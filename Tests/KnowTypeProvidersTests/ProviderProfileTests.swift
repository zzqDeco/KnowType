import Foundation
import XCTest
@testable import KnowTypeProviders

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
}
