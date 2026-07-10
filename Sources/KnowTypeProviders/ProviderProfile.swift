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
    case legacyWriterQuarantined = "legacy_writer_quarantined"
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
    public static let legacyTombstoneSchemaVersion = "migrated-to-providers.v2.json"

    public let fileURL: URL
    public let lockFileURL: URL
    public let legacyFileURL: URL?
    public let legacySnapshotURL: URL?
    private let revisionSignal: any ProviderProfileRevisionSignaling

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
                if legacyStorageStateWithoutLock() == .configuration {
                    try preserveLegacySnapshotIfNeeded(Data(contentsOf: legacyFileURL))
                    try writeLegacyTombstoneWithoutLock()
                    return ProviderProfileStorageMigrationResult(
                        status: .legacyWriterQuarantined,
                        revision: current.revision,
                        profileCount: current.profiles.count
                    )
                }
                try writeLegacyTombstoneWithoutLock()
                return ProviderProfileStorageMigrationResult(
                    status: .alreadyCurrent,
                    revision: current.revision,
                    profileCount: current.profiles.count
                )
            }

            switch legacyStorageStateWithoutLock() {
            case .unmanaged:
                return ProviderProfileStorageMigrationResult(
                    status: .unmanaged,
                    revision: 0,
                    profileCount: 0
                )
            case .absent:
                try writeLegacyTombstoneWithoutLock()
                return ProviderProfileStorageMigrationResult(
                    status: .noLegacyConfiguration,
                    revision: 0,
                    profileCount: 0
                )
            case .tombstone:
                if let legacySnapshotURL,
                   FileManager.default.fileExists(atPath: legacySnapshotURL.path) {
                    throw ProviderProfileStoreError.canonicalFileMissing(path: fileURL.path)
                }
                return ProviderProfileStorageMigrationResult(
                    status: .noLegacyConfiguration,
                    revision: 0,
                    profileCount: 0
                )
            case .configuration:
                break
            }

            let legacyData = try Data(contentsOf: legacyFileURL)
            let legacy = try JSONDecoder().decode(LegacyProviderProfilesEnvelope.self, from: legacyData)
            guard (1...ProviderProfilesFile.currentSchemaVersion).contains(legacy.schemaVersion) else {
                throw ProviderProfileStoreError.unsupportedSchemaVersion(legacy.schemaVersion)
            }
            guard legacy.revision < UInt64.max else {
                throw ProviderProfileStoreError.revisionOverflow
            }
            try preserveLegacySnapshotIfNeeded(legacyData)

            var migratedProfiles = legacy.profiles
            var createdCredentialReferences: [String] = []
            var createdCredentialReferenceSet = Set<String>()
            var missingCredentials = 0

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
                          newReference != legacyReference,
                          createdCredentialReferenceSet.insert(newReference).inserted else {
                        throw ProviderProfileStoreError.invalidMigrationCredentialReference
                    }
                    try secretStore.setSecret(secret, named: newReference)
                    createdCredentialReferences.append(newReference)
                    migratedProfiles[index].secretName = newReference
                }

                let currentLegacyData = try Data(contentsOf: legacyFileURL)
                guard currentLegacyData == legacyData else {
                    throw ProviderProfileStoreError.legacyChangedDuringMigration(path: legacyFileURL.path)
                }

                let migrated = ProviderProfilesFile(
                    schemaVersion: ProviderProfilesFile.currentSchemaVersion,
                    revision: legacy.revision + 1,
                    profiles: migratedProfiles
                )
                do {
                    try writeProfilesWithoutLock(migrated)
                    try writeLegacyTombstoneWithoutLock()
                } catch {
                    try? FileManager.default.removeItem(at: fileURL)
                    try? legacyData.write(to: legacyFileURL, options: [.atomic])
                    try? Self.restrictFilePermissions(legacyFileURL)
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
                for reference in createdCredentialReferences {
                    try? secretStore.deleteSecret(named: reference)
                }
                throw error
            }
        }
        if let committedRevision {
            revisionSignal.postProviderProfilesChanged(revision: committedRevision)
        }
        return result
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
        do {
            try writeProfilesWithoutLock(profiles)
            try writeLegacyTombstoneWithoutLock()
        } catch {
            if let previousData {
                try? previousData.write(to: fileURL, options: [.atomic])
                try? Self.restrictFilePermissions(fileURL)
            } else {
                try? FileManager.default.removeItem(at: fileURL)
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
            return
        case .configuration:
            throw canonicalExists
                ? ProviderProfileStoreError.legacyWriterDetected(path: legacyFileURL.path)
                : ProviderProfileStoreError.migrationRequired(path: legacyFileURL.path)
        case .tombstone:
            if !canonicalExists,
               let legacySnapshotURL,
               FileManager.default.fileExists(atPath: legacySnapshotURL.path) {
                throw ProviderProfileStoreError.canonicalFileMissing(path: fileURL.path)
            }
        }
    }

    private func requireCanonicalStorageReadyForReadWithoutLock() throws {
        guard let legacyFileURL else {
            return
        }
        switch legacyStorageStateWithoutLock() {
        case .unmanaged, .absent:
            return
        case .configuration:
            throw ProviderProfileStoreError.migrationRequired(path: legacyFileURL.path)
        case .tombstone:
            if let legacySnapshotURL,
               FileManager.default.fileExists(atPath: legacySnapshotURL.path) {
                throw ProviderProfileStoreError.canonicalFileMissing(path: fileURL.path)
            }
        }
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

    private func preserveLegacySnapshotIfNeeded(_ data: Data) throws {
        guard let legacySnapshotURL,
              !FileManager.default.fileExists(atPath: legacySnapshotURL.path) else {
            return
        }
        try data.write(to: legacySnapshotURL, options: [.atomic])
        try Self.restrictFilePermissions(legacySnapshotURL)
    }

    private func writeLegacyTombstoneWithoutLock() throws {
        guard let legacyFileURL else {
            return
        }
        try Self.legacyTombstoneData.write(to: legacyFileURL, options: [.atomic])
        try Self.restrictFilePermissions(legacyFileURL)
    }

    private static var legacyTombstoneData: Data {
        Data(
            """
            {
              "canonicalFile" : "\(canonicalFilename)",
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
        let directory = lockFileURL.deletingLastPathComponent()
        if createDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let descriptor = open(lockFileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw ProviderProfileStoreError.lockFailed(path: lockFileURL.path, code: errno)
        }
        defer {
            _ = flock(descriptor, LOCK_UN)
            _ = close(descriptor)
        }

        while flock(descriptor, operation) != 0 {
            guard errno == EINTR else {
                throw ProviderProfileStoreError.lockFailed(path: lockFileURL.path, code: errno)
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
