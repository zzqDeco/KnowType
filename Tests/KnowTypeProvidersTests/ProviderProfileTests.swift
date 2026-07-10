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

private final class DeleteFailingSecretStore: SecretStore, @unchecked Sendable {
    private let backing: InMemorySecretStore

    init(values: [String: String]) {
        backing = InMemorySecretStore(values: values)
    }

    func secret(named name: String) throws -> String? {
        try backing.secret(named: name)
    }

    func setSecret(_ value: String, named name: String) throws {
        try backing.setSecret(value, named: name)
    }

    func deleteSecret(named name: String) throws {
        throw ProviderError.invalidResponse("delete unavailable")
    }
}

private struct PreV2ProviderProfilesFile: Codable {
    var schemaVersion: Int
    var profiles: [ProviderProfile]
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

    func testDefaultProfileStoreUsesGenerationSeparatedPaths() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-paths-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }

        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )

        XCTAssertEqual(store.fileURL.lastPathComponent, "providers.v2.json")
        XCTAssertEqual(store.legacyFileURL?.lastPathComponent, "providers.json")
        XCTAssertEqual(store.legacySnapshotURL?.lastPathComponent, "providers.legacy.json")
    }

    func testDefaultProfileStoreRequiresMigrationInsteadOfTreatingLegacyAsEmpty() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-migration-required-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let legacyURL = try XCTUnwrap(store.legacyFileURL)
        let legacy = PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [])
        try JSONEncoder().encode(legacy).write(to: legacyURL, options: [.atomic])

        XCTAssertThrowsError(try store.loadProfiles()) { error in
            XCTAssertEqual(
                error as? ProviderProfileStoreError,
                .migrationRequired(path: legacyURL.path)
            )
        }
        XCTAssertThrowsError(try store.transactProfiles(expectedRevision: 0) { $0 }) { error in
            XCTAssertEqual(
                error as? ProviderProfileStoreError,
                .migrationRequired(path: legacyURL.path)
            )
        }
    }

    func testLegacyProfileMigrationRekeysCredentialsAndTombstonesOldPath() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-migrate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let legacyURL = try XCTUnwrap(store.legacyFileURL)
        let snapshotURL = try XCTUnwrap(store.legacySnapshotURL)
        let profile = ProviderProfile(
            id: "profile-a",
            displayName: "Legacy",
            kind: .openAIChat,
            baseURL: URL(string: "https://example.com/v1")!,
            model: "model",
            secretName: "legacy.secret",
            isDefault: true
        )
        let legacyData = try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [profile])
        )
        try legacyData.write(to: legacyURL, options: [.atomic])
        let secrets = InMemorySecretStore(values: ["legacy.secret": "secret-value"])

        let result = try store.migrateLegacyProfiles(
            secretStore: secrets,
            credentialReferenceGenerator: { "new.\($0)" }
        )

        XCTAssertEqual(
            result,
            ProviderProfileStorageMigrationResult(
                status: .migrated,
                revision: 1,
                profileCount: 1,
                credentialsRekeyed: 1
            )
        )
        let migrated = try store.loadProfiles()
        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertEqual(migrated.revision, 1)
        XCTAssertEqual(migrated.profiles.first?.secretName, "new.profile-a")
        XCTAssertEqual(try secrets.secret(named: "new.profile-a"), "secret-value")
        XCTAssertEqual(try secrets.secret(named: "legacy.secret"), "secret-value")
        XCTAssertEqual(try Data(contentsOf: snapshotURL), legacyData)
        XCTAssertEqual(store.legacyStorageState(), .tombstone)
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                PreV2ProviderProfilesFile.self,
                from: Data(contentsOf: legacyURL)
            )
        )
    }

    func testMigrationRecoversInterruptedProvisionalTombstoneFromSnapshot() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-provisional-recovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let legacyURL = try XCTUnwrap(store.legacyFileURL)
        let snapshotURL = try XCTUnwrap(store.legacySnapshotURL)
        let profile = ProviderProfile(
            id: "recovered",
            displayName: "Recovered",
            kind: .openAIChat,
            baseURL: URL(string: "https://example.com/v1")!,
            model: "model",
            isDefault: true
        )
        let legacyData = try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [profile])
        )
        try legacyData.write(to: snapshotURL, options: [.atomic])
        let claimURL = legacyURL.deletingLastPathComponent().appendingPathComponent(
            "\(FileProviderProfileStore.legacyConflictFilenamePrefix)interrupted.json"
        )
        try legacyData.write(to: claimURL, options: [.atomic])
        try Data(
            """
            {
              "canonicalFile" : "providers.v2.json",
              "canonicalExpected" : false,
              "profiles" : [],
              "schemaVersion" : "migrated-to-providers.v2.json"
            }
            """.utf8
        ).write(to: legacyURL, options: [.atomic])
        XCTAssertThrowsError(try store.loadProfiles()) { error in
            XCTAssertEqual(
                error as? ProviderProfileStoreError,
                .migrationRequired(path: legacyURL.path)
            )
        }

        let result = try store.migrateLegacyProfiles(secretStore: InMemorySecretStore())

        XCTAssertEqual(result.status, .migrated)
        XCTAssertEqual(result.profileCount, 1)
        XCTAssertEqual(try store.loadProfiles().profiles.map(\.id), ["recovered"])
        let tombstone = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: legacyURL)) as? [String: Any]
        )
        XCTAssertEqual(tombstone["canonicalExpected"] as? Bool, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: claimURL.path))
    }

    func testMigrationRecoversInterruptedClaimBeforeProvisionalTombstone() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-claim-recovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let legacyURL = try XCTUnwrap(store.legacyFileURL)
        let snapshotURL = try XCTUnwrap(store.legacySnapshotURL)
        let legacyData = try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [])
        )
        let claimURL = legacyURL.deletingLastPathComponent().appendingPathComponent(
            "\(FileProviderProfileStore.legacyConflictFilenamePrefix)interrupted.json"
        )
        try legacyData.write(to: snapshotURL, options: [.atomic])
        try legacyData.write(to: claimURL, options: [.atomic])

        XCTAssertThrowsError(try store.loadProfiles()) { error in
            XCTAssertEqual(
                error as? ProviderProfileStoreError,
                .migrationRequired(path: legacyURL.path)
            )
        }
        let result = try store.migrateLegacyProfiles(secretStore: InMemorySecretStore())

        XCTAssertEqual(result.status, .migrated)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertEqual(store.legacyStorageState(), .tombstone)
        XCTAssertFalse(FileManager.default.fileExists(atPath: claimURL.path))
    }

    func testMigrationRejectsSnapshotWithoutMatchingInterruptedClaim() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-unproven-recovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let legacyURL = try XCTUnwrap(store.legacyFileURL)
        let snapshotURL = try XCTUnwrap(store.legacySnapshotURL)
        let legacyData = try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [])
        )
        try legacyData.write(to: snapshotURL, options: [.atomic])

        XCTAssertThrowsError(try store.loadProfiles()) { error in
            XCTAssertEqual(
                error as? ProviderProfileStoreError,
                .migrationRequired(path: legacyURL.path)
            )
        }
        XCTAssertThrowsError(
            try store.migrateLegacyProfiles(secretStore: InMemorySecretStore())
        ) { error in
            XCTAssertEqual(error as? ProviderProfileStoreError, .migrationRollbackFailed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertEqual(try Data(contentsOf: snapshotURL), legacyData)
    }

    func testMigrationDoesNotOverwriteWriterPayloadArrivingDuringCutover() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-cutover-writer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let directory = applicationSupport.appendingPathComponent("KnowType", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyURL = directory.appendingPathComponent(FileProviderProfileStore.legacyFilename)
        let initialData = try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [])
        )
        let lateWriterProfile = ProviderProfile(
            id: "late",
            displayName: "Late writer",
            kind: .openAIChat,
            baseURL: URL(string: "https://late.example.com/v1")!,
            model: "late-model",
            isDefault: true
        )
        let lateWriterData = try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [lateWriterProfile])
        )
        try initialData.write(to: legacyURL, options: [.atomic])
        let store = FileProviderProfileStore(
            fileURL: directory.appendingPathComponent(FileProviderProfileStore.canonicalFilename),
            legacyFileURL: legacyURL,
            legacySnapshotURL: directory.appendingPathComponent(FileProviderProfileStore.legacySnapshotFilename),
            migrationCutoverHook: {
                try lateWriterData.write(to: legacyURL, options: [.atomic])
            }
        )

        XCTAssertThrowsError(try store.migrateLegacyProfiles(secretStore: InMemorySecretStore())) { error in
            XCTAssertEqual(
                error as? ProviderProfileStoreError,
                .legacyChangedDuringMigration(path: legacyURL.path)
            )
        }
        XCTAssertEqual(try Data(contentsOf: legacyURL), lateWriterData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        let conflictURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix(FileProviderProfileStore.legacyConflictFilenamePrefix)
        }
        XCTAssertEqual(conflictURLs.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(conflictURLs.first)), initialData)
    }

    func testLegacyMigrationRollbackRestoresMetadataBeforeRemovingNewCredential() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-migration-rollback-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let legacyURL = try XCTUnwrap(store.legacyFileURL)
        let snapshotURL = try XCTUnwrap(store.legacySnapshotURL)
        let profile = ProviderProfile(
            id: "profile-a",
            displayName: "Legacy",
            kind: .openAIChat,
            baseURL: URL(string: "https://example.com/v1")!,
            model: "model",
            secretName: "legacy.secret",
            isDefault: true
        )
        let legacyData = try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [profile])
        )
        try legacyData.write(to: legacyURL, options: [.atomic])
        let secrets = InMemorySecretStore(values: ["legacy.secret": "secret-value"])
        _ = try store.migrateLegacyProfiles(
            secretStore: secrets,
            credentialReferenceGenerator: { "new.\($0)" }
        )

        let rollback = try store.rollbackLegacyMigration(
            expectedCanonicalRevision: 1,
            secretStore: secrets
        )

        XCTAssertEqual(
            rollback,
            ProviderProfileStorageRollbackResult(
                credentialsRemoved: 1,
                credentialCleanupFailures: 0
            )
        )
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
        XCTAssertNil(try secrets.secret(named: "new.profile-a"))
        XCTAssertEqual(try secrets.secret(named: "legacy.secret"), "secret-value")
    }

    func testLegacyMigrationRollbackKeepsRestoredMetadataWhenCredentialCleanupFails() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-migration-cleanup-failure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let legacyURL = try XCTUnwrap(store.legacyFileURL)
        let profile = ProviderProfile(
            id: "profile-a",
            displayName: "Legacy",
            kind: .openAIChat,
            baseURL: URL(string: "https://example.com/v1")!,
            model: "model",
            secretName: "legacy.secret",
            isDefault: true
        )
        let legacyData = try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [profile])
        )
        try legacyData.write(to: legacyURL, options: [.atomic])
        let secrets = DeleteFailingSecretStore(values: ["legacy.secret": "secret-value"])
        _ = try store.migrateLegacyProfiles(
            secretStore: secrets,
            credentialReferenceGenerator: { "new.\($0)" }
        )

        let rollback = try store.rollbackLegacyMigration(
            expectedCanonicalRevision: 1,
            secretStore: secrets
        )

        XCTAssertEqual(
            rollback,
            ProviderProfileStorageRollbackResult(
                credentialsRemoved: 0,
                credentialCleanupFailures: 1
            )
        )
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertEqual(try secrets.secret(named: "new.profile-a"), "secret-value")
    }

    func testLegacyMigrationRollbackRejectsChangedCanonicalRevision() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-migration-stale-rollback-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let legacyURL = try XCTUnwrap(store.legacyFileURL)
        try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [])
        ).write(to: legacyURL, options: [.atomic])
        _ = try store.migrateLegacyProfiles(secretStore: InMemorySecretStore())
        _ = try store.transactProfiles(expectedRevision: 1) { $0 }

        XCTAssertThrowsError(
            try store.rollbackLegacyMigration(
                expectedCanonicalRevision: 1,
                secretStore: InMemorySecretStore()
            )
        ) { error in
            XCTAssertEqual(
                error as? ProviderProfileStoreError,
                .revisionConflict(expected: 1, actual: 2)
            )
        }
        XCTAssertEqual(try store.loadProfiles().revision, 2)
        XCTAssertEqual(store.legacyStorageState(), .tombstone)
    }

    func testLegacyNumericV2WithoutRevisionStillMigrates() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-migrate-v2-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let legacyURL = try XCTUnwrap(store.legacyFileURL)
        try Data(#"{"schemaVersion":2,"profiles":[]}"#.utf8)
            .write(to: legacyURL, options: [.atomic])

        let result = try store.migrateLegacyProfiles(secretStore: InMemorySecretStore())

        XCTAssertEqual(result.status, .migrated)
        XCTAssertEqual(result.revision, 1)
        XCTAssertEqual(try store.loadProfiles().revision, 1)
    }

    func testLegacyWriterAfterCutoverCannotChangeCanonicalProfilesOrCredential() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-old-writer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let legacyURL = try XCTUnwrap(store.legacyFileURL)
        let original = ProviderProfile(
            id: "profile-a",
            displayName: "Canonical",
            kind: .openAIChat,
            baseURL: URL(string: "https://example.com/v1")!,
            model: "model-a",
            secretName: "legacy.secret",
            isDefault: true
        )
        try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [original])
        ).write(to: legacyURL, options: [.atomic])
        let secrets = InMemorySecretStore(values: ["legacy.secret": "secret-value"])
        _ = try store.migrateLegacyProfiles(
            secretStore: secrets,
            credentialReferenceGenerator: { "new.\($0)" }
        )
        let canonical = try store.loadProfiles()

        var overwritten = original
        overwritten.displayName = "Stale writer"
        overwritten.model = "model-stale"
        let staleWriterData = try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [overwritten])
        )
        try staleWriterData.write(to: legacyURL, options: [.atomic])
        try secrets.deleteSecret(named: "legacy.secret")

        XCTAssertEqual(try store.loadProfiles(), canonical)
        XCTAssertEqual(try secrets.secret(named: "new.profile-a"), "secret-value")
        XCTAssertThrowsError(
            try store.transactProfiles(expectedRevision: canonical.revision) { $0 }
        ) { error in
            XCTAssertEqual(
                error as? ProviderProfileStoreError,
                .legacyWriterDetected(path: legacyURL.path)
            )
        }

        XCTAssertThrowsError(try store.migrateLegacyProfiles(secretStore: secrets)) { error in
            XCTAssertEqual(
                error as? ProviderProfileStoreError,
                .legacyWriterDetected(path: legacyURL.path)
            )
        }
        XCTAssertEqual(try store.loadProfiles(), canonical)
        XCTAssertEqual(try Data(contentsOf: legacyURL), staleWriterData)
        XCTAssertEqual(store.legacyStorageState(), .configuration)
        XCTAssertEqual(try secrets.secret(named: "new.profile-a"), "secret-value")
    }

    func testCanonicalProfilesDowngradePreservesCurrentProfilesForLegacyRuntime() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-downgrade-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let legacyURL = try XCTUnwrap(store.legacyFileURL)
        let original = ProviderProfile(
            id: "profile-a",
            displayName: "Original",
            kind: .openAIChat,
            baseURL: URL(string: "https://example.com/v1")!,
            model: "model-a",
            secretName: "legacy.secret",
            isDefault: true
        )
        try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [original])
        ).write(to: legacyURL, options: [.atomic])
        let secrets = InMemorySecretStore(values: ["legacy.secret": "secret-value"])
        _ = try store.migrateLegacyProfiles(
            secretStore: secrets,
            credentialReferenceGenerator: { "new.\($0)" }
        )
        _ = try store.transactProfiles(expectedRevision: 1) { current in
            var updated = current
            updated.profiles[0].displayName = "Current"
            return updated
        }

        let result = try store.downgradeCanonicalProfilesForLegacyRuntime()

        XCTAssertEqual(
            result,
            ProviderProfileStorageDowngradeResult(
                status: .downgraded,
                revision: 2,
                profileCount: 1
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        let legacyData = try Data(contentsOf: legacyURL)
        let legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: legacyData) as? [String: Any]
        )
        XCTAssertEqual(legacyObject["schemaVersion"] as? Int, 1)
        XCTAssertNil(legacyObject["revision"])
        let decoded = try JSONDecoder().decode(PreV2ProviderProfilesFile.self, from: legacyData)
        XCTAssertEqual(decoded.profiles.first?.displayName, "Current")
        XCTAssertEqual(decoded.profiles.first?.secretName, "new.profile-a")
        XCTAssertEqual(try secrets.secret(named: "new.profile-a"), "secret-value")
    }

    func testCanonicalProfilesDowngradeRejectsLateLegacyWriter() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-downgrade-late-writer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let legacyURL = try XCTUnwrap(store.legacyFileURL)
        let staleWriterData = try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [])
        )
        try staleWriterData.write(to: legacyURL, options: [.atomic])
        _ = try store.migrateLegacyProfiles(secretStore: InMemorySecretStore())
        try staleWriterData.write(to: legacyURL, options: [.atomic])

        XCTAssertThrowsError(try store.downgradeCanonicalProfilesForLegacyRuntime()) { error in
            XCTAssertEqual(
                error as? ProviderProfileStoreError,
                .legacyWriterDetected(path: legacyURL.path)
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertEqual(try Data(contentsOf: legacyURL), staleWriterData)
    }

    func testCanonicalProfilesDowngradePreservesWriterArrivingDuringCutover() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-downgrade-cutover-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let initialStore = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let legacyURL = try XCTUnwrap(initialStore.legacyFileURL)
        let snapshotURL = try XCTUnwrap(initialStore.legacySnapshotURL)
        try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [])
        ).write(to: legacyURL, options: [.atomic])
        _ = try initialStore.migrateLegacyProfiles(secretStore: InMemorySecretStore())
        let lateWriterProfile = ProviderProfile(
            id: "late",
            displayName: "Late writer",
            kind: .openAIChat,
            baseURL: URL(string: "https://late.example.com/v1")!,
            model: "late-model",
            isDefault: true
        )
        let lateWriterData = try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [lateWriterProfile])
        )
        let store = FileProviderProfileStore(
            fileURL: initialStore.fileURL,
            legacyFileURL: legacyURL,
            legacySnapshotURL: snapshotURL,
            migrationCutoverHook: {
                try lateWriterData.write(to: legacyURL, options: [.atomic])
            }
        )

        XCTAssertThrowsError(try store.downgradeCanonicalProfilesForLegacyRuntime()) { error in
            XCTAssertEqual(
                error as? ProviderProfileStoreError,
                .legacyChangedDuringMigration(path: legacyURL.path)
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertEqual(try Data(contentsOf: legacyURL), lateWriterData)
    }

    func testTransactionDoesNotOverwriteWriterPayloadArrivingBeforeTombstoneCheck() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-transaction-writer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let initialStore = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let legacyURL = try XCTUnwrap(initialStore.legacyFileURL)
        let snapshotURL = try XCTUnwrap(initialStore.legacySnapshotURL)
        let original = ProviderProfile(
            id: "canonical",
            displayName: "Canonical",
            kind: .openAIChat,
            baseURL: URL(string: "https://example.com/v1")!,
            model: "model",
            isDefault: true
        )
        try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [original])
        ).write(to: legacyURL, options: [.atomic])
        _ = try initialStore.migrateLegacyProfiles(secretStore: InMemorySecretStore())
        let canonicalBefore = try initialStore.loadProfiles()
        let lateWriterData = try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [])
        )
        let store = FileProviderProfileStore(
            fileURL: initialStore.fileURL,
            legacyFileURL: legacyURL,
            legacySnapshotURL: snapshotURL,
            migrationCutoverHook: {
                try lateWriterData.write(to: legacyURL, options: [.atomic])
            }
        )

        XCTAssertThrowsError(
            try store.transactProfiles(expectedRevision: canonicalBefore.revision) { current in
                var updated = current
                updated.profiles[0].displayName = "Should roll back"
                return updated
            }
        ) { error in
            XCTAssertEqual(
                error as? ProviderProfileStoreError,
                .legacyWriterDetected(path: legacyURL.path)
            )
        }
        XCTAssertEqual(try initialStore.loadProfiles(), canonicalBefore)
        XCTAssertEqual(try Data(contentsOf: legacyURL), lateWriterData)
    }

    func testMigrationClearsMissingCredentialReference() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-missing-secret-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let legacyURL = try XCTUnwrap(store.legacyFileURL)
        let profile = ProviderProfile(
            id: "missing",
            displayName: "Missing",
            kind: .openAIChat,
            baseURL: URL(string: "https://example.com/v1")!,
            model: "model",
            secretName: "missing.secret",
            isDefault: true
        )
        try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [profile])
        ).write(to: legacyURL, options: [.atomic])

        let result = try store.migrateLegacyProfiles(secretStore: InMemorySecretStore())

        XCTAssertEqual(result.missingCredentials, 1)
        XCTAssertEqual(result.credentialsRekeyed, 0)
        XCTAssertNil(try store.loadProfiles().profiles.first?.secretName)
    }

    func testMigrationCompensatesCreatedCredentialsWhenReferenceGenerationFails() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-secret-compensation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let legacyURL = try XCTUnwrap(store.legacyFileURL)
        let profiles = ["a", "b"].map { id in
            ProviderProfile(
                id: id,
                displayName: id,
                kind: .openAIChat,
                baseURL: URL(string: "https://example.com/v1")!,
                model: "model",
                secretName: "legacy.\(id)",
                isDefault: id == "a"
            )
        }
        let legacyData = try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: profiles)
        )
        try legacyData.write(to: legacyURL, options: [.atomic])
        let secrets = InMemorySecretStore(values: [
            "legacy.a": "secret-a",
            "legacy.b": "secret-b"
        ])

        XCTAssertThrowsError(
            try store.migrateLegacyProfiles(
                secretStore: secrets,
                credentialReferenceGenerator: { _ in "new.duplicate" }
            )
        ) { error in
            XCTAssertEqual(
                error as? ProviderProfileStoreError,
                .invalidMigrationCredentialReference
            )
        }
        XCTAssertNil(try secrets.secret(named: "new.duplicate"))
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testMigrationRejectsOccupiedCredentialDestinationWithoutChangingIt() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-secret-collision-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let legacyURL = try XCTUnwrap(store.legacyFileURL)
        let profile = ProviderProfile(
            id: "a",
            displayName: "A",
            kind: .openAIChat,
            baseURL: URL(string: "https://example.com/v1")!,
            model: "model",
            secretName: "legacy.a",
            isDefault: true
        )
        try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [profile])
        ).write(to: legacyURL, options: [.atomic])
        let secrets = InMemorySecretStore(values: [
            "legacy.a": "legacy-value",
            "new.a": "existing-value"
        ])

        XCTAssertThrowsError(
            try store.migrateLegacyProfiles(
                secretStore: secrets,
                credentialReferenceGenerator: { "new.\($0)" }
            )
        ) { error in
            XCTAssertEqual(error as? ProviderProfileStoreError, .invalidMigrationCredentialReference)
        }
        XCTAssertEqual(try secrets.secret(named: "new.a"), "existing-value")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testFailedMigrationRefreshesLegacySnapshotBeforeSuccessfulRetry() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-snapshot-retry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let legacyURL = try XCTUnwrap(store.legacyFileURL)
        let snapshotURL = try XCTUnwrap(store.legacySnapshotURL)
        let firstProfiles = ["a", "b"].map { id in
            ProviderProfile(
                id: id,
                displayName: id,
                kind: .openAIChat,
                baseURL: URL(string: "https://example.com/v1")!,
                model: "model",
                secretName: "legacy.\(id)",
                isDefault: id == "a"
            )
        }
        try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: firstProfiles)
        ).write(to: legacyURL, options: [.atomic])
        let secrets = InMemorySecretStore(values: [
            "legacy.a": "secret-a",
            "legacy.b": "secret-b",
            "legacy.c": "secret-c"
        ])
        XCTAssertThrowsError(
            try store.migrateLegacyProfiles(
                secretStore: secrets,
                credentialReferenceGenerator: { _ in "duplicate" }
            )
        )

        let replacement = ProviderProfile(
            id: "c",
            displayName: "Replacement",
            kind: .openAIResponses,
            baseURL: URL(string: "https://replacement.example.com/v1")!,
            model: "replacement",
            secretName: "legacy.c",
            isDefault: true
        )
        let replacementData = try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [replacement])
        )
        try replacementData.write(to: legacyURL, options: [.atomic])

        _ = try store.migrateLegacyProfiles(
            secretStore: secrets,
            credentialReferenceGenerator: { "new.\($0)" }
        )

        XCTAssertEqual(try Data(contentsOf: snapshotURL), replacementData)
        XCTAssertEqual(try store.loadProfiles().profiles.first?.id, "c")
    }

    func testMigrationRollbackFailureRetainsNewCredential() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-rollback-failure-\(UUID().uuidString)", isDirectory: true)
        let canonicalDirectory = root.appendingPathComponent("canonical", isDirectory: true)
        let legacyDirectory = root.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: canonicalDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: canonicalDirectory.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: legacyDirectory.path)
            try? FileManager.default.removeItem(at: root)
        }
        let legacyURL = legacyDirectory.appendingPathComponent("providers.json")
        let profile = ProviderProfile(
            id: "a",
            displayName: "A",
            kind: .openAIChat,
            baseURL: URL(string: "https://example.com/v1")!,
            model: "model",
            secretName: "legacy.a",
            isDefault: true
        )
        try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [profile])
        ).write(to: legacyURL, options: [.atomic])
        let store = FileProviderProfileStore(
            fileURL: canonicalDirectory.appendingPathComponent("providers.v2.json"),
            legacyFileURL: legacyURL,
            legacySnapshotURL: canonicalDirectory.appendingPathComponent("providers.legacy.json"),
            migrationCutoverHook: {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o400],
                    ofItemAtPath: legacyURL.path
                )
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o500],
                    ofItemAtPath: canonicalDirectory.path
                )
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o500],
                    ofItemAtPath: legacyDirectory.path
                )
            }
        )
        let secrets = InMemorySecretStore(values: ["legacy.a": "secret-value"])

        XCTAssertThrowsError(
            try store.migrateLegacyProfiles(
                secretStore: secrets,
                credentialReferenceGenerator: { "new.\($0)" }
            )
        ) { error in
            XCTAssertEqual(error as? ProviderProfileStoreError, .migrationRollbackFailed)
        }
        XCTAssertEqual(try secrets.secret(named: "new.a"), "secret-value")
    }

    func testMissingCanonicalAfterCompletedMigrationFailsClosed() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-missing-canonical-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let legacyURL = try XCTUnwrap(store.legacyFileURL)
        try JSONEncoder().encode(
            PreV2ProviderProfilesFile(schemaVersion: 1, profiles: [])
        ).write(to: legacyURL, options: [.atomic])
        _ = try store.migrateLegacyProfiles(secretStore: InMemorySecretStore())
        try FileManager.default.removeItem(at: store.fileURL)

        XCTAssertThrowsError(try store.loadProfiles()) { error in
            XCTAssertEqual(
                error as? ProviderProfileStoreError,
                .canonicalFileMissing(path: store.fileURL.path)
            )
        }
    }

    func testMissingCanonicalAfterFreshStoreSaveFailsClosed() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-profile-fresh-missing-canonical-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let store = try FileProviderProfileStore.defaultStore(
            applicationSupportDirectory: applicationSupport
        )
        let initial = try store.migrateLegacyProfiles(secretStore: InMemorySecretStore())
        XCTAssertEqual(initial.status, .noLegacyConfiguration)
        _ = try store.transactProfiles(expectedRevision: 0) { $0 }
        try FileManager.default.removeItem(at: store.fileURL)

        XCTAssertThrowsError(try store.loadProfiles()) { error in
            XCTAssertEqual(
                error as? ProviderProfileStoreError,
                .canonicalFileMissing(path: store.fileURL.path)
            )
        }
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
