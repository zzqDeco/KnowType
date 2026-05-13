import Foundation
import XCTest
import KnowTypeCore
@testable import KnowTypeProviders

private struct StubProvider: LLMProvider {
    let providerName = "stub"

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        LLMResponse(candidates: [])
    }
}

private struct StubProfileStore: ProviderProfileStore {
    var result: Result<ProviderProfilesFile, Error>

    func loadProfiles() throws -> ProviderProfilesFile {
        try result.get()
    }

    func saveProfiles(_ profiles: ProviderProfilesFile) throws {}
}

private struct FailingSecretStore: SecretStore {
    func secret(named name: String) throws -> String? {
        throw ProviderError.invalidResponse("secret unavailable")
    }

    func setSecret(_ value: String, named name: String) throws {}

    func deleteSecret(named name: String) throws {}
}

private final class ConfigurationCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedConfigurations: [ProviderConfiguration] = []

    func append(_ configuration: ProviderConfiguration) {
        lock.lock()
        defer { lock.unlock() }
        capturedConfigurations.append(configuration)
    }

    var configurations: [ProviderConfiguration] {
        lock.lock()
        defer { lock.unlock() }
        return capturedConfigurations
    }
}

final class ProviderProfileTests: XCTestCase {
    func testProfileResolverDoesNotPersistAPIKeyInProfile() throws {
        let profile = ProviderProfileDefaults.openAICompatible(
            baseURL: URL(string: "https://api.example.com/v1")!,
            model: "example-model",
            secretName: "knowtype.test.key"
        )
        let resolver = ProviderProfileResolver(
            secretStore: DictionarySecretStore(values: ["knowtype.test.key": "secret-value"])
        )

        let configuration = try resolver.configuration(for: profile)

        XCTAssertEqual(configuration.apiKey, "secret-value")
        XCTAssertEqual(profile.secretName, "knowtype.test.key")
    }

    func testProfileResolverRequiresNamedSecret() throws {
        let profile = ProviderProfileDefaults.openAICompatible(secretName: "missing")
        let resolver = ProviderProfileResolver(secretStore: DictionarySecretStore(values: [:]))

        XCTAssertThrowsError(try resolver.configuration(for: profile)) { error in
            XCTAssertEqual(error as? ProviderError, .missingAPIKey)
        }
    }

    func testFileProviderProfileStoreRoundTripsProfiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = FileProviderProfileStore(fileURL: directory.appendingPathComponent("providers.json"))
        let profiles = ProviderProfilesFile(profiles: [
            ProviderProfileDefaults.openAICompatible()
        ])

        try store.saveProfiles(profiles)
        let loaded = try store.loadProfiles()

        XCTAssertEqual(loaded, profiles)
    }

    func testInMemorySecretStoreSupportsMutation() throws {
        let store = InMemorySecretStore()

        try store.setSecret("value", named: "key")
        XCTAssertEqual(try store.secret(named: "key"), "value")

        try store.deleteSecret(named: "key")
        XCTAssertNil(try store.secret(named: "key"))
    }

    func testRuntimeLoaderBuildsDefaultProviderWithResolvedSecret() throws {
        let defaultProfile = ProviderProfileDefaults.openAICompatible(
            baseURL: URL(string: "https://api.example.com/v1")!,
            model: "example-model",
            secretName: "secret-name"
        )
        let nonDefaultProfile = ProviderProfile(
            displayName: "Local",
            kind: .ollamaNative,
            baseURL: URL(string: "http://localhost:11434")!,
            model: "llama",
            isDefault: false
        )
        let capture = ConfigurationCapture()
        let loader = ProviderRuntimeLoader(
            profileStore: StubProfileStore(result: .success(ProviderProfilesFile(profiles: [
                nonDefaultProfile,
                defaultProfile
            ]))),
            secretStore: DictionarySecretStore(values: ["secret-name": "resolved-secret"]),
            providerBuilder: { configuration in
                capture.append(configuration)
                return StubProvider()
            }
        )

        let provider = loader.loadDefaultProvider()

        XCTAssertEqual(provider?.providerName, "stub")
        XCTAssertEqual(capture.configurations, [
            ProviderConfiguration(
                kind: .openAIChat,
                baseURL: URL(string: "https://api.example.com/v1")!,
                apiKey: "resolved-secret",
                model: "example-model"
            )
        ])
    }

    func testRuntimeLoaderReturnsNilWhenNoDefaultProfileExists() throws {
        let loader = ProviderRuntimeLoader(
            profileStore: StubProfileStore(result: .success(ProviderProfilesFile(profiles: [
                ProviderProfile(
                    displayName: "Local",
                    kind: .ollamaNative,
                    baseURL: URL(string: "http://localhost:11434")!,
                    model: "llama"
                )
            ]))),
            secretStore: DictionarySecretStore(values: [:]),
            providerBuilder: { _ in
                XCTFail("Provider builder should not be called without a default profile")
                return StubProvider()
            }
        )

        XCTAssertNil(loader.loadDefaultProvider())
    }

    func testRuntimeLoaderReturnsNilWhenStoreSecretOrFactoryFails() throws {
        let profile = ProviderProfileDefaults.openAICompatible(secretName: "secret-name")

        let storeFailure = ProviderRuntimeLoader(
            profileStore: StubProfileStore(result: .failure(ProviderError.invalidResponse("bad file"))),
            secretStore: DictionarySecretStore(values: ["secret-name": "secret"]),
            providerBuilder: { _ in StubProvider() }
        )
        XCTAssertNil(storeFailure.loadDefaultProvider())

        let secretFailure = ProviderRuntimeLoader(
            profileStore: StubProfileStore(result: .success(ProviderProfilesFile(profiles: [profile]))),
            secretStore: FailingSecretStore(),
            providerBuilder: { _ in StubProvider() }
        )
        XCTAssertNil(secretFailure.loadDefaultProvider())

        let factoryFailure = ProviderRuntimeLoader(
            profileStore: StubProfileStore(result: .success(ProviderProfilesFile(profiles: [profile]))),
            secretStore: DictionarySecretStore(values: ["secret-name": "secret"]),
            providerBuilder: { _ in
                throw ProviderError.unsupportedKind(.openAIChat)
            }
        )
        XCTAssertNil(factoryFailure.loadDefaultProvider())
    }
}
