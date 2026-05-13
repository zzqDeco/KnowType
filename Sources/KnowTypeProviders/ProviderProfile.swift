import Foundation
import KnowTypeCore

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
    public var schemaVersion: Int
    public var profiles: [ProviderProfile]

    public init(schemaVersion: Int = 1, profiles: [ProviderProfile] = []) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
    }
}

public protocol ProviderProfileStore: Sendable {
    func loadProfiles() throws -> ProviderProfilesFile
    func saveProfiles(_ profiles: ProviderProfilesFile) throws
}

public struct FileProviderProfileStore: ProviderProfileStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultStore() throws -> FileProviderProfileStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("KnowType", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return FileProviderProfileStore(fileURL: directory.appendingPathComponent("providers.json"))
    }

    public func loadProfiles() throws -> ProviderProfilesFile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ProviderProfilesFile()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(ProviderProfilesFile.self, from: data)
    }

    public func saveProfiles(_ profiles: ProviderProfilesFile) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profiles)
        try data.write(to: fileURL, options: [.atomic])
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
