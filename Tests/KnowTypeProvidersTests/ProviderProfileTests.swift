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

private struct ResponseProvider: LLMProvider {
    let providerName: String
    let response: LLMResponse

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        response
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

        XCTAssertEqual(loaded.schemaVersion, ProviderProfilesFile.currentSchemaVersion)
        XCTAssertEqual(loaded.revision, 1)
        XCTAssertEqual(loaded.profiles, profiles.profiles)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.lockFileURL.path))
    }

    func testV1FileDecodesRevisionZeroAndUpgradesOnFirstTransaction() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-v1-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("providers.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":1,"profiles":[]}"#.utf8).write(to: fileURL)
        let store = FileProviderProfileStore(fileURL: fileURL)

        let legacy = try store.loadProfiles()
        XCTAssertEqual(legacy.schemaVersion, 1)
        XCTAssertEqual(legacy.revision, 0)

        let upgraded = try store.transactProfiles(expectedRevision: 0) { $0 }
        XCTAssertEqual(upgraded.schemaVersion, 2)
        XCTAssertEqual(upgraded.revision, 1)
        XCTAssertEqual(try store.loadProfiles(), upgraded)
    }

    func testFutureProviderProfileSchemaIsRejected() throws {
        let data = Data(#"{"schemaVersion":3,"revision":9,"profiles":[]}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ProviderProfilesFile.self, from: data)) { error in
            XCTAssertEqual(error as? ProviderProfileStoreError, .unsupportedSchemaVersion(3))
        }
    }

    func testV2ProviderProfileSchemaRequiresRevision() throws {
        let data = Data(#"{"schemaVersion":2,"profiles":[]}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ProviderProfilesFile.self, from: data))
    }

    func testFileStoreCASRejectsStaleRevisionWithoutLosingProfiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-cas-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeA = FileProviderProfileStore(fileURL: directory.appendingPathComponent("providers.json"))
        let storeB = FileProviderProfileStore(fileURL: storeA.fileURL)
        let profile = ProviderProfileDefaults.openAICompatible()

        let committed = try storeA.transactProfiles(expectedRevision: 0) { current in
            var updated = current
            updated.profiles = [profile]
            return updated
        }
        XCTAssertEqual(committed.revision, 1)

        XCTAssertThrowsError(
            try storeB.transactProfiles(expectedRevision: 0) { current in
                var updated = current
                updated.profiles = []
                return updated
            }
        ) { error in
            XCTAssertEqual(
                error as? ProviderProfileStoreError,
                .revisionConflict(expected: 0, actual: 1)
            )
        }
        XCTAssertEqual(try storeA.loadProfiles().profiles, [profile])
    }

    func testFileStorePostsRevisionSignalOnlyAfterSuccessfulCommit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-signal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let signal = RecordingProviderProfileRevisionSignal()
        let store = FileProviderProfileStore(
            fileURL: directory.appendingPathComponent("providers.json"),
            revisionSignal: signal
        )

        _ = try store.transactProfiles(expectedRevision: 0) { $0 }
        XCTAssertEqual(signal.revisions, [1])

        XCTAssertThrowsError(try store.transactProfiles(expectedRevision: 0) { $0 })
        XCTAssertEqual(signal.revisions, [1])
    }

    func testPrivacySafeEndpointSummaryMatchesSharedFixtures() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/provider-endpoint-summary.json")
        let fixture = try JSONDecoder().decode(
            ProviderEndpointSummaryFixture.self,
            from: Data(contentsOf: fixtureURL)
        )

        for item in fixture.cases {
            let url = try XCTUnwrap(URL(string: item.input))
            XCTAssertEqual(
                ProviderEndpointURLPolicy.privacySafeSummary(url),
                item.summary,
                item.input
            )
        }
    }

    func testProfileResolverRejectsUserInfoAndFragmentButAllowsQuery() throws {
        let resolver = ProviderProfileResolver(secretStore: DictionarySecretStore(values: [:]))
        let unsafeURLs = [
            "https://user:pass@example.com/v1",
            "https://example.com/v1#debug"
        ]
        for value in unsafeURLs {
            let profile = ProviderProfile(
                displayName: "Unsafe",
                kind: .ollamaNative,
                baseURL: try XCTUnwrap(URL(string: value)),
                model: "model"
            )
            XCTAssertThrowsError(try resolver.configuration(for: profile))
        }

        let queryProfile = ProviderProfile(
            displayName: "Compatible",
            kind: .ollamaNative,
            baseURL: URL(string: "https://example.com/v1?runtime=compatible")!,
            model: "model"
        )
        XCTAssertEqual(
            try resolver.configuration(for: queryProfile).baseURL.absoluteString,
            "https://example.com/v1?runtime=compatible"
        )
    }

    func testDefaultProfileStoreCanOpenWithoutCreatingDirectory() throws {
        let fileManager = FileManager.default
        let applicationSupport = fileManager.temporaryDirectory
            .appendingPathComponent("provider-profile-no-create-\(UUID().uuidString)", isDirectory: true)
        let knowTypeDirectory = applicationSupport.appendingPathComponent("KnowType", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: applicationSupport)
        }

        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport,
            createDirectory: false
        )
        let profiles = try store.loadProfiles()

        XCTAssertEqual(profiles, ProviderProfilesFile())
        XCTAssertFalse(fileManager.fileExists(atPath: knowTypeDirectory.path))
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

    func testRuntimeLoaderBuildsSeededDefaultProviderWhenStoreIsEmpty() throws {
        let capture = ConfigurationCapture()
        let loader = ProviderRuntimeLoader(
            profileStore: StubProfileStore(result: .success(ProviderProfilesFile())),
            secretStore: DictionarySecretStore(values: [:]),
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
                baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
                model: ""
            )
        ])
    }

    func testRuntimeLoaderCanDisableSeededDefaultsForEmptyStore() throws {
        let loader = ProviderRuntimeLoader(
            profileStore: StubProfileStore(result: .success(ProviderProfilesFile())),
            secretStore: DictionarySecretStore(values: [:]),
            loadDefaultsWhenEmpty: false,
            providerBuilder: { _ in
                XCTFail("Provider builder should not be called when seeded defaults are disabled")
                return StubProvider()
            }
        )

        XCTAssertNil(loader.loadDefaultProvider())
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

    func testProviderConnectionDiagnosticReturnsCandidateSummary() async throws {
        let diagnostic = ProviderConnectionDiagnostic(providerBuilder: { _ in
            ResponseProvider(
                providerName: "diagnostic-stub",
                response: LLMResponse(candidates: [
                    LLMCandidate(text: "works")
                ])
            )
        })

        let result = try await diagnostic.test(
            configuration: ProviderConfiguration(
                kind: .openAIChat,
                baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
                model: ""
            )
        )

        XCTAssertEqual(result.providerName, "diagnostic-stub")
        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.firstCandidateText, "works")
    }

    func testProviderConnectionDiagnosticRejectsEmptyOrBlankCandidates() async throws {
        let diagnostic = ProviderConnectionDiagnostic(providerBuilder: { _ in
            ResponseProvider(providerName: "diagnostic-stub", response: LLMResponse(candidates: [
                LLMCandidate(text: "  \n")
            ]))
        })

        do {
            _ = try await diagnostic.test(
                configuration: ProviderConfiguration(
                    kind: .openAIChat,
                    baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
                    model: ""
                )
            )
            XCTFail("Expected empty diagnostic response to fail")
        } catch {
            XCTAssertEqual(error as? ProviderError, .invalidResponse("diagnostic returned no usable continuation candidates"))
        }
    }

    func testProviderConnectionDiagnosticRejectsCandidatesThatRepeatLockedPrefixOnly() async throws {
        let diagnostic = ProviderConnectionDiagnostic(providerBuilder: { _ in
            ResponseProvider(providerName: "diagnostic-stub", response: LLMResponse(candidates: [
                LLMCandidate(text: "KnowType")
            ]))
        })

        do {
            _ = try await diagnostic.test(
                configuration: ProviderConfiguration(
                    kind: .openAIChat,
                    baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
                    model: ""
                )
            )
            XCTFail("Expected unusable continuation to fail")
        } catch {
            XCTAssertEqual(error as? ProviderError, .invalidResponse("diagnostic returned no usable continuation candidates"))
        }
    }

    func testProviderConnectionDiagnosticCountsOnlyUsableCandidates() async throws {
        let diagnostic = ProviderConnectionDiagnostic(providerBuilder: { _ in
            ResponseProvider(
                providerName: "diagnostic-stub",
                response: LLMResponse(candidates: [
                    LLMCandidate(text: " "),
                    LLMCandidate(text: "usable")
                ])
            )
        })

        let result = try await diagnostic.test(
            configuration: ProviderConfiguration(
                kind: .openAIChat,
                baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
                model: ""
            )
        )

        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.firstCandidateText, "usable")
    }

    func testProviderErrorUsesReadableLocalizedDescription() {
        XCTAssertEqual(
            ProviderError.invalidResponse("diagnostic returned no candidates").localizedDescription,
            "Invalid provider response: diagnostic returned no candidates"
        )
    }
}

private final class RecordingProviderProfileRevisionSignal: ProviderProfileRevisionSignaling, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UInt64] = []

    var revisions: [UInt64] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func postProviderProfilesChanged(revision: UInt64) {
        lock.lock()
        values.append(revision)
        lock.unlock()
    }
}

private struct ProviderEndpointSummaryFixture: Decodable {
    struct Item: Decodable {
        var input: String
        var summary: String
    }

    var cases: [Item]
}
