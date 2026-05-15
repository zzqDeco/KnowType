import Combine
import Foundation
import KnowTypeCore
import KnowTypeProviders

@MainActor
public final class ProviderProfilesViewModel: ObservableObject {
    public typealias ConnectionTester = @Sendable (ProviderConfiguration) async throws -> ProviderConnectionDiagnosticResult

    @Published public private(set) var profiles: [ProviderProfile]
    @Published public var selectedProfileID: String?
    @Published public var draft: ProviderProfileDraft {
        didSet {
            if draft != oldValue {
                resetConnectionStatus()
            }
        }
    }
    @Published public private(set) var validationErrors: [String]
    @Published public private(set) var lastErrorMessage: String?
    @Published public private(set) var isPersistenceBlocked: Bool
    @Published public private(set) var connectionStatus: ProviderConnectionStatus

    private let profileStore: any ProviderProfileStore
    private let secretStore: any SecretStore
    private let connectionTester: ConnectionTester
    private var file: ProviderProfilesFile
    private var persistenceBlockedError: Error?
    private var connectionTestGeneration: UInt64 = 0

    public init(
        profileStore: any ProviderProfileStore,
        secretStore: any SecretStore,
        loadDefaultsWhenEmpty: Bool = true,
        connectionTester: @escaping ConnectionTester = { configuration in
            try await ProviderConnectionDiagnostic().test(configuration: configuration)
        }
    ) {
        self.profileStore = profileStore
        self.secretStore = secretStore
        self.connectionTester = connectionTester
        self.validationErrors = []
        self.connectionStatus = .idle

        let resolvedFile: ProviderProfilesFile
        let resolvedProfiles: [ProviderProfile]
        let resolvedErrorMessage: String?

        do {
            let loaded = try profileStore.loadProfiles()
            if loaded.profiles.isEmpty && loadDefaultsWhenEmpty {
                let defaults = Self.profileScopedSecrets(ProviderProfileTemplates.defaultProfiles())
                resolvedFile = loaded
                resolvedProfiles = defaults
            } else {
                resolvedFile = loaded
                resolvedProfiles = loaded.profiles
            }
            resolvedErrorMessage = nil
        } catch {
            resolvedFile = ProviderProfilesFile()
            resolvedProfiles = []
            resolvedErrorMessage = error.localizedDescription
        }

        let firstProfile = resolvedProfiles.first
        self.file = resolvedFile
        self.profiles = resolvedProfiles
        self.selectedProfileID = firstProfile?.id
        self.draft = ProviderProfileDraft(profile: firstProfile ?? ProviderProfileTemplates.defaultProfile(kind: .openAIChat))
        self.lastErrorMessage = resolvedErrorMessage
        self.persistenceBlockedError = resolvedErrorMessage == nil ? nil : ProviderProfilesViewModelError.loadFailed(resolvedErrorMessage ?? "")
        self.isPersistenceBlocked = self.persistenceBlockedError != nil
    }

    public convenience init() throws {
        #if canImport(Security)
        try self.init(profileStore: FileProviderProfileStore.defaultStore(), secretStore: KeychainSecretStore())
        #else
        try self.init(profileStore: FileProviderProfileStore.defaultStore(), secretStore: InMemorySecretStore())
        #endif
    }

    public func selectProfile(id: String) {
        guard let profile = profiles.first(where: { $0.id == id }) else {
            return
        }
        selectedProfileID = id
        draft = ProviderProfileDraft(profile: profile)
        validationErrors = []
        resetConnectionStatus()
    }

    public func createProfile(kind: ProviderKind) {
        var profile = ProviderProfileTemplates.defaultProfile(kind: kind)
        if profile.secretName != nil {
            profile.secretName = Self.secretName(for: profile.id)
        }
        selectedProfileID = profile.id
        draft = ProviderProfileDraft(profile: profile)
        validationErrors = []
        resetConnectionStatus()
    }

