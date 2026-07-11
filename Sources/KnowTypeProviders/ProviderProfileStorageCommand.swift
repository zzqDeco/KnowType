import Foundation

public enum ProviderProfileStorageCommand {
    public static func migrate() -> Int32 {
        do {
            let result = try profileStore().migrateLegacyProfiles(
                secretStore: KeychainSecretStore()
            )
            print("provider.migration.status=\(result.status.rawValue)")
            print("provider.migration.revision=\(result.revision)")
            print("provider.migration.profiles=\(result.profileCount)")
            print("provider.migration.credentials.rekeyed=\(result.credentialsRekeyed)")
            print("provider.migration.credentials.missing=\(result.missingCredentials)")
            return 0
        } catch let error as ProviderProfileStoreError {
            fputs("provider.migration.error=\(errorCode(error))\n", stderr)
            return 1
        } catch {
            fputs("provider.migration.error=unexpected\n", stderr)
            return 1
        }
    }

    public static func rollback(expectedCanonicalRevision: UInt64) -> Int32 {
        do {
            let result = try profileStore().rollbackLegacyMigration(
                expectedCanonicalRevision: expectedCanonicalRevision,
                secretStore: KeychainSecretStore()
            )
            print("provider.migration.rollback=ok")
            print("provider.migration.rollback.credentials.removed=\(result.credentialsRemoved)")
            print("provider.migration.rollback.credentials.cleanupFailures=\(result.credentialCleanupFailures)")
            return 0
        } catch let error as ProviderProfileStoreError {
            fputs("provider.migration.rollback.error=\(errorCode(error))\n", stderr)
            return 1
        } catch {
            fputs("provider.migration.rollback.error=unexpected\n", stderr)
            return 1
        }
    }

    public static func downgradeForLegacyRuntime() -> Int32 {
        do {
            let result = try profileStore().downgradeCanonicalProfilesForLegacyRuntime()
            print("provider.storage.downgrade.status=\(result.status.rawValue)")
            print("provider.storage.downgrade.revision=\(result.revision)")
            print("provider.storage.downgrade.profiles=\(result.profileCount)")
            return 0
        } catch let error as ProviderProfileStoreError {
            fputs("provider.storage.downgrade.error=\(errorCode(error))\n", stderr)
            return 1
        } catch {
            fputs("provider.storage.downgrade.error=unexpected\n", stderr)
            return 1
        }
    }

    private static func profileStore() throws -> FileProviderProfileStore {
        if let override = ProcessInfo.processInfo.environment["KNOWTYPE_APP_SUPPORT_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            let directory = URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return FileProviderProfileStore(
                fileURL: directory.appendingPathComponent(FileProviderProfileStore.canonicalFilename),
                legacyFileURL: directory.appendingPathComponent(FileProviderProfileStore.legacyFilename),
                legacySnapshotURL: directory.appendingPathComponent(FileProviderProfileStore.legacySnapshotFilename)
            )
        }
        return try FileProviderProfileStore.defaultStore()
    }

    private static func errorCode(_ error: ProviderProfileStoreError) -> String {
        switch error {
        case .unsupportedSchemaVersion:
            return "unsupported-schema"
        case .revisionConflict:
            return "revision-conflict"
        case .revisionOverflow:
            return "revision-overflow"
        case .lockFailed:
            return "lock-failed"
        case .migrationRequired:
            return "migration-required"
        case .canonicalFileMissing:
            return "canonical-missing"
        case .legacyWriterDetected:
            return "legacy-writer-detected"
        case .legacyChangedDuringMigration:
            return "legacy-changed"
        case .invalidMigrationCredentialReference:
            return "invalid-credential-reference"
        case .filePermissionUpdateFailed:
            return "permission-update-failed"
        case .migrationRollbackFailed:
            return "migration-rollback-failed"
        case .metadataRollbackFailed:
            return "metadata-rollback-failed"
        }
    }
}
