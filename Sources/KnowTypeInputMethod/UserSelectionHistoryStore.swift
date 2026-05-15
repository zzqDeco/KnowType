import Foundation

public struct UserSelectionHistoryFile: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var history: [String]

    public init(schemaVersion: Int = 1, history: [String] = []) {
        self.schemaVersion = schemaVersion
        self.history = history
    }
}

public protocol UserSelectionHistoryStoring: Sendable {
    func loadHistory(maxEntries: Int) throws -> [String]
    func saveHistory(_ history: [String], maxEntries: Int) throws
}

public struct FileUserSelectionHistoryStore: UserSelectionHistoryStoring {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultStore() throws -> FileUserSelectionHistoryStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("KnowType", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return FileUserSelectionHistoryStore(fileURL: directory.appendingPathComponent("user-selection-history.json"))
    }

    public func loadHistory(maxEntries: Int = 64) throws -> [String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        if let file = try? JSONDecoder().decode(UserSelectionHistoryFile.self, from: data) {
            return sanitized(file.history, maxEntries: maxEntries)
        }
        let legacyHistory = try JSONDecoder().decode([String].self, from: data)
        return sanitized(legacyHistory, maxEntries: maxEntries)
    }

    public func saveHistory(_ history: [String], maxEntries: Int = 64) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let file = UserSelectionHistoryFile(history: sanitized(history, maxEntries: maxEntries))
        let data = try encoder.encode(file)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func sanitized(_ history: [String], maxEntries: Int) -> [String] {
        let clean = history
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard maxEntries > 0 else {
            return []
        }
        return Array(clean.suffix(maxEntries))
    }
}
