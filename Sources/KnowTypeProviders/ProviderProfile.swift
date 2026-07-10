import Foundation
import KnowTypeCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct ProviderProfile: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var kind: ProviderKind
    public var baseURL: URL
    public var model: String
    public var timeoutSeconds: TimeInterval
    public var headers: [String: String]
    public var secretName: String?
    public var customBodyTemplate: String?
    public var customResponsePath: String?
    public var isDefault: Bool

    public init(
        id: String = UUID().uuidString,
        displayName: String,
        kind: ProviderKind,
        baseURL: URL,
        model: String,
        timeoutSeconds: TimeInterval = 20,
        headers: [String: String] = [:],
        secretName: String? = nil,
        customBodyTemplate: String? = nil,
        customResponsePath: String? = nil,
        isDefault: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
        self.timeoutSeconds = timeoutSeconds
        self.headers = headers
        self.secretName = secretName
        self.customBodyTemplate = customBodyTemplate
        self.customResponsePath = customResponsePath
        self.isDefault = isDefault
    }
}

public struct ProviderProfilesFile: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var revision: UInt64
    public var profiles: [ProviderProfile]

    public init(
        schemaVersion: Int = ProviderProfilesFile.currentSchemaVersion,
        revision: UInt64 = 0,
        profiles: [ProviderProfile] = []
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.profiles = profiles
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case revision
        case profiles
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard (1...Self.currentSchemaVersion).contains(schemaVersion) else {
            throw ProviderProfileStoreError.unsupportedSchemaVersion(schemaVersion)
        }

        self.schemaVersion = schemaVersion
        if schemaVersion == 1 {
            self.revision = try container.decodeIfPresent(UInt64.self, forKey: .revision) ?? 0
        } else {
            self.revision = try container.decode(UInt64.self, forKey: .revision)
        }
        self.profiles = try container.decode([ProviderProfile].self, forKey: .profiles)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(revision, forKey: .revision)
        try container.encode(profiles, forKey: .profiles)
    }
}

public protocol ProviderProfileStore: Sendable {
    func loadProfiles() throws -> ProviderProfilesFile
    func saveProfiles(_ profiles: ProviderProfilesFile) throws
    func transactProfiles(
        expectedRevision: UInt64,
        _ mutation: (ProviderProfilesFile) throws -> ProviderProfilesFile
    ) throws -> ProviderProfilesFile
}

public extension ProviderProfileStore {
    func transactProfiles(
        expectedRevision: UInt64,
        _ mutation: (ProviderProfilesFile) throws -> ProviderProfilesFile
    ) throws -> ProviderProfilesFile {
        let current = try loadProfiles()
        guard current.revision == expectedRevision else {
            throw ProviderProfileStoreError.revisionConflict(
                expected: expectedRevision,
                actual: current.revision
            )
        }
        guard current.revision < UInt64.max else {
            throw ProviderProfileStoreError.revisionOverflow
        }

        var updated = try mutation(current)
        updated.schemaVersion = ProviderProfilesFile.currentSchemaVersion
        updated.revision = current.revision + 1
        try saveProfiles(updated)
        return updated
    }
}

public enum ProviderProfileStoreError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case revisionConflict(expected: UInt64, actual: UInt64)
    case revisionOverflow
    case lockFailed(path: String, code: Int32)
    case migrationRequired(path: String)
    case canonicalFileMissing(path: String)
    case legacyWriterDetected(path: String)
    case legacyChangedDuringMigration(path: String)
    case invalidMigrationCredentialReference
    case filePermissionUpdateFailed(path: String, code: Int32)
    case migrationRollbackFailed
    case metadataRollbackFailed

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported provider profile schema version: \(version)"
        case .revisionConflict(let expected, let actual):
            return "Provider profile revision conflict (expected \(expected), found \(actual))"
        case .revisionOverflow:
            return "Provider profile revision cannot be incremented"
        case .lockFailed(let path, let code):
            return "Could not lock provider profiles at \(path) (errno \(code))"
        case .migrationRequired(let path):
            return "Legacy provider profiles require migration before they can be changed: \(path)"
        case .canonicalFileMissing(let path):
            return "Canonical provider profiles are missing after migration: \(path)"
        case .legacyWriterDetected(let path):
            return "A legacy settings process changed provider profiles after migration: \(path)"
        case .legacyChangedDuringMigration(let path):
            return "Legacy provider profiles changed during migration: \(path)"
        case .invalidMigrationCredentialReference:
            return "Provider profile migration generated an invalid credential reference"
        case .filePermissionUpdateFailed(let path, let code):
            return "Could not restrict provider profile file permissions at \(path) (errno \(code))"
        case .migrationRollbackFailed:
            return "Provider profile migration failed and metadata rollback could not be completed"
        case .metadataRollbackFailed:
            return "Provider profile metadata update failed and the previous canonical file could not be restored"
        }
    }
}

public enum LegacyProviderProfileStorageState: String, Sendable, Equatable {
    case unmanaged
    case absent
    case configuration
    case tombstone
}

public enum ProviderProfileStorageMigrationStatus: String, Sendable, Equatable {
    case unmanaged
    case noLegacyConfiguration = "no_legacy_configuration"
    case migrated
    case alreadyCurrent = "already_current"
}

