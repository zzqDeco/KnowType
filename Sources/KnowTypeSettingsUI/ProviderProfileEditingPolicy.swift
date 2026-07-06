import Foundation
import KnowTypeProviders

enum ProviderProfileEditingPolicy {
    typealias SecretResolver = (String) throws -> String?

    static var defaultProviderValidationError: String {
        SettingsLocalization.string("settings.provider.validation.defaultProviderRequired")
    }

    struct SavePlan {
        var profile: ProviderProfile
        var updatedProfiles: [ProviderProfile]
        var updatedFile: ProviderProfilesFile
        var selectedProfileID: String
        var postSaveDraft: ProviderProfileDraft
        var secretMutation: SecretMutation
    }

    enum SecretMutation: Equatable {
        case none
        case set(value: String, secretName: String, oldSecretName: String?)
        case delete(secretName: String)
    }

    static func secretName(for profileID: String) -> String {
        "knowtype.provider.\(profileID).apiKey"
    }

    static func profileScopedSecrets(_ profiles: [ProviderProfile]) -> [ProviderProfile] {
        profiles.map { profile in
            var scoped = profile
            if scoped.secretName != nil {
                scoped.secretName = secretName(for: scoped.id)
            }
            return scoped
        }
    }

    static func validate(_ draft: ProviderProfileDraft) -> [String] {
        var errors: [String] = []
        if draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(SettingsLocalization.string("settings.provider.validation.displayNameRequired"))
        }
        let validBaseURL = validHTTPURL(draft.baseURL)
        if validBaseURL == nil {
            errors.append(SettingsLocalization.string("settings.provider.validation.baseURLHTTP"))
        }
        if requiresModel(kind: draft.kind, baseURL: validBaseURL) {
            let model = draft.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if model.isEmpty || isRemoteOpenAIPlaceholderModel(
                kind: draft.kind,
                baseURL: validBaseURL,
                model: model
            ) {
                errors.append(SettingsLocalization.string("settings.provider.validation.modelRequired"))
            }
        }
        if draft.timeoutSeconds <= 0 {
            errors.append(SettingsLocalization.string("settings.provider.validation.timeoutPositive"))
        }
        if draft.kind == .customHTTP {
            if draft.customBodyTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(SettingsLocalization.string("settings.provider.validation.customHTTPBodyRequired"))
            }
            if draft.customResponsePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(SettingsLocalization.string("settings.provider.validation.customHTTPResponsePathRequired"))
            }
        }
        return errors
    }

    static func saveValidationErrors(draft: ProviderProfileDraft, profiles: [ProviderProfile]) -> [String] {
        var errors = validate(draft)
        if !draft.isDefault && !profiles.contains(where: { $0.id != draft.id && $0.isDefault }) {
            errors.append(defaultProviderValidationError)
        }
        return errors
    }

    static func saveOnlyValidationErrors(from errors: [String]) -> [String] {
        errors.filter { $0 == defaultProviderValidationError }
    }

    static func mergedValidationErrors(_ groups: [String]...) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        for error in groups.flatMap({ $0 }) where seen.insert(error).inserted {
            merged.append(error)
        }
        return merged
    }

    static func makeSavePlan(
        draft: ProviderProfileDraft,
        profiles: [ProviderProfile],
        file: ProviderProfilesFile,
        secretResolver: SecretResolver
    ) throws -> SavePlan {
        var profile = try draft.makeProfile()
        let existingProfile = profiles.first(where: { $0.id == profile.id })
        let mutation = secretMutation(
            for: profile,
            existingProfile: existingProfile,
            draftAPIKey: draft.apiKey
        )
        try validateSecretAvailability(
            for: profile,
            existingProfile: existingProfile,
            mutation: mutation,
            secretResolver: secretResolver
        )

        switch mutation {
        case .set(_, let secretName, _):
            profile.secretName = secretName
        case .delete:
            profile.secretName = nil
        case .none:
            if requiresSecret(profile) {
                profile.secretName = existingProfile?.secretName ?? profile.secretName ?? secretName(for: profile.id)
            } else if acceptsOptionalSecret(profile),
                      canReuseExistingSecret(for: profile, existingProfile: existingProfile) {
                profile.secretName = try retainedOptionalSecretName(
                    from: existingProfile,
                    secretResolver: secretResolver
                )
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
        return SavePlan(
            profile: profile,
            updatedProfiles: updatedProfiles,
            updatedFile: updatedFile,
            selectedProfileID: profile.id,
            postSaveDraft: ProviderProfileDraft(profile: profile),
            secretMutation: mutation
        )
    }

    static func makeConnectionConfiguration(
        draft: ProviderProfileDraft,
        profiles: [ProviderProfile],
        secretResolver: SecretResolver
    ) throws -> ProviderConfiguration {
        var profile = try draft.makeProfile()
        let existingProfile = profiles.first(where: { $0.id == profile.id })
        let trimmedAPIKey = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey: String?
        if trimmedAPIKey.isEmpty {
            if shouldClearBlankOptionalSecret(for: profile, existingProfile: existingProfile) {
                apiKey = nil
            } else if canReuseExistingSecret(for: profile, existingProfile: existingProfile) {
                apiKey = try resolvedExistingSecret(for: profile, secretResolver: secretResolver)
            } else {
                apiKey = nil
            }
            if requiresSecret(profile), apiKey == nil {
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

    static func applySecretMutation(
        _ mutation: SecretMutation,
        updatedProfiles: [ProviderProfile],
        secretStore: any SecretStore
    ) throws {
        switch mutation {
        case .none:
            return
        case .set(let value, let secretName, let oldSecretName):
            try secretStore.setSecret(value, named: secretName)
            if let oldSecretName,
               oldSecretName != secretName,
               !isSecretReferenced(oldSecretName, in: updatedProfiles) {
                do {
                    try secretStore.deleteSecret(named: oldSecretName)
                } catch {
                    try? secretStore.deleteSecret(named: secretName)
                    throw error
                }
            }
        case .delete(let secretName):
            if !isSecretReferenced(secretName, in: updatedProfiles) {
                try secretStore.deleteSecret(named: secretName)
            }
        }
    }

    static func requiresSecret(_ profile: ProviderProfile) -> Bool {
        switch profile.kind {
        case .openAIChat, .openAIResponses:
            return !isLocalBaseURL(profile.baseURL)
        case .anthropicMessages, .geminiNative:
            return true
        case .ollamaNative, .customHTTP:
            return false
        }
    }

    static func acceptsOptionalSecret(_ profile: ProviderProfile) -> Bool {
        switch profile.kind {
        case .openAIChat, .openAIResponses:
            return isLocalBaseURL(profile.baseURL)
        case .customHTTP:
            return true
        case .anthropicMessages, .geminiNative, .ollamaNative:
            return false
        }
    }

    static func canReuseExistingSecret(for profile: ProviderProfile, existingProfile: ProviderProfile?) -> Bool {
        guard let existingProfile,
              profile.secretName == existingProfile.secretName else {
            return false
        }
        return profile.kind == existingProfile.kind
            && credentialEndpointScope(profile.baseURL) == credentialEndpointScope(existingProfile.baseURL)
    }

    private static func validateSecretAvailability(
        for profile: ProviderProfile,
        existingProfile: ProviderProfile?,
        mutation: SecretMutation,
        secretResolver: SecretResolver
    ) throws {
        guard requiresSecret(profile), case .none = mutation else {
            return
        }
        guard canReuseExistingSecret(for: profile, existingProfile: existingProfile) else {
            throw ProviderProfilesViewModelError.missingAPIKey
        }
        guard let secretName = profile.secretName,
              let existingSecret = try secretResolver(secretName),
              !existingSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderProfilesViewModelError.missingAPIKey
        }
    }

    private static func retainedOptionalSecretName(
        from existingProfile: ProviderProfile?,
        secretResolver: SecretResolver
    ) throws -> String? {
        guard let secretName = existingProfile?.secretName else {
            return nil
        }
        guard let existingSecret = try secretResolver(secretName),
              !existingSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return secretName
    }

    private static func resolvedExistingSecret(
        for profile: ProviderProfile,
        secretResolver: SecretResolver
    ) throws -> String? {
        guard let secretName = profile.secretName,
              let existingSecret = try secretResolver(secretName) else {
            return nil
        }
        let trimmed = existingSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
                if acceptsOptionalSecret(profile),
                   !canReuseExistingSecret(for: profile, existingProfile: existingProfile),
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

    private static func credentialEndpointScope(_ url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""
        let port = url.port ?? defaultPort(for: scheme)
        let portValue = port.map(String.init) ?? ""
        return "\(scheme)://\(host):\(portValue)"
    }

    private static func defaultPort(for scheme: String) -> Int? {
        switch scheme {
        case "http":
            return 80
        case "https":
            return 443
        default:
            return nil
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
