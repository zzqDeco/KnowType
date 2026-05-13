import Foundation
import KnowTypeCore

public struct ProviderRuntimeLoader: Sendable {
    public typealias ProviderBuilder = @Sendable (ProviderConfiguration) throws -> any LLMProvider

    private let profileStore: any ProviderProfileStore
    private let secretStore: any SecretStore
    private let providerBuilder: ProviderBuilder

    public init(
        profileStore: any ProviderProfileStore,
        secretStore: any SecretStore,
        providerBuilder: @escaping ProviderBuilder = { configuration in
            try ProviderFactory.makeProvider(configuration: configuration)
        }
    ) {
        self.profileStore = profileStore
        self.secretStore = secretStore
        self.providerBuilder = providerBuilder
    }

    public func loadDefaultProvider() -> (any LLMProvider)? {
        do {
            let profilesFile = try profileStore.loadProfiles()
            guard let defaultProfile = profilesFile.profiles.first(where: \.isDefault) else {
                return nil
            }

            let configuration = try ProviderProfileResolver(secretStore: secretStore)
                .configuration(for: defaultProfile)
            return try providerBuilder(configuration)
        } catch {
            return nil
        }
    }

    public static func loadDefaultProvider() -> (any LLMProvider)? {
        do {
            let profileStore = try FileProviderProfileStore.defaultStore()
            return defaultLoader(profileStore: profileStore).loadDefaultProvider()
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
}
