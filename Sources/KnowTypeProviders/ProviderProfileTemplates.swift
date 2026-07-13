import Foundation

public enum ProviderProfileTemplates {
    private struct RetiredModelMigration {
        var kind: ProviderKind
        var officialHost: String
        var officialPaths: Set<String>
        var retiredModel: String
        var replacementModel: String
    }

    private static let retiredModelMigrations = [
        RetiredModelMigration(
            kind: .anthropicMessages,
            officialHost: "api.anthropic.com",
            officialPaths: ["", "/", "/v1", "/v1/"],
            retiredModel: "claude-3-5-haiku-latest",
            replacementModel: "claude-haiku-4-5-20251001"
        ),
        RetiredModelMigration(
            kind: .geminiNative,
            officialHost: "generativelanguage.googleapis.com",
            officialPaths: ["", "/"],
            retiredModel: "gemini-1.5-flash",
            replacementModel: "gemini-3.5-flash"
        )
    ]

    public static func defaultProfiles() -> [ProviderProfile] {
        ProviderKind.allCases.map { defaultProfile(kind: $0, isDefault: $0 == .openAIChat) }
    }

    public static func defaultProfile(kind: ProviderKind, isDefault: Bool = false) -> ProviderProfile {
        switch kind {
        case .openAIChat:
            return ProviderProfile(
                displayName: "Local OpenAI Compatible",
                kind: kind,
                baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
                model: "",
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
                model: "claude-haiku-4-5-20251001",
                headers: ["anthropic-version": "2023-06-01"],
                secretName: "knowtype.anthropic_messages.apiKey",
                isDefault: isDefault
            )
        case .geminiNative:
            return ProviderProfile(
                displayName: "Gemini Native",
                kind: kind,
                baseURL: URL(string: "https://generativelanguage.googleapis.com")!,
                model: "gemini-3.5-flash",
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
                customBodyTemplate: #"{"request":{{request_json}}}"#,
                customResponsePath: "candidates",
                isDefault: isDefault
            )
        }
    }

    public static func loadProfilesMigratingRetiredModels(
        from store: any ProviderProfileStore
    ) throws -> ProviderProfilesFile {
        var loaded = try store.loadProfiles()
        var mayRetryRevisionConflict = true

        while true {
            let migratedProfiles = migratingRetiredModels(in: loaded.profiles)
            guard migratedProfiles != loaded.profiles else {
                return loaded
            }

            do {
                return try store.transactProfiles(expectedRevision: loaded.revision) { current in
                    var updated = current
                    updated.profiles = migratingRetiredModels(in: current.profiles)
                    return updated
                }
            } catch let error as ProviderProfileStoreError {
                guard mayRetryRevisionConflict,
                      case .revisionConflict = error else {
                    throw error
                }
                mayRetryRevisionConflict = false
                loaded = try store.loadProfiles()
            }
        }
    }

    static func migratingRetiredModels(in profiles: [ProviderProfile]) -> [ProviderProfile] {
        profiles.map { profile in
            guard let migration = retiredModelMigrations.first(where: { migration in
                profile.kind == migration.kind
                    && profile.model == migration.retiredModel
                    && isOfficialEndpoint(
                        profile.baseURL,
                        host: migration.officialHost,
                        paths: migration.officialPaths
                    )
            }) else {
                return profile
            }

            var migrated = profile
            migrated.model = migration.replacementModel
            return migrated
        }
    }

    private static func isOfficialEndpoint(
        _ url: URL,
        host: String,
        paths: Set<String>
    ) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == host,
              components.port == nil || components.port == 443,
              components.user == nil,
              components.password == nil,
              components.percentEncodedQuery == nil,
              components.fragment == nil,
              paths.contains(components.percentEncodedPath) else {
            return false
        }
        return true
    }
}