public struct ProviderProfileStorageMigrationResult: Sendable, Equatable {
    public var status: ProviderProfileStorageMigrationStatus
    public var revision: UInt64
    public var profileCount: Int
    public var credentialsRekeyed: Int
    public var missingCredentials: Int

    public init(
        status: ProviderProfileStorageMigrationStatus,
        revision: UInt64,
        profileCount: Int,
        credentialsRekeyed: Int = 0,
        missingCredentials: Int = 0
    ) {
        self.status = status
        self.revision = revision
        self.profileCount = profileCount
        self.credentialsRekeyed = credentialsRekeyed
        self.missingCredentials = missingCredentials
    }
}

public struct ProviderProfileStorageRollbackResult: Sendable, Equatable {
    public var credentialsRemoved: Int
    public var credentialCleanupFailures: Int

    public init(credentialsRemoved: Int, credentialCleanupFailures: Int) {
        self.credentialsRemoved = credentialsRemoved
        self.credentialCleanupFailures = credentialCleanupFailures
    }
}

public enum ProviderProfileStorageDowngradeStatus: String, Sendable, Equatable {
    case alreadyLegacy = "already_legacy"
    case downgraded
    case unmanaged
}

public struct ProviderProfileStorageDowngradeResult: Sendable, Equatable {
    public var status: ProviderProfileStorageDowngradeStatus
    public var revision: UInt64
    public var profileCount: Int

    public init(
        status: ProviderProfileStorageDowngradeStatus,
        revision: UInt64,
        profileCount: Int
    ) {
        self.status = status
        self.revision = revision
        self.profileCount = profileCount
    }
}

private struct LegacyProviderProfilesEnvelope: Decodable {
    var schemaVersion: Int
    var revision: UInt64
    var profiles: [ProviderProfile]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case revision
        case profiles
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        revision = try container.decodeIfPresent(UInt64.self, forKey: .revision) ?? 0
        profiles = try container.decode([ProviderProfile].self, forKey: .profiles)
    }
}

private struct LegacyProviderProfilesPayload: Encodable {
    let schemaVersion = 1
    var profiles: [ProviderProfile]
}

private enum LegacyFilePreparation {
    case unmanaged
    case unchanged
    case created(publishedData: Data)
    case replaced(claimURL: URL, publishedData: Data)
}

public protocol ProviderProfileRevisionSignaling: Sendable {
    func postProviderProfilesChanged(revision: UInt64)
}

public struct DistributedProviderProfileRevisionSignal: ProviderProfileRevisionSignaling {
    public static let notificationName = Notification.Name(
        "com.knowtype.provider-profiles.revision-changed"
    )

    public init() {}

    public func postProviderProfilesChanged(revision: UInt64) {
        #if os(macOS)
        DistributedNotificationCenter.default().postNotificationName(
            Self.notificationName,
            object: nil,
            userInfo: ["revision": NSNumber(value: revision)],
            deliverImmediately: true
        )
        #endif
    }
}

public struct FileProviderProfileStore: ProviderProfileStore {
    public static let canonicalFilename = "providers.v2.json"
    public static let legacyFilename = "providers.json"
    public static let legacySnapshotFilename = "providers.legacy.json"
    public static let legacyConflictFilenamePrefix = "providers.legacy-conflict."
    public static let legacyTombstoneSchemaVersion = "migrated-to-providers.v2.json"

    public let fileURL: URL
    public let lockFileURL: URL
    public let legacyFileURL: URL?
    public let legacySnapshotURL: URL?
    private let revisionSignal: any ProviderProfileRevisionSignaling
    private let migrationCutoverHook: (@Sendable () throws -> Void)?

    public init(
        fileURL: URL,
        legacyFileURL: URL? = nil,
        legacySnapshotURL: URL? = nil,
        revisionSignal: any ProviderProfileRevisionSignaling = DistributedProviderProfileRevisionSignal()
    ) {
        self.fileURL = fileURL
        self.lockFileURL = fileURL.appendingPathExtension("lock")
        self.legacyFileURL = legacyFileURL
        self.legacySnapshotURL = legacySnapshotURL
        self.revisionSignal = revisionSignal
        self.migrationCutoverHook = nil
    }

    init(
        fileURL: URL,
        legacyFileURL: URL?,
        legacySnapshotURL: URL?,
        revisionSignal: any ProviderProfileRevisionSignaling = DistributedProviderProfileRevisionSignal(),
        migrationCutoverHook: @escaping @Sendable () throws -> Void
    ) {
        self.fileURL = fileURL
        self.lockFileURL = fileURL.appendingPathExtension("lock")
        self.legacyFileURL = legacyFileURL
        self.legacySnapshotURL = legacySnapshotURL
        self.revisionSignal = revisionSignal
        self.migrationCutoverHook = migrationCutoverHook
    }

