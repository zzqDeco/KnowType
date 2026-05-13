import Combine
import Foundation
import KnowTypeProviders

@MainActor
public final class ProviderProfilesViewModel: ObservableObject {
    @Published public private(set) var profiles: [ProviderProfile]
    @Published public var selectedProfileID: String?
    @Published public var draft: ProviderProfileDraft
    @Published public private(set) var validationErrors: [String]
    @Published public private(set) var lastErrorMessage: String?

    private let profileStore: any ProviderProfileStore
    private let secretStore: any SecretStore
    private var file: ProviderProfilesFile

    public init(
        profileStore: any ProviderProfileStore,
        secretStore: any SecretStore,
        loadDefaultsWhenEmpty: Bool = true
    ) {
        self.profileStore = profileStore
        self.secretStore = secretStore
        self.validationErrors = []

        let resolvedFile: ProviderProfilesFile
        let resolvedProfiles: [ProviderProfile]
        let resolvedErrorMessage: String?

        do {
            let loaded = try profileStore.loadProfiles()
            if loaded.profiles.isEmpty && loadDefaultsWhenEmpty {
                let defaults = ProviderProfileTemplates.defaultProfiles()
                resolvedFile = ProviderProfilesFile(schemaVersion: loaded.schemaVersion, profiles: defaults)
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
    }

    public func createProfile(kind: ProviderKind) {
        let profile = ProviderProfileTemplates.defaultProfile(kind: kind)
        selectedProfileID = profile.id
        draft = ProviderProfileDraft(profile: profile)
        validationErrors = []
    }

    @discardableResult
    public func saveDraft() -> Bool {
        validationErrors = validate(draft)
        guard validationErrors.isEmpty else {
            return false
        }

        do {
            var profile = try draft.makeProfile()
            if !draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let secretName = profile.secretName ?? Self.secretName(for: profile.id)
                try secretStore.setSecret(draft.apiKey, named: secretName)
                profile.secretName = secretName
            }

            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index] = profile
            } else {
                profiles.append(profile)
            }

            if profile.isDefault {
                profiles = profiles.map { existing in
                    var updated = existing
                    updated.isDefault = existing.id == profile.id
                    return updated
                }
            }

            if !profiles.contains(where: \.isDefault), let firstIndex = profiles.indices.first {
                profiles[firstIndex].isDefault = true
            }

            file.profiles = profiles
            try profileStore.saveProfiles(file)
            selectedProfileID = profile.id
            draft = ProviderProfileDraft(profile: profile)
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    public func setDefaultProfile(id: String) throws {
        guard profiles.contains(where: { $0.id == id }) else {
            return
        }
        profiles = profiles.map { profile in
            var updated = profile
            updated.isDefault = profile.id == id
            return updated
        }
        file.profiles = profiles
        try profileStore.saveProfiles(file)
        if selectedProfileID == id, let profile = profiles.first(where: { $0.id == id }) {
            draft = ProviderProfileDraft(profile: profile)
        }
    }

    public func validate(_ draft: ProviderProfileDraft) -> [String] {
        var errors: [String] = []
        if draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Display name is required.")
        }
        if URL(string: draft.baseURL)?.scheme.map({ $0 == "http" || $0 == "https" }) != true {
            errors.append("Base URL must be an HTTP or HTTPS URL.")
        }
        if draft.kind != .customHTTP && draft.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Model is required.")
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

    private static func secretName(for profileID: String) -> String {
        "knowtype.provider.\(profileID).apiKey"
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
        guard let url = URL(string: baseURL) else {
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

public enum ProviderProfileTemplates {
    public static func defaultProfiles() -> [ProviderProfile] {
        ProviderKind.allCases.map { defaultProfile(kind: $0, isDefault: $0 == .openAIChat) }
    }

    public static func defaultProfile(kind: ProviderKind, isDefault: Bool = false) -> ProviderProfile {
        switch kind {
        case .openAIChat:
            return ProviderProfile(
                displayName: "OpenAI Chat",
                kind: kind,
                baseURL: URL(string: "https://api.openai.com")!,
                model: "gpt-4.1-mini",
                secretName: "knowtype.openai_chat.apiKey",
                isDefault: isDefault
            )
        case .openAIResponses:
            return ProviderProfile(
                displayName: "OpenAI Responses",
                kind: kind,
                baseURL: URL(string: "https://api.openai.com")!,
                model: "gpt-4.1-mini",
                secretName: "knowtype.openai_responses.apiKey",
                isDefault: isDefault
            )
        case .anthropicMessages:
            return ProviderProfile(
                displayName: "Anthropic Messages",
                kind: kind,
                baseURL: URL(string: "https://api.anthropic.com")!,
                model: "claude-3-5-haiku-latest",
                headers: ["anthropic-version": "2023-06-01"],
                secretName: "knowtype.anthropic_messages.apiKey",
                isDefault: isDefault
            )
        case .geminiNative:
            return ProviderProfile(
                displayName: "Gemini Native",
                kind: kind,
                baseURL: URL(string: "https://generativelanguage.googleapis.com")!,
                model: "gemini-1.5-flash",
                secretName: "knowtype.gemini_native.apiKey",
                isDefault: isDefault
            )
        case .ollamaNative:
            return ProviderProfile(
                displayName: "Ollama Native",
                kind: kind,
                baseURL: URL(string: "http://localhost:11434")!,
                model: "llama3.2",
                isDefault: isDefault
            )
        case .customHTTP:
            return ProviderProfile(
                displayName: "Custom HTTP",
                kind: kind,
                baseURL: URL(string: "https://api.example.com/v1/complete")!,
                model: "",
                secretName: "knowtype.custom_http.apiKey",
                customBodyTemplate: #"{"request":{{request_json}}}"#,
                customResponsePath: "candidates",
                isDefault: isDefault
            )
        }
    }
}
