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
        }
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
    public let fileURL: URL
    public let lockFileURL: URL
    private let revisionSignal: any ProviderProfileRevisionSignaling

    public init(
        fileURL: URL,
        revisionSignal: any ProviderProfileRevisionSignaling = DistributedProviderProfileRevisionSignal()
    ) {
        self.fileURL = fileURL
        self.lockFileURL = fileURL.appendingPathExtension("lock")
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
        return FileProviderProfileStore(fileURL: directory.appendingPathComponent("providers.json"))
    }

    public func loadProfiles() throws -> ProviderProfilesFile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ProviderProfilesFile()
        }
        return try withFileLock(operation: LOCK_SH, createDirectory: false) {
            try loadProfilesWithoutLock()
        }
    }

    public func saveProfiles(_ profiles: ProviderProfilesFile) throws {
        _ = try transactProfiles(expectedRevision: profiles.revision) { _ in profiles }
    }

    public func transactProfiles(
        expectedRevision: UInt64,
        _ mutation: (ProviderProfilesFile) throws -> ProviderProfilesFile
    ) throws -> ProviderProfilesFile {
        let committed = try withFileLock(operation: LOCK_EX, createDirectory: true) {
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
            try writeProfilesWithoutLock(updated)
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