    public static func defaultStore(createDirectory: Bool = true) throws -> FileProviderProfileStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createDirectory
        )
        return try defaultStore(applicationSupportDirectory: base, createDirectory: createDirectory)
    }

    public static func defaultStore(
        applicationSupportDirectory base: URL,
        createDirectory: Bool = true
    ) throws -> FileProviderProfileStore {
        let directory = base.appendingPathComponent("KnowType", isDirectory: true)
        if createDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return FileProviderProfileStore(
            fileURL: directory.appendingPathComponent(Self.canonicalFilename),
            legacyFileURL: directory.appendingPathComponent(Self.legacyFilename),
            legacySnapshotURL: directory.appendingPathComponent(Self.legacySnapshotFilename)
        )
    }

    public func loadProfiles() throws -> ProviderProfilesFile {
        let directory = lockFileURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return ProviderProfilesFile()
        }
        return try withFileLock(operation: LOCK_SH, createDirectory: false) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                try requireCanonicalStorageReadyForReadWithoutLock()
                return ProviderProfilesFile()
            }
            return try loadProfilesWithoutLock()
        }
    }

    public func saveProfiles(_ profiles: ProviderProfilesFile) throws {
        _ = try transactProfiles(expectedRevision: profiles.revision) { _ in profiles }
    }

    public func legacyStorageState() -> LegacyProviderProfileStorageState {
        legacyStorageStateWithoutLock()
    }

    public func migrateLegacyProfiles(
        secretStore: any SecretStore,
        credentialReferenceGenerator: (String) -> String = { profileID in
            "knowtype.provider.\(profileID).credential.\(UUID().uuidString)"
        }
    ) throws -> ProviderProfileStorageMigrationResult {
        var committedRevision: UInt64?
        let result = try withFileLock(operation: LOCK_EX, createDirectory: true) {
            guard let legacyFileURL else {
                return ProviderProfileStorageMigrationResult(
                    status: .unmanaged,
                    revision: 0,
                    profileCount: 0
                )
            }
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let current = try loadProfilesWithoutLock()
                let preparation = try prepareLegacyTombstoneForCanonicalWithoutLock(
                    conflictError: .legacyWriterDetected(path: legacyFileURL.path)
                )
                try finishLegacyFilePreparation(preparation)
                return ProviderProfileStorageMigrationResult(
                    status: .alreadyCurrent,
                    revision: current.revision,
                    profileCount: current.profiles.count
                )
            }

            let legacyData: Data
            switch legacyStorageStateWithoutLock() {
            case .unmanaged:
                return ProviderProfileStorageMigrationResult(
                    status: .unmanaged,
                    revision: 0,
                    profileCount: 0
                )
            case .absent:
                if let recoveredData = try recoverInterruptedLegacyMigrationWithoutLock() {
                    legacyData = recoveredData
                } else if interruptedLegacyMigrationEvidenceExistsWithoutLock() {
                    throw ProviderProfileStoreError.migrationRollbackFailed
                } else {
                    return ProviderProfileStorageMigrationResult(
                        status: .noLegacyConfiguration,
                        revision: 0,
                        profileCount: 0
                    )
                }
            case .tombstone:
                if legacyTombstoneExpectsCanonicalWithoutLock() {
                    throw ProviderProfileStoreError.canonicalFileMissing(path: fileURL.path)
                }
                guard let recoveredData = try recoverInterruptedLegacyMigrationWithoutLock() else {
                    throw ProviderProfileStoreError.migrationRollbackFailed
                }
                legacyData = recoveredData
            case .configuration:
                legacyData = try Data(contentsOf: legacyFileURL)
            }

            let legacy = try JSONDecoder().decode(LegacyProviderProfilesEnvelope.self, from: legacyData)
            guard (1...ProviderProfilesFile.currentSchemaVersion).contains(legacy.schemaVersion) else {
                throw ProviderProfileStoreError.unsupportedSchemaVersion(legacy.schemaVersion)
            }
            guard legacy.revision < UInt64.max else {
                throw ProviderProfileStoreError.revisionOverflow
            }
            try writeLegacySnapshot(legacyData)

            var migratedProfiles = legacy.profiles
            var createdCredentialReferences: [String] = []
            var createdCredentialReferenceSet = Set<String>()
            let legacyCredentialReferenceSet = Set(legacy.profiles.compactMap(\.secretName))
            var missingCredentials = 0
            var canCompensateCredentials = true

            do {
                for index in migratedProfiles.indices {
                    guard let legacyReference = migratedProfiles[index].secretName else {
                        continue
                    }
                    guard let secret = try secretStore.secret(named: legacyReference), !secret.isEmpty else {
                        migratedProfiles[index].secretName = nil
                        missingCredentials += 1
                        continue
                    }

                    let newReference = credentialReferenceGenerator(migratedProfiles[index].id)
                    guard !newReference.isEmpty,
                          !legacyCredentialReferenceSet.contains(newReference),
                          createdCredentialReferenceSet.insert(newReference).inserted else {
                        throw ProviderProfileStoreError.invalidMigrationCredentialReference
                    }
                    guard try secretStore.secret(named: newReference) == nil else {
                        throw ProviderProfileStoreError.invalidMigrationCredentialReference
                    }
                    try secretStore.setSecret(secret, named: newReference)
                    createdCredentialReferences.append(newReference)
                    migratedProfiles[index].secretName = newReference
                }

                let migrated = ProviderProfilesFile(
                    schemaVersion: ProviderProfilesFile.currentSchemaVersion,
                    revision: legacy.revision + 1,
                    profiles: migratedProfiles
                )
                let provisionalTombstoneData = Self.legacyTombstoneData(canonicalExpected: false)
                var provisionalTombstonePreparation: LegacyFilePreparation?
                var finalTombstonePreparation: LegacyFilePreparation?
                do {
                    provisionalTombstonePreparation = try replaceLegacyPayloadWithTombstoneWithoutLock(
                        expectedData: legacyData,
                        canonicalExpected: false,
                        conflictError: .legacyChangedDuringMigration(path: legacyFileURL.path)
                    )
                    try migrationCutoverHook?()
                    try writeProfilesWithoutLock(migrated)
                    finalTombstonePreparation = try replaceLegacyPayloadWithTombstoneWithoutLock(
                        expectedData: provisionalTombstoneData,
                        canonicalExpected: true,
                        conflictError: .legacyChangedDuringMigration(path: legacyFileURL.path)
                    )
                    guard legacyStorageStateWithoutLock() == .tombstone,
                          legacyTombstoneExpectsCanonicalWithoutLock() else {
                        throw ProviderProfileStoreError.legacyChangedDuringMigration(path: legacyFileURL.path)
                    }
                    if let finalTombstonePreparation {
                        try finishLegacyFilePreparation(finalTombstonePreparation)
                    }
                    if let provisionalTombstonePreparation {
                        try finishLegacyFilePreparation(provisionalTombstonePreparation)
                    }
                } catch {
                    do {
                        if FileManager.default.fileExists(atPath: fileURL.path) {
                            try FileManager.default.removeItem(at: fileURL)
                        }
                        if let finalTombstonePreparation {
                            try rollbackLegacyFilePreparationWithoutLock(finalTombstonePreparation)
                        }
                        if let provisionalTombstonePreparation {
                            try rollbackLegacyFilePreparationWithoutLock(provisionalTombstonePreparation)
                        }
                    } catch {
                        canCompensateCredentials = false
                        throw ProviderProfileStoreError.migrationRollbackFailed
                    }
                    throw error
                }

                committedRevision = migrated.revision
                return ProviderProfileStorageMigrationResult(
                    status: .migrated,
                    revision: migrated.revision,
                    profileCount: migrated.profiles.count,
                    credentialsRekeyed: createdCredentialReferences.count,
                    missingCredentials: missingCredentials
                )
            } catch {
                if canCompensateCredentials {
                    for reference in createdCredentialReferences {
                        try? secretStore.deleteSecret(named: reference)
                    }
                }
                throw error
            }
        }
        if let committedRevision {
            revisionSignal.postProviderProfilesChanged(revision: committedRevision)
        }
        return result
    }

    public func downgradeCanonicalProfilesForLegacyRuntime() throws -> ProviderProfileStorageDowngradeResult {
        try withFileLock(operation: LOCK_EX, createDirectory: true) {
            guard let legacyFileURL else {
                return ProviderProfileStorageDowngradeResult(
                    status: .unmanaged,
                    revision: 0,
                    profileCount: 0
                )
            }

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                switch legacyStorageStateWithoutLock() {
                case .configuration:
                    let data = try Data(contentsOf: legacyFileURL)
                    let legacy = try JSONDecoder().decode(LegacyProviderProfilesEnvelope.self, from: data)
                    return ProviderProfileStorageDowngradeResult(
                        status: .alreadyLegacy,
                        revision: legacy.revision,
                        profileCount: legacy.profiles.count
                    )
                case .absent:
                    if interruptedLegacyMigrationEvidenceExistsWithoutLock() {
                        let legacy = try recoverInterruptedLegacyProfilesForDowngradeWithoutLock()
                        return ProviderProfileStorageDowngradeResult(
                            status: .alreadyLegacy,
                            revision: legacy.revision,
                            profileCount: legacy.profiles.count
                        )
                    }
                    return ProviderProfileStorageDowngradeResult(
                        status: .alreadyLegacy,
                        revision: 0,
                        profileCount: 0
                    )
                case .unmanaged:
                    return ProviderProfileStorageDowngradeResult(
                        status: .alreadyLegacy,
                        revision: 0,
                        profileCount: 0
                    )
                case .tombstone:
                    if legacyTombstoneExpectsCanonicalWithoutLock() {
                        throw ProviderProfileStoreError.canonicalFileMissing(path: fileURL.path)
                    }
                    let legacy = try recoverInterruptedLegacyProfilesForDowngradeWithoutLock()
                    return ProviderProfileStorageDowngradeResult(
                        status: .alreadyLegacy,
                        revision: legacy.revision,
                        profileCount: legacy.profiles.count
                    )
                }
            }

            let legacyState = legacyStorageStateWithoutLock()
            guard legacyState != .configuration else {
                throw ProviderProfileStoreError.legacyWriterDetected(path: legacyFileURL.path)
            }
            let canonicalData = try Data(contentsOf: fileURL)
            let canonical = try JSONDecoder().decode(ProviderProfilesFile.self, from: canonicalData)
            var legacyPreparation: LegacyFilePreparation?

            do {
                let legacyData = try encodedLegacyPayload(profiles: canonical.profiles)
                switch legacyState {
                case .tombstone:
                    legacyPreparation = try replaceLegacyPayloadWithoutLock(
                        expectedData: Data(contentsOf: legacyFileURL),
                        replacementData: legacyData,
                        conflictError: .legacyChangedDuringMigration(path: legacyFileURL.path)
                    )
                case .absent:
                    do {
                        try createLegacyFileExclusivelyWithoutLock(data: legacyData)
                        legacyPreparation = .created(publishedData: legacyData)
                    } catch let error as NSError
                        where error.domain == NSPOSIXErrorDomain && error.code == Int(EEXIST) {
                        throw ProviderProfileStoreError.legacyChangedDuringMigration(
                            path: legacyFileURL.path
                        )
                    }
                case .unmanaged:
                    legacyPreparation = .unmanaged
                case .configuration:
                    throw ProviderProfileStoreError.legacyWriterDetected(path: legacyFileURL.path)
                }
                try migrationCutoverHook?()
                guard try Data(contentsOf: legacyFileURL) == legacyData else {
                    throw ProviderProfileStoreError.legacyChangedDuringMigration(path: legacyFileURL.path)
                }
                try FileManager.default.removeItem(at: fileURL)
                if let legacyPreparation {
                    try finishLegacyFilePreparation(legacyPreparation)
                }
                if let legacySnapshotURL {
                    try? FileManager.default.removeItem(at: legacySnapshotURL)
                }
            } catch {
                do {
                    if !FileManager.default.fileExists(atPath: fileURL.path) {
                        try canonicalData.write(to: fileURL, options: [.atomic])
                        try Self.restrictFilePermissions(fileURL)
                    }
                    if let legacyPreparation {
                        try rollbackLegacyFilePreparationWithoutLock(legacyPreparation)
                    }
                } catch {
                    throw ProviderProfileStoreError.metadataRollbackFailed
                }
                throw error
            }

            return ProviderProfileStorageDowngradeResult(
                status: .downgraded,
                revision: canonical.revision,
                profileCount: canonical.profiles.count
            )
        }
    }

    public func rollbackLegacyMigration(
        expectedCanonicalRevision: UInt64,
        secretStore: any SecretStore
    ) throws -> ProviderProfileStorageRollbackResult {
        var credentialReferencesToRemove: [String] = []
        try withFileLock(operation: LOCK_EX, createDirectory: false) {
            guard let legacyFileURL, let legacySnapshotURL else {
                return
            }
            guard legacyStorageStateWithoutLock() == .tombstone,
                  FileManager.default.fileExists(atPath: fileURL.path),
                  FileManager.default.fileExists(atPath: legacySnapshotURL.path) else {
                throw ProviderProfileStoreError.migrationRollbackFailed
            }

            let canonical = try loadProfilesWithoutLock()
            guard canonical.revision == expectedCanonicalRevision else {
                throw ProviderProfileStoreError.revisionConflict(
                    expected: expectedCanonicalRevision,
                    actual: canonical.revision
                )
            }
            let legacyData = try Data(contentsOf: legacySnapshotURL)
            let legacy = try JSONDecoder().decode(LegacyProviderProfilesEnvelope.self, from: legacyData)
            let legacyReferences = Set(legacy.profiles.compactMap(\.secretName))
            let canonicalData = try Data(contentsOf: fileURL)
            let tombstoneData = try Data(contentsOf: legacyFileURL)
            credentialReferencesToRemove = canonical.profiles
                .compactMap(\.secretName)
                .filter { !legacyReferences.contains($0) }

            var legacyPreparation: LegacyFilePreparation?
            do {
                legacyPreparation = try replaceLegacyPayloadWithoutLock(
                    expectedData: tombstoneData,
                    replacementData: legacyData,
                    conflictError: .legacyChangedDuringMigration(path: legacyFileURL.path)
                )
                try FileManager.default.removeItem(at: fileURL)
                if let legacyPreparation {
                    try finishLegacyFilePreparation(legacyPreparation)
                }
                try? FileManager.default.removeItem(at: legacySnapshotURL)
            } catch {
                credentialReferencesToRemove = []
                do {
                    if !FileManager.default.fileExists(atPath: fileURL.path) {
                        try canonicalData.write(to: fileURL, options: [.atomic])
                        try Self.restrictFilePermissions(fileURL)
                    }
                    if let legacyPreparation {
                        try rollbackLegacyFilePreparationWithoutLock(legacyPreparation)
                    }
                } catch {
                    throw ProviderProfileStoreError.metadataRollbackFailed
                }
                throw ProviderProfileStoreError.migrationRollbackFailed
            }
        }

        var removed = 0
        var failures = 0
        for reference in Set(credentialReferencesToRemove) {
            do {
                try secretStore.deleteSecret(named: reference)
                removed += 1
            } catch {
                failures += 1
            }
        }
        return ProviderProfileStorageRollbackResult(
            credentialsRemoved: removed,
            credentialCleanupFailures: failures
        )
    }

    public func transactProfiles(
        expectedRevision: UInt64,
        _ mutation: (ProviderProfilesFile) throws -> ProviderProfilesFile
    ) throws -> ProviderProfilesFile {
        let committed = try withFileLock(operation: LOCK_EX, createDirectory: true) {
            try requireCanonicalStorageReadyForMutationWithoutLock()
            let current = try loadProfilesWithoutLock()
            guard current.revision == expectedRevision else {
                throw ProviderProfileStoreError.revisionConflict(
                    expected: expectedRevision,
                    actual: current.revision
                )
            }
            guard current.revision < UInt64.max else {
                throw ProviderProfileStoreError.revisionOverflow
            }

            var updated = try mutation(current)
            updated.schemaVersion = ProviderProfilesFile.currentSchemaVersion
            updated.revision = current.revision + 1
            try writeProfilesAndTombstoneWithoutLock(updated)
            return updated
        }
        revisionSignal.postProviderProfilesChanged(revision: committed.revision)
        return committed
    }

    private func loadProfilesWithoutLock() throws -> ProviderProfilesFile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ProviderProfilesFile()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(ProviderProfilesFile.self, from: data)
    }

    private func writeProfilesWithoutLock(_ profiles: ProviderProfilesFile) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profiles)
        try data.write(to: fileURL, options: [.atomic])
        try Self.restrictFilePermissions(fileURL)
    }

    private func writeProfilesAndTombstoneWithoutLock(_ profiles: ProviderProfilesFile) throws {
        let previousData = try? Data(contentsOf: fileURL)
        var tombstonePreparation: LegacyFilePreparation?
        do {
            try writeProfilesWithoutLock(profiles)
            try migrationCutoverHook?()
            tombstonePreparation = try prepareLegacyTombstoneForCanonicalWithoutLock(
                conflictError: .legacyWriterDetected(path: legacyFileURL?.path ?? "<unmanaged>")
            )
            guard legacyStorageStateWithoutLock() != .configuration else {
                throw ProviderProfileStoreError.legacyWriterDetected(
                    path: legacyFileURL?.path ?? "<unmanaged>"
                )
            }
            if let tombstonePreparation {
                try finishLegacyFilePreparation(tombstonePreparation)
            }
        } catch {
            do {
                if let previousData {
                    try previousData.write(to: fileURL, options: [.atomic])
                    try Self.restrictFilePermissions(fileURL)
                } else if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                if let tombstonePreparation {
                    try rollbackLegacyFilePreparationWithoutLock(tombstonePreparation)
                }
            } catch {
                throw ProviderProfileStoreError.metadataRollbackFailed
            }
            throw error
        }
    }

    private func requireCanonicalStorageReadyForMutationWithoutLock() throws {
        guard let legacyFileURL else {
            return
        }
        let canonicalExists = FileManager.default.fileExists(atPath: fileURL.path)
        switch legacyStorageStateWithoutLock() {
        case .unmanaged, .absent:
            if !canonicalExists, interruptedLegacyMigrationEvidenceExistsWithoutLock() {
                throw ProviderProfileStoreError.migrationRequired(path: legacyFileURL.path)
            }
            return
        case .configuration:
            throw canonicalExists
                ? ProviderProfileStoreError.legacyWriterDetected(path: legacyFileURL.path)
                : ProviderProfileStoreError.migrationRequired(path: legacyFileURL.path)
        case .tombstone:
            if !canonicalExists, legacyTombstoneExpectsCanonicalWithoutLock() {
                throw ProviderProfileStoreError.canonicalFileMissing(path: fileURL.path)
            }
            if !canonicalExists {
                throw ProviderProfileStoreError.migrationRequired(path: legacyFileURL.path)
            }
        }
    }

    private func requireCanonicalStorageReadyForReadWithoutLock() throws {
        guard let legacyFileURL else {
            return
        }
        switch legacyStorageStateWithoutLock() {
        case .unmanaged:
            return
        case .absent:
            if interruptedLegacyMigrationEvidenceExistsWithoutLock() {
                throw ProviderProfileStoreError.migrationRequired(path: legacyFileURL.path)
            }
            return
        case .configuration:
            throw ProviderProfileStoreError.migrationRequired(path: legacyFileURL.path)
        case .tombstone:
            if legacyTombstoneExpectsCanonicalWithoutLock() {
                throw ProviderProfileStoreError.canonicalFileMissing(path: fileURL.path)
            }
            throw ProviderProfileStoreError.migrationRequired(path: legacyFileURL.path)
        }
    }

    private func interruptedLegacyMigrationEvidenceExistsWithoutLock() -> Bool {
        guard let legacySnapshotURL else {
            return false
        }
        return FileManager.default.fileExists(atPath: legacySnapshotURL.path)
    }

    private func recoverInterruptedLegacyMigrationWithoutLock() throws -> Data? {
        guard let legacyFileURL, let legacySnapshotURL,
              FileManager.default.fileExists(atPath: legacySnapshotURL.path) else {
            return nil
        }
        let snapshotData = try Data(contentsOf: legacySnapshotURL)
        let directory = legacyFileURL.deletingLastPathComponent()
        let matchingClaimURL = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasPrefix(Self.legacyConflictFilenamePrefix) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .first { (try? Data(contentsOf: $0)) == snapshotData }
        guard let matchingClaimURL else {
            return nil
        }

        switch legacyStorageStateWithoutLock() {
        case .absent:
            do {
                try createLegacyFileExclusivelyWithoutLock(data: snapshotData)
            } catch {
                throw ProviderProfileStoreError.legacyChangedDuringMigration(path: legacyFileURL.path)
            }
        case .tombstone:
            guard !legacyTombstoneExpectsCanonicalWithoutLock() else {
                return nil
            }
            let preparation = try replaceLegacyPayloadWithoutLock(
                expectedData: Data(contentsOf: legacyFileURL),
                replacementData: snapshotData,
                conflictError: .legacyChangedDuringMigration(path: legacyFileURL.path)
            )
            try finishLegacyFilePreparation(preparation)
        case .configuration:
            guard try Data(contentsOf: legacyFileURL) == snapshotData else {
                throw ProviderProfileStoreError.legacyChangedDuringMigration(path: legacyFileURL.path)
            }
        case .unmanaged:
            return nil
        }
        guard try Data(contentsOf: legacyFileURL) == snapshotData else {
            throw ProviderProfileStoreError.legacyChangedDuringMigration(path: legacyFileURL.path)
        }
        try? FileManager.default.removeItem(at: matchingClaimURL)
        return snapshotData
    }

    private func recoverInterruptedLegacyProfilesForDowngradeWithoutLock() throws
        -> LegacyProviderProfilesEnvelope {
        guard let recoveredData = try recoverInterruptedLegacyMigrationWithoutLock() else {
            throw ProviderProfileStoreError.migrationRollbackFailed
        }
        let legacy = try JSONDecoder().decode(LegacyProviderProfilesEnvelope.self, from: recoveredData)
        if let legacySnapshotURL {
            try? FileManager.default.removeItem(at: legacySnapshotURL)
        }
        return legacy
    }

    private func legacyStorageStateWithoutLock() -> LegacyProviderProfileStorageState {
        guard let legacyFileURL else {
            return .unmanaged
        }
        guard let data = try? Data(contentsOf: legacyFileURL) else {
            return FileManager.default.fileExists(atPath: legacyFileURL.path) ? .configuration : .absent
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["schemaVersion"] as? String == Self.legacyTombstoneSchemaVersion,
              object["canonicalFile"] as? String == Self.canonicalFilename else {
            return .configuration
        }
        return .tombstone
    }

    private func writeLegacySnapshot(_ data: Data) throws {
        guard let legacySnapshotURL else {
            return
        }
        try data.write(to: legacySnapshotURL, options: [.atomic])
        try Self.restrictFilePermissions(legacySnapshotURL)
    }

    private func writeLegacyPayloadWithoutLock(profiles: [ProviderProfile]) throws {
        guard let legacyFileURL else {
            return
        }
        try encodedLegacyPayload(profiles: profiles).write(to: legacyFileURL, options: [.atomic])
        try Self.restrictFilePermissions(legacyFileURL)
    }

    private func encodedLegacyPayload(profiles: [ProviderProfile]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(LegacyProviderProfilesPayload(profiles: profiles))
    }

    private func legacyTombstoneExpectsCanonicalWithoutLock() -> Bool {
        guard let legacyFileURL,
              let data = try? Data(contentsOf: legacyFileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if let expected = object["canonicalExpected"] as? Bool {
            return expected
        }
        return legacySnapshotURL.map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false
    }

    private func prepareLegacyTombstoneForCanonicalWithoutLock(
        conflictError: ProviderProfileStoreError
    ) throws -> LegacyFilePreparation {
        guard let legacyFileURL else {
            return .unmanaged
        }
        switch legacyStorageStateWithoutLock() {
        case .unmanaged:
            return .unmanaged
        case .configuration:
            throw conflictError
        case .tombstone:
            if legacyTombstoneExpectsCanonicalWithoutLock() {
                return .unchanged
            }
            return try replaceLegacyPayloadWithTombstoneWithoutLock(
                expectedData: Data(contentsOf: legacyFileURL),
                canonicalExpected: true,
                conflictError: conflictError
            )
        case .absent:
            let tombstoneData = Self.legacyTombstoneData(canonicalExpected: true)
            do {
                try createLegacyFileExclusivelyWithoutLock(data: tombstoneData)
                return .created(publishedData: tombstoneData)
            } catch let error as NSError
                where error.domain == NSPOSIXErrorDomain && error.code == Int(EEXIST) {
                throw conflictError
            }
        }
    }

    private func replaceLegacyPayloadWithTombstoneWithoutLock(
        expectedData: Data,
        canonicalExpected: Bool,
        conflictError: ProviderProfileStoreError
    ) throws -> LegacyFilePreparation {
        try replaceLegacyPayloadWithoutLock(
            expectedData: expectedData,
            replacementData: Self.legacyTombstoneData(canonicalExpected: canonicalExpected),
            conflictError: conflictError
        )
    }

    private func replaceLegacyPayloadWithoutLock(
        expectedData: Data,
        replacementData: Data,
        conflictError: ProviderProfileStoreError
    ) throws -> LegacyFilePreparation {
        guard let legacyFileURL else {
            return .unmanaged
        }
        let claimURL = legacyFileURL.deletingLastPathComponent().appendingPathComponent(
            "\(Self.legacyConflictFilenamePrefix)\(UUID().uuidString).json"
        )
        guard rename(legacyFileURL.path, claimURL.path) == 0 else {
            throw conflictError
        }
        do {
            guard try Data(contentsOf: claimURL) == expectedData else {
                try restoreClaimedLegacyPayloadWithoutLock(claimURL)
                throw conflictError
            }
            do {
                try createLegacyFileExclusivelyWithoutLock(data: replacementData)
            } catch {
                try restoreClaimedLegacyPayloadWithoutLock(claimURL)
                throw conflictError
            }
            return .replaced(claimURL: claimURL, publishedData: replacementData)
        } catch {
            if FileManager.default.fileExists(atPath: claimURL.path) {
                try? Self.restrictFilePermissions(claimURL)
            }
            throw error
        }
    }

    private func createLegacyFileExclusivelyWithoutLock(data: Data) throws {
        guard let legacyFileURL else {
            return
        }
        let descriptor = open(
            legacyFileURL.path,
            O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        var completed = false
        defer {
            _ = close(descriptor)
            if !completed {
                _ = unlink(legacyFileURL.path)
            }
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        completed = true
    }

    private func restoreClaimedLegacyPayloadWithoutLock(_ claimURL: URL) throws {
        guard let legacyFileURL else {
            return
        }
        if !FileManager.default.fileExists(atPath: legacyFileURL.path) {
            guard rename(claimURL.path, legacyFileURL.path) == 0 else {
                throw ProviderProfileStoreError.metadataRollbackFailed
            }
            return
        }
        // A newer pre-v2 payload already owns the legacy path. Keep the
        // permission-restricted claim as conflict evidence rather than
        // overwriting either writer or silently dropping an intermediate save.
        try Self.restrictFilePermissions(claimURL)
    }

    private func rollbackLegacyFilePreparationWithoutLock(
        _ preparation: LegacyFilePreparation
    ) throws {
        switch preparation {
        case .unmanaged, .unchanged:
            return
        case .created(let publishedData):
            if let legacyFileURL,
               (try? Data(contentsOf: legacyFileURL)) == publishedData {
                try FileManager.default.removeItem(at: legacyFileURL)
            }
        case .replaced(let claimURL, let publishedData):
            if let legacyFileURL,
               (try? Data(contentsOf: legacyFileURL)) == publishedData {
                try FileManager.default.removeItem(at: legacyFileURL)
            }
            try restoreClaimedLegacyPayloadWithoutLock(claimURL)
        }
    }

    private func finishLegacyFilePreparation(
        _ preparation: LegacyFilePreparation
    ) throws {
        guard case .replaced(let claimURL, _) = preparation else {
            return
        }
        try FileManager.default.removeItem(at: claimURL)
    }

    private static func legacyTombstoneData(canonicalExpected: Bool) -> Data {
        Data(
            """
            {
              "canonicalFile" : "\(canonicalFilename)",
              "canonicalExpected" : \(canonicalExpected),
              "profiles" : [],
              "schemaVersion" : "\(legacyTombstoneSchemaVersion)"
            }

            """.utf8
        )
    }

    private static func restrictFilePermissions(_ url: URL) throws {
        guard chmod(url.path, S_IRUSR | S_IWUSR) == 0 else {
            throw ProviderProfileStoreError.filePermissionUpdateFailed(path: url.path, code: errno)
        }
    }

    private func withFileLock<T>(
        operation: Int32,
        createDirectory: Bool,
        _ body: () throws -> T
    ) throws -> T {
        try withLock(
            at: lockFileURL,
            operation: operation,
            createDirectory: createDirectory,
            body
        )
    }

    private func withLock<T>(
        at lockURL: URL,
        operation: Int32,
        createDirectory: Bool,
        _ body: () throws -> T
    ) throws -> T {
        let directory = lockURL.deletingLastPathComponent()
        if createDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw ProviderProfileStoreError.lockFailed(path: lockURL.path, code: errno)
        }
        defer {
            _ = flock(descriptor, LOCK_UN)
            _ = close(descriptor)
        }

        while flock(descriptor, operation) != 0 {
            guard errno == EINTR else {
                throw ProviderProfileStoreError.lockFailed(path: lockURL.path, code: errno)
            }
        }
        return try body()
    }
}

public protocol SecretStore: Sendable {
    func secret(named name: String) throws -> String?
    func setSecret(_ value: String, named name: String) throws
    func deleteSecret(named name: String) throws
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [String: String]
    private let lock = NSLock()

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    public func secret(named name: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[name]
    }

    public func setSecret(_ value: String, named name: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[name] = value
    }

    public func deleteSecret(named name: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: name)
    }
}

public struct DictionarySecretStore: SecretStore {
    private let values: [String: String]

    public init(values: [String: String]) {
        self.values = values
    }

    public func secret(named name: String) throws -> String? {
        values[name]
    }

    public func setSecret(_ value: String, named name: String) throws {
        throw ProviderError.invalidResponse("DictionarySecretStore is read-only")
    }

    public func deleteSecret(named name: String) throws {
        throw ProviderError.invalidResponse("DictionarySecretStore is read-only")
    }
}

public struct ProviderProfileResolver {
    public let secretStore: any SecretStore

    public init(secretStore: any SecretStore) {
        self.secretStore = secretStore
    }

    public func configuration(for profile: ProviderProfile) throws -> ProviderConfiguration {
        guard ProviderEndpointURLPolicy.isAllowedRuntimeURL(profile.baseURL) else {
            throw ProviderError.invalidResponse("provider base URL contains unsupported credentials or fragment")
        }
        let apiKey: String?
        if let secretName = profile.secretName {
            guard let resolvedSecret = try secretStore.secret(named: secretName),
                  !resolvedSecret.isEmpty else {
                throw ProviderError.missingAPIKey
            }
            apiKey = resolvedSecret
        } else {
            apiKey = nil
        }

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
}

public enum ProviderProfileDefaults {
    public static func openAICompatible(
        displayName: String = "OpenAI Compatible",
        baseURL: URL = URL(string: "https://api.openai.com")!,
        model: String = "gpt-4.1-mini",
        secretName: String = "knowtype.openai.apiKey"
    ) -> ProviderProfile {
        ProviderProfile(
            displayName: displayName,
            kind: .openAIChat,
            baseURL: baseURL,
            model: model,
            secretName: secretName,
            isDefault: true
        )
    }
}