    public func changeDraftKind(_ kind: ProviderKind) {
        guard draft.kind != kind else {
            return
        }

        let template = ProviderProfileTemplates.defaultProfile(kind: kind)
        draft.kind = kind
        draft.baseURL = template.baseURL.absoluteString
        draft.model = template.model
        draft.timeoutSeconds = template.timeoutSeconds
        draft.headers = template.headers
        if template.secretName == nil {
            draft.secretName = nil
            draft.apiKey = ""
        } else {
            let existingProfile = profiles.first(where: { $0.id == draft.id })
            draft.secretName = existingProfile?.secretName ?? Self.secretName(for: draft.id)
        }
        draft.customBodyTemplate = template.customBodyTemplate ?? ""
        draft.customResponsePath = template.customResponsePath ?? ""
        validationErrors = []
        resetConnectionStatus()
    }

    @discardableResult
    public func saveDraft() -> Bool {
        if let persistenceBlockedError {
            lastErrorMessage = persistenceBlockedError.localizedDescription
            return false
        }

        validationErrors = validate(draft)
        if !draft.isDefault && !profiles.contains(where: { $0.id != draft.id && $0.isDefault }) {
            validationErrors.append("At least one default provider is required.")
        }
        guard validationErrors.isEmpty else {
            return false
        }

        do {
            var profile = try draft.makeProfile()
            let existingProfile = profiles.first(where: { $0.id == profile.id })
            let secretMutation = Self.secretMutation(
                for: profile,
                existingProfile: existingProfile,
                draftAPIKey: draft.apiKey
            )
            try validateSecretAvailability(for: profile, mutation: secretMutation)

            switch secretMutation {
            case .set(_, let secretName, _):
                profile.secretName = secretName
            case .delete:
                profile.secretName = nil
            case .none:
                if Self.requiresSecret(profile) {
                    profile.secretName = existingProfile?.secretName ?? profile.secretName ?? Self.secretName(for: profile.id)
                } else if Self.acceptsOptionalSecret(profile) {
                    profile.secretName = try retainedOptionalSecretName(from: existingProfile)
                } else {
                    profile.secretName = nil
                }
            }

            var updatedProfiles = profiles
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                updatedProfiles[index] = profile
            } else {
                updatedProfiles.append(profile)
            }

            if profile.isDefault {
                updatedProfiles = updatedProfiles.map { existing in
                    var updated = existing
                    updated.isDefault = existing.id == profile.id
                    return updated
                }
            }

            var updatedFile = file
            updatedFile.profiles = updatedProfiles
            try profileStore.saveProfiles(updatedFile)
            do {
                try apply(secretMutation, updatedProfiles: updatedProfiles)
            } catch {
                let secretMutationError = error
                do {
                    try profileStore.saveProfiles(file)
                } catch {
                    throw ProviderProfilesViewModelError.rollbackFailed(
                        secretMutation: secretMutationError.localizedDescription,
                        rollback: error.localizedDescription
                    )
                }
                throw secretMutationError
            }
            profiles = updatedProfiles
            file = updatedFile
            selectedProfileID = profile.id
            draft = ProviderProfileDraft(profile: profile)
            lastErrorMessage = nil
            resetConnectionStatus()
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    public func setDefaultProfile(id: String) throws {
        if let persistenceBlockedError {
            lastErrorMessage = persistenceBlockedError.localizedDescription
            throw persistenceBlockedError
        }

        guard profiles.contains(where: { $0.id == id }) else {
            return
        }
        let updatedProfiles = profiles.map { profile in
            var updated = profile
            updated.isDefault = profile.id == id
            return updated
        }
        var updatedFile = file
        updatedFile.profiles = updatedProfiles
        do {
            try profileStore.saveProfiles(updatedFile)
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
        profiles = updatedProfiles
        file = updatedFile
        lastErrorMessage = nil
        if selectedProfileID == id, let profile = profiles.first(where: { $0.id == id }) {
            draft = ProviderProfileDraft(profile: profile)
        }
    }

    @discardableResult
    public func testDraftConnection() async -> Bool {
        if let persistenceBlockedError {
            let message = persistenceBlockedError.localizedDescription
            lastErrorMessage = message
            connectionStatus = .failure(message)
            return false
        }

        let snapshot = ConnectionTestSnapshot(
            selectedProfileID: selectedProfileID,
            draft: draft
        )

        validationErrors = validate(snapshot.draft)
        guard validationErrors.isEmpty else {
            connectionStatus = .failure("Fix validation errors before testing.")
            return false
        }

        connectionTestGeneration &+= 1
        let generation = connectionTestGeneration
        do {
            let configuration = try connectionTestConfiguration(for: snapshot.draft)
            connectionStatus = .testing
            let result = try await connectionTester(configuration)
            guard isCurrentConnectionTest(generation: generation, snapshot: snapshot) else {
                return false
            }
            connectionStatus = .success("Connected to \(result.providerName). Received \(result.candidateCount) candidate(s).")
            lastErrorMessage = nil
            return true
        } catch {
            guard isCurrentConnectionTest(generation: generation, snapshot: snapshot) else {
                return false
            }
            let message = error.localizedDescription
            connectionStatus = .failure(message)
            return false
        }
    }

    public func validate(_ draft: ProviderProfileDraft) -> [String] {
        var errors: [String] = []
        if draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Display name is required.")
        }
        let validBaseURL = Self.validHTTPURL(draft.baseURL)
        if validBaseURL == nil {
            errors.append("Base URL must be an HTTP or HTTPS URL.")
        }
        if Self.requiresModel(kind: draft.kind, baseURL: validBaseURL) {
            let model = draft.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if model.isEmpty || Self.isRemoteOpenAIPlaceholderModel(
                kind: draft.kind,
                baseURL: validBaseURL,
                model: model
            ) {
                errors.append("Model is required.")
            }
        }
        if draft.timeoutSeconds <= 0 {
            errors.append("Timeout must be greater than zero.")
        }
        if draft.kind == .customHTTP {
            if draft.customBodyTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("Custom HTTP body template is required.")
            }
            if draft.customResponsePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("Custom HTTP response path is required.")
            }
        }
        return errors
    }

    private func connectionTestConfiguration(for draft: ProviderProfileDraft) throws -> ProviderConfiguration {
        var profile = try draft.makeProfile()
        let trimmedAPIKey = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey: String?
        if trimmedAPIKey.isEmpty {
            apiKey = try resolvedExistingSecret(for: profile)
            if Self.requiresSecret(profile), apiKey == nil {
                throw ProviderProfilesViewModelError.missingAPIKey
            }
        } else {
            apiKey = trimmedAPIKey
        }

        profile.secretName = apiKey == nil ? nil : profile.secretName
        return ProviderConfiguration(
            kind: profile.kind,
            baseURL: profile.baseURL,
            apiKey: apiKey,
            model: profile.model,
            timeoutSeconds: profile.timeoutSeconds,
            headers: profile.headers,
            customBodyTemplate: profile.customBodyTemplate,
            customResponsePath: profile.customResponsePath
        )
    }

    private func resolvedExistingSecret(for profile: ProviderProfile) throws -> String? {
        guard let secretName = profile.secretName,
              let existingSecret = try secretStore.secret(named: secretName) else {
            return nil
        }
        let trimmed = existingSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resetConnectionStatus() {
        connectionTestGeneration &+= 1
        connectionStatus = .idle
    }

    private func isCurrentConnectionTest(
        generation: UInt64,
        snapshot: ConnectionTestSnapshot
    ) -> Bool {
        generation == connectionTestGeneration
            && selectedProfileID == snapshot.selectedProfileID
            && draft == snapshot.draft
    }

    private static func secretName(for profileID: String) -> String {
        "knowtype.provider.\(profileID).apiKey"
    }

    private static func profileScopedSecrets(_ profiles: [ProviderProfile]) -> [ProviderProfile] {
        profiles.map { profile in
            var scoped = profile
            if scoped.secretName != nil {
                scoped.secretName = secretName(for: scoped.id)
            }
            return scoped
        }
    }

    private static func requiresSecret(_ profile: ProviderProfile) -> Bool {
        switch profile.kind {
        case .openAIChat, .openAIResponses:
            return !isLocalBaseURL(profile.baseURL)
        case .anthropicMessages, .geminiNative:
            return true
        case .ollamaNative, .customHTTP:
            return false
        }
    }

    private static func acceptsOptionalSecret(_ profile: ProviderProfile) -> Bool {
        switch profile.kind {
        case .openAIChat, .openAIResponses:
            return isLocalBaseURL(profile.baseURL)
        case .customHTTP:
            return true
        case .anthropicMessages, .geminiNative, .ollamaNative:
            return false
        }
    }

    private static func requiresModel(kind: ProviderKind, baseURL: URL?) -> Bool {
        switch kind {
        case .anthropicMessages, .geminiNative, .ollamaNative:
            return true
        case .openAIChat, .openAIResponses:
            guard let baseURL else {
                return false
            }
            return !isLocalBaseURL(baseURL)
        case .customHTTP:
            return false
        }
    }

    private static func isRemoteOpenAIPlaceholderModel(
        kind: ProviderKind,
        baseURL: URL?,
        model: String
    ) -> Bool {
        switch kind {
        case .openAIChat, .openAIResponses:
            guard let baseURL,
                  !isLocalBaseURL(baseURL) else {
                return false
            }
            return OpenAICompatibleModelDiscovery.requiresDiscovery(model)
        case .anthropicMessages, .geminiNative, .ollamaNative, .customHTTP:
            return false
        }
    }

    private static func isLocalBaseURL(_ url: URL) -> Bool {
        guard let host = url.host(percentEncoded: false)?.lowercased() else {
            return false
        }
        return host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
            || host.hasSuffix(".local")
    }

    private func validateSecretAvailability(for profile: ProviderProfile, mutation: SecretMutation) throws {
        guard Self.requiresSecret(profile), case .none = mutation else {
            return
        }
        guard let secretName = profile.secretName,
              let existingSecret = try secretStore.secret(named: secretName),
              !existingSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderProfilesViewModelError.missingAPIKey
        }
    }

    private func retainedOptionalSecretName(from existingProfile: ProviderProfile?) throws -> String? {
        guard let secretName = existingProfile?.secretName else {
            return nil
        }
        guard let existingSecret = try secretStore.secret(named: secretName),
              !existingSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return secretName
    }

    private enum SecretMutation {
        case none
        case set(value: String, secretName: String, oldSecretName: String?)
        case delete(secretName: String)
    }

    private static func secretMutation(
        for profile: ProviderProfile,
        existingProfile: ProviderProfile?,
        draftAPIKey: String
    ) -> SecretMutation {
        let trimmedAPIKey = draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if requiresSecret(profile) || acceptsOptionalSecret(profile) {
            guard !trimmedAPIKey.isEmpty else {
                if shouldClearBlankOptionalSecret(for: profile, existingProfile: existingProfile),
                   let oldSecretName = existingProfile?.secretName {
                    return .delete(secretName: oldSecretName)
                }
                return .none
            }
            let secretName = secretName(for: profile.id)
            return .set(value: trimmedAPIKey, secretName: secretName, oldSecretName: existingProfile?.secretName)
        }

        guard let oldSecretName = existingProfile?.secretName else {
            return .none
        }
        return .delete(secretName: oldSecretName)
    }

    private static func shouldClearBlankOptionalSecret(
        for profile: ProviderProfile,
        existingProfile: ProviderProfile?
    ) -> Bool {
        guard let existingProfile else {
            return false
        }
        switch profile.kind {
        case .openAIChat, .openAIResponses:
            return isLocalBaseURL(profile.baseURL)
                && (profile.kind != existingProfile.kind || !isLocalBaseURL(existingProfile.baseURL))
        case .anthropicMessages, .geminiNative, .ollamaNative, .customHTTP:
            return false
        }
    }

    private func apply(_ mutation: SecretMutation, updatedProfiles: [ProviderProfile]) throws {
        switch mutation {
        case .none:
            return
        case .set(let value, let secretName, let oldSecretName):
            try secretStore.setSecret(value, named: secretName)
            if let oldSecretName,
               oldSecretName != secretName,
               !Self.isSecretReferenced(oldSecretName, in: updatedProfiles) {
                do {
                    try secretStore.deleteSecret(named: oldSecretName)
                } catch {
                    try? secretStore.deleteSecret(named: secretName)
                    throw error
                }
            }
        case .delete(let secretName):
            if !Self.isSecretReferenced(secretName, in: updatedProfiles) {
                try secretStore.deleteSecret(named: secretName)
            }
        }
    }

    private static func isSecretReferenced(_ secretName: String, in profiles: [ProviderProfile]) -> Bool {
        profiles.contains { $0.secretName == secretName }
    }

    private static func validHTTPURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme,
              (scheme == "http" || scheme == "https"),
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }
}

