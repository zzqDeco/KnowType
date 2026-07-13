import CryptoKit
import Foundation
import KnowTypeCore

public struct ProviderRuntimeLoadResult: Sendable {
    public var revision: UInt64
    public var fingerprint: String
    public var provider: (any LLMProvider)?

    public init(
        revision: UInt64,
        fingerprint: String,
        provider: (any LLMProvider)?
    ) {
        self.revision = revision
        self.fingerprint = fingerprint
        self.provider = provider
    }
}

public struct ProviderRuntimeLoader: Sendable {
    public typealias ProviderBuilder = @Sendable (ProviderConfiguration) throws -> any LLMProvider

    private let profileStore: any ProviderProfileStore
    private let secretStore: any SecretStore
    private let providerBuilder: ProviderBuilder
    private let loadDefaultsWhenEmpty: Bool

    public init(
        profileStore: any ProviderProfileStore,
        secretStore: any SecretStore,
        loadDefaultsWhenEmpty: Bool = true,
        providerBuilder: @escaping ProviderBuilder = { configuration in
            try ProviderFactory.makeProvider(configuration: configuration)
        }
    ) {
        self.profileStore = profileStore
        self.secretStore = secretStore
        self.providerBuilder = providerBuilder
        self.loadDefaultsWhenEmpty = loadDefaultsWhenEmpty
    }

    public func loadDefaultProvider() -> (any LLMProvider)? {
        loadDefaultProviderRuntime()?.provider
    }

    public func loadProviderRevision() -> UInt64? {
        try? profileStore.loadProfiles().revision
    }

    public func loadDefaultProviderRuntime() -> ProviderRuntimeLoadResult? {
        do {
            let profilesFile = try ProviderProfileTemplates.loadProfilesMigratingRetiredModels(
                from: profileStore
            )
            let profiles = profilesFile.profiles.isEmpty && loadDefaultsWhenEmpty
                ? ProviderProfileTemplates.defaultProfiles()
                : profilesFile.profiles
            guard let defaultProfile = profiles.first(where: \.isDefault) else {
                return ProviderRuntimeLoadResult(
                    revision: profilesFile.revision,
                    fingerprint: Self.fingerprint(for: nil),
                    provider: nil
                )
            }

            do {
                let configuration = try ProviderProfileResolver(secretStore: secretStore)
                    .configuration(for: defaultProfile)
                return ProviderRuntimeLoadResult(
                    revision: profilesFile.revision,
                    fingerprint: Self.fingerprint(for: configuration),
                    provider: try providerBuilder(configuration)
                )
            } catch {
                return ProviderRuntimeLoadResult(
                    revision: profilesFile.revision,
                    fingerprint: Self.fingerprint(for: defaultProfile),
                    provider: nil
                )
            }
        } catch {
            return nil
        }
    }

    public static func loadDefaultProvider(createProfileDirectory: Bool = true) -> (any LLMProvider)? {
        loadDefaultProviderRuntime(createProfileDirectory: createProfileDirectory)?.provider
    }

    public static func loadDefaultProviderRuntime(
        createProfileDirectory: Bool = true
    ) -> ProviderRuntimeLoadResult? {
        do {
            let profileStore = try FileProviderProfileStore.defaultStore(createDirectory: createProfileDirectory)
            return defaultLoader(profileStore: profileStore).loadDefaultProviderRuntime()
        } catch {
            return nil
        }
    }

    public static func loadDefaultProviderRevision(createProfileDirectory: Bool = true) -> UInt64? {
        do {
            let profileStore = try FileProviderProfileStore.defaultStore(createDirectory: createProfileDirectory)
            return defaultLoader(profileStore: profileStore).loadProviderRevision()
        } catch {
            return nil
        }
    }

    private static func defaultLoader(profileStore: any ProviderProfileStore) -> ProviderRuntimeLoader {
        #if canImport(Security)
        return ProviderRuntimeLoader(
            profileStore: profileStore,
            secretStore: KeychainSecretStore()
        )
        #else
        return ProviderRuntimeLoader(
            profileStore: profileStore,
            secretStore: DictionarySecretStore(values: [:])
        )
        #endif
    }

    private static func fingerprint(for configuration: ProviderConfiguration?) -> String {
        guard let configuration,
              let data = try? JSONEncoder.sorted.encode(configuration) else {
            return fingerprint(data: Data("provider:none".utf8))
        }
        return fingerprint(data: data)
    }

    private static func fingerprint(for profile: ProviderProfile) -> String {
        let data = (try? JSONEncoder.sorted.encode(profile)) ?? Data("provider:invalid".utf8)
        return fingerprint(data: data)
    }

    private static func fingerprint(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
