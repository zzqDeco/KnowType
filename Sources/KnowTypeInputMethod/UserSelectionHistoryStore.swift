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

    public static func defaultStore(createDirectory: Bool = true) throws -> FileUserSelectionHistoryStore {
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
    ) throws -> FileUserSelectionHistoryStore {
        let directory = base.appendingPathComponent("KnowType", isDirectory: true)
        if createDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
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

public final class UserSelectionHistoryPersistence: @unchecked Sendable {
    private static let queue = DispatchQueue(label: "KnowType.UserSelectionHistoryPersistence")

    private let store: any UserSelectionHistoryStoring

    public init(store: any UserSelectionHistoryStoring) {
        self.store = store
    }

    public func loadHistory(maxEntries: Int) -> [String] {
        Self.queue.sync {
            (try? store.loadHistory(maxEntries: maxEntries)) ?? []
        }
    }

    public func recordSelection(
        _ text: String,
        currentHistory: [String],
        maxEntries: Int
    ) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return sanitized(currentHistory, maxEntries: maxEntries)
        }
        let nextHistory = sanitized(currentHistory + [trimmed], maxEntries: maxEntries)
        let store = store
        Self.queue.async {
            Self.persist(selection: trimmed, store: store, maxEntries: maxEntries)
        }
        return nextHistory
    }

    public func flushHistory(_ currentHistory: [String], maxEntries: Int) {
        Self.queue.sync {}
    }

    private static func persist(
        selection: String,
        store: any UserSelectionHistoryStoring,
        maxEntries: Int
    ) {
        let diskHistory = (try? store.loadHistory(maxEntries: maxEntries)) ?? []
        let merged = sanitized(diskHistory + [selection], maxEntries: maxEntries)
        try? store.saveHistory(merged, maxEntries: maxEntries)
    }
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