private struct ConnectionTestSnapshot: Equatable {
    var selectedProfileID: String?
    var draft: ProviderProfileDraft
}

public enum ProviderProfilesViewModelError: Error, Equatable, LocalizedError {
    case loadFailed(String)
    case missingAPIKey
    case rollbackFailed(secretMutation: String, rollback: String)

    public var errorDescription: String? {
        switch self {
        case .loadFailed(let message):
            return message
        case .missingAPIKey:
            return "API key is required for this provider."
        case .rollbackFailed(let secretMutation, let rollback):
            return "Failed to update provider secret: \(secretMutation). Also failed to restore providers.json: \(rollback). Provider metadata may be staged on disk."
        }
    }
}

public enum ProviderConnectionStatus: Equatable, Sendable {
    case idle
    case testing
    case success(String)
    case failure(String)

    public var message: String? {
        switch self {
        case .idle, .testing:
            return nil
        case .success(let message), .failure(let message):
            return message
        }
    }

    public var isTesting: Bool {
        if case .testing = self {
            return true
        }
        return false
    }
}

public struct ProviderProfileDraft: Equatable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var kind: ProviderKind
    public var baseURL: String
    public var model: String
    public var timeoutSeconds: TimeInterval
    public var headers: [String: String]
    public var secretName: String?
    public var apiKey: String
    public var customBodyTemplate: String
    public var customResponsePath: String
    public var isDefault: Bool

    public init(profile: ProviderProfile) {
        self.id = profile.id
        self.displayName = profile.displayName
        self.kind = profile.kind
        self.baseURL = profile.baseURL.absoluteString
        self.model = profile.model
        self.timeoutSeconds = profile.timeoutSeconds
        self.headers = profile.headers
        self.secretName = profile.secretName
        self.apiKey = ""
        self.customBodyTemplate = profile.customBodyTemplate ?? ""
        self.customResponsePath = profile.customResponsePath ?? ""
        self.isDefault = profile.isDefault
    }

    public func makeProfile() throws -> ProviderProfile {
        guard let url = URL(string: baseURL),
              let scheme = url.scheme,
              (scheme == "http" || scheme == "https"),
              url.host?.isEmpty == false else {
            throw ProviderProfileDraftError.invalidBaseURL
        }
        return ProviderProfile(
            id: id,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            baseURL: url,
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            timeoutSeconds: timeoutSeconds,
            headers: headers,
            secretName: secretName,
            customBodyTemplate: emptyToNil(customBodyTemplate),
            customResponsePath: emptyToNil(customResponsePath),
            isDefault: isDefault
        )
    }

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum ProviderProfileDraftError: Error, Equatable {
    case invalidBaseURL
}
