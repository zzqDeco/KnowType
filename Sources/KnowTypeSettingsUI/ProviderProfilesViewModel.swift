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
                resetDraftConnectionStatus()
            }
        }
    }
    @Published public private(set) var validationErrors: [String]
    @Published public private(set) var lastErrorMessage: String?
    @Published public private(set) var isPersistenceBlocked: Bool
    @Published public private(set) var connectionStatus: ProviderConnectionStatus
    @Published public private(set) var draftConnectionStatus: ProviderConnectionStatus
    @Published public private(set) var savedConnectionStatus: ProviderConnectionStatus

    private let profileStore: any ProviderProfileStore
    private let secretStore: any SecretStore
    private let connectionTester: ConnectionTester
    private var file: ProviderProfilesFile
    private var persistenceBlockedError: Error?
    private var draftConnectionTestGeneration: UInt64 = 0
    private var savedConnectionTestGeneration: UInt64 = 0

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
        self.draftConnectionStatus = .idle
        self.savedConnectionStatus = .idle

        let resolvedFile: ProviderProfilesFile
        let resolvedProfiles: [ProviderProfile]
        let resolvedErrorMessage: String?

        do {
            let loaded = try profileStore.loadProfiles()
            if loaded.profiles.isEmpty && loadDefaultsWhenEmpty {
                let defaults = ProviderProfileEditingPolicy.profileScopedSecrets(ProviderProfileTemplates.defaultProfiles())
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
        resetDraftConnectionStatus()
    }

    public func createProfile(kind: ProviderKind) {
        var profile = ProviderProfileTemplates.defaultProfile(kind: kind)
        if profile.secretName != nil {
            profile.secretName = ProviderProfileEditingPolicy.secretName(for: profile.id)
        }
        selectedProfileID = profile.id
        draft = ProviderProfileDraft(profile: profile)
        validationErrors = []
        resetDraftConnectionStatus()
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
            draft.secretName = existingProfile?.secretName ?? ProviderProfileEditingPolicy.secretName(for: draft.id)
        }
        draft.customBodyTemplate = template.customBodyTemplate ?? ""
        draft.customResponsePath = template.customResponsePath ?? ""
        validationErrors = []
        resetDraftConnectionStatus()
    }

    @discardableResult
    public func saveDraft() -> Bool {
        if let persistenceBlockedError {
            lastErrorMessage = persistenceBlockedError.localizedDescription
            return false
        }

        validationErrors = ProviderProfileEditingPolicy.saveValidationErrors(draft: draft, profiles: profiles)
        guard validationErrors.isEmpty else {
            return false
        }

        do {
            let plan = try ProviderProfileEditingPolicy.makeSavePlan(
                draft: draft,
                profiles: profiles,
                file: file,
                secretResolver: { try secretStore.secret(named: $0) }
            )
            try profileStore.saveProfiles(plan.updatedFile)
            do {
                try ProviderProfileEditingPolicy.applySecretMutation(
                    plan.secretMutation,
                    updatedProfiles: plan.updatedProfiles,
                    secretStore: secretStore
                )
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
            profiles = plan.updatedProfiles
            file = plan.updatedFile
            selectedProfileID = plan.selectedProfileID
            draft = plan.postSaveDraft
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

        guard let profile = profiles.first(where: { $0.id == id }) else {
            return
        }
        do {
            try validateCurrentServiceCandidate(profile)
        } catch {
            savedConnectionStatus = .failure(error.localizedDescription)
            throw error
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
        reconcileDraftDefaultState(activeProfileID: id)
        resetSavedConnectionStatus()
    }

    @discardableResult
    public func testDraftConnection() async -> Bool {
        if let persistenceBlockedError {
            let message = persistenceBlockedError.localizedDescription
            lastErrorMessage = message
            setDraftConnectionStatus(.failure(message))
            return false
        }

        let snapshot = ConnectionTestSnapshot(
            selectedProfileID: selectedProfileID,
            draft: draft
        )

        let connectionValidationErrors = ProviderProfileEditingPolicy.validate(snapshot.draft)
        guard connectionValidationErrors.isEmpty else {
            validationErrors = ProviderProfileEditingPolicy.mergedValidationErrors(
                connectionValidationErrors,
                ProviderProfileEditingPolicy.saveOnlyValidationErrors(from: validationErrors)
            )
            setDraftConnectionStatus(.failure(SettingsLocalization.string("settings.provider.connection.fixValidationBeforeTesting")))
            return false
        }
        validationErrors = ProviderProfileEditingPolicy.saveOnlyValidationErrors(from: validationErrors)

        draftConnectionTestGeneration &+= 1
        let generation = draftConnectionTestGeneration
        do {
            let configuration = try ProviderProfileEditingPolicy.makeConnectionConfiguration(
                draft: snapshot.draft,
                profiles: profiles,
                secretResolver: { try secretStore.secret(named: $0) }
            )
            setDraftConnectionStatus(.testing)
            let result = try await connectionTester(configuration)
            guard isCurrentConnectionTest(generation: generation, snapshot: snapshot) else {
                return false
            }
            setDraftConnectionStatus(
                .success(
                    String(
                        format: SettingsLocalization.string("settings.provider.connection.success"),
                        result.providerName,
                        result.candidateCount
                    )
                )
            )
            return true
        } catch {
            guard isCurrentConnectionTest(generation: generation, snapshot: snapshot) else {
                return false
            }
            let message = error.localizedDescription
            setDraftConnectionStatus(.failure(message))
            return false
        }
    }

    @discardableResult
    public func testSavedProfileConnection(id profileID: String? = nil) async -> Bool {
        if let persistenceBlockedError {
            let message = persistenceBlockedError.localizedDescription
            lastErrorMessage = message
            savedConnectionStatus = .failure(message)
            return false
        }

        guard let profile = savedConnectionProfile(id: profileID) else {
            savedConnectionStatus = .failure(SettingsLocalization.string("settings.provider.serviceSummary.empty"))
            return false
        }

        let savedDraft = ProviderProfileDraft(profile: profile)
        let connectionValidationErrors = ProviderProfileEditingPolicy.validate(savedDraft)
        guard connectionValidationErrors.isEmpty else {
            validationErrors = ProviderProfileEditingPolicy.mergedValidationErrors(
                connectionValidationErrors,
                ProviderProfileEditingPolicy.saveOnlyValidationErrors(from: validationErrors)
            )
            savedConnectionStatus = .failure(SettingsLocalization.string("settings.provider.connection.fixValidationBeforeTesting"))
            return false
        }
        validationErrors = ProviderProfileEditingPolicy.saveOnlyValidationErrors(from: validationErrors)

        savedConnectionTestGeneration &+= 1
        let generation = savedConnectionTestGeneration
        let snapshot = SavedConnectionTestSnapshot(profile: profile)
        do {
            let configuration = try ProviderProfileEditingPolicy.makeConnectionConfiguration(
                draft: savedDraft,
                profiles: profiles,
                secretResolver: { try secretStore.secret(named: $0) }
            )
            savedConnectionStatus = .testing
            let result = try await connectionTester(configuration)
            guard isCurrentSavedConnectionTest(generation: generation, snapshot: snapshot) else {
                return false
            }
            savedConnectionStatus = .success(
                String(
                    format: SettingsLocalization.string("settings.provider.connection.success"),
                    result.providerName,
                    result.candidateCount
                )
            )
            return true
        } catch {
            guard isCurrentSavedConnectionTest(generation: generation, snapshot: snapshot) else {
                return false
            }
            let message = error.localizedDescription
            savedConnectionStatus = .failure(message)
            return false
        }
    }

    public func validate(_ draft: ProviderProfileDraft) -> [String] {
        ProviderProfileEditingPolicy.validate(draft)
    }

    private func resetConnectionStatus() {
        resetDraftConnectionStatus()
        resetSavedConnectionStatus()
    }

    private func validateCurrentServiceCandidate(_ profile: ProviderProfile) throws {
        let savedDraft = ProviderProfileDraft(profile: profile)
        if let message = ProviderProfileEditingPolicy.validate(savedDraft).first {
            throw ProviderProfilesViewModelError.validationFailed(message)
        }
        _ = try ProviderProfileEditingPolicy.makeConnectionConfiguration(
            draft: savedDraft,
            profiles: profiles,
            secretResolver: { try secretStore.secret(named: $0) }
        )
    }

    private func reconcileDraftDefaultState(activeProfileID: String) {
        let shouldBeDefault = draft.id == activeProfileID
        if draft.isDefault != shouldBeDefault {
            draft.isDefault = shouldBeDefault
        }
    }

    private func resetDraftConnectionStatus() {
        draftConnectionTestGeneration &+= 1
        setDraftConnectionStatus(.idle)
    }

    private func resetSavedConnectionStatus() {
        savedConnectionTestGeneration &+= 1
        savedConnectionStatus = .idle
    }

    private func setDraftConnectionStatus(_ status: ProviderConnectionStatus) {
        draftConnectionStatus = status
        connectionStatus = status
    }

    private func isCurrentConnectionTest(
        generation: UInt64,
        snapshot: ConnectionTestSnapshot
    ) -> Bool {
        generation == draftConnectionTestGeneration
            && selectedProfileID == snapshot.selectedProfileID
            && draft == snapshot.draft
    }

    private func isCurrentSavedConnectionTest(
        generation: UInt64,
        snapshot: SavedConnectionTestSnapshot
    ) -> Bool {
        generation == savedConnectionTestGeneration
            && savedConnectionProfile(id: snapshot.profile.id) == snapshot.profile
    }

    private func savedConnectionProfile(id profileID: String?) -> ProviderProfile? {
        if let profileID {
            return profiles.first { $0.id == profileID }
        }
        return profiles.first(where: \.isDefault)
    }
}

private struct ConnectionTestSnapshot: Equatable {
    var selectedProfileID: String?
    var draft: ProviderProfileDraft
}

private struct SavedConnectionTestSnapshot: Equatable {
    var profile: ProviderProfile
}

public enum ProviderProfilesViewModelError: Error, Equatable, LocalizedError {
    case loadFailed(String)
    case missingAPIKey
    case rollbackFailed(secretMutation: String, rollback: String)
    case validationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .loadFailed(let message):
            return message
        case .missingAPIKey:
            return SettingsLocalization.string("settings.provider.error.missingAPIKey")
        case .rollbackFailed(let secretMutation, let rollback):
            return String(
                format: SettingsLocalization.string("settings.provider.error.rollbackFailed"),
                secretMutation,
                rollback
            )
        case .validationFailed(let message):
            return message
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
