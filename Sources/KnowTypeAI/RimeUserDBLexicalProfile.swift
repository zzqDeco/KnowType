import Foundation

public struct RimeUserDBTextSnapshot: Sendable, Equatable {
    public var schemaID: String
    public var fileURL: URL
    public var modifiedAt: Date?
    public var content: String

    public init(
        schemaID: String,
        fileURL: URL,
        modifiedAt: Date? = nil,
        content: String
    ) {
        self.schemaID = schemaID
        self.fileURL = fileURL
        self.modifiedAt = modifiedAt
        self.content = content
    }
}

public protocol RimeUserDBTextSnapshotProviding: Sendable {
    func userDBTextSnapshot(schemaID: String) async throws -> RimeUserDBTextSnapshot
}

public struct RimeUserDBTextParser: Sendable {
    public var maxTerms: Int

    public init(maxTerms: Int = 64) {
        self.maxTerms = max(1, maxTerms)
    }

    public func parse(_ snapshot: RimeUserDBTextSnapshot) -> [LexicalContextTerm] {
        parse(snapshot.content)
    }

    public func parse(_ content: String) -> [LexicalContextTerm] {
        var bestFrequencyByText: [String: Double] = [:]
        for line in content.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }
            let columns = trimmed.split(separator: "\t", omittingEmptySubsequences: false)
            guard let row = parsedRow(columns: columns),
                  row.frequency > 0 else {
                continue
            }
            bestFrequencyByText[row.text] = max(bestFrequencyByText[row.text] ?? 0, row.frequency)
        }

        let maxFrequency = max(bestFrequencyByText.values.max() ?? 1, 1)
        return bestFrequencyByText
            .map { text, frequency in
                LexicalContextTerm(
                    text: text,
                    score: min(1, frequency / maxFrequency),
                    source: "rime-userdb"
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.text < rhs.text
                }
                return lhs.score > rhs.score
            }
            .prefix(maxTerms)
            .map { $0 }
    }

    private func parsedRow(columns: [Substring]) -> (text: String, frequency: Double)? {
        guard columns.count >= 3 else {
            return nil
        }
        let thirdColumn = columns[2].trimmingCharacters(in: .whitespacesAndNewlines)
        if let frequency = Double(thirdColumn),
           let text = LexicalContextBuilder.sanitizedProfileText(String(columns[0])) {
            return (text, frequency)
        }

        let metadata = columns[2...]
            .map { String($0) }
            .joined(separator: " ")
        guard let frequency = metadataFrequency(metadata),
              let text = metadataRowText(columns[0], columns[1]) else {
            return nil
        }
        return (text, frequency)
    }

    private func metadataRowText(_ firstColumn: Substring, _ secondColumn: Substring) -> String? {
        let first = String(firstColumn)
        let second = String(secondColumn)
        let firstText = LexicalContextBuilder.sanitizedProfileText(first)
        let secondText = LexicalContextBuilder.sanitizedProfileText(second)
        switch (looksLikeRimeCode(first), looksLikeRimeCode(second)) {
        case (true, false):
            return secondText
        case (false, true):
            return firstText
        default:
            return secondText ?? firstText
        }
    }

    private func looksLikeRimeCode(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        return trimmed.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (97...122).contains(value)
                || value == 0x20
                || value == 0x27
                || value == 0x2D
                || value == 0x5F
        }
    }

    private func metadataFrequency(_ metadata: String) -> Double? {
        for token in metadata.split(whereSeparator: \.isWhitespace) {
            guard token.hasPrefix("c=") else {
                continue
            }
            return Double(token.dropFirst(2))
        }
        return nil
    }
}

public struct PersistentLexicalProfile: Codable, Sendable, Equatable {
    public var generatedAt: Date
    public var schemaID: String
    public var rimeSnapshotPath: String?
    public var rimeSnapshotModifiedAt: Date?
    public var lexicalContext: LexicalContextSnapshot
    public var sha256: String

    public init(
        generatedAt: Date = Date(),
        schemaID: String,
        rimeSnapshotPath: String?,
        rimeSnapshotModifiedAt: Date?,
        lexicalContext: LexicalContextSnapshot
    ) {
        self.generatedAt = generatedAt
        self.schemaID = schemaID
        self.rimeSnapshotPath = rimeSnapshotPath
        self.rimeSnapshotModifiedAt = rimeSnapshotModifiedAt
        self.lexicalContext = lexicalContext
        self.sha256 = lexicalContext.sha256
    }
}

public final class LexicalProfileStore: @unchecked Sendable {
    private let jsonURL: URL?
    private let markdownURL: URL?
    private let fileManager: FileManager
    private let lock = NSLock()
    private var profile: PersistentLexicalProfile?

    public init(
        jsonURL: URL = LexicalProfileStore.defaultJSONURL(),
        markdownURL: URL = AIUserDirectory.defaultDirectory().lexicalProfileURL,
        fileManager: FileManager = .default
    ) {
        self.jsonURL = jsonURL
        self.markdownURL = markdownURL
        self.fileManager = fileManager
        self.profile = Self.loadProfile(from: jsonURL, fileManager: fileManager)
    }

    private init(fileManager: FileManager = .default) {
        self.jsonURL = nil
        self.markdownURL = nil
        self.fileManager = fileManager
        self.profile = nil
    }

    public static func inMemory() -> LexicalProfileStore {
        LexicalProfileStore()
    }

    public static func defaultJSONURL(fileManager: FileManager = .default) -> URL {
        let root = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return root
            .appendingPathComponent("KnowType", isDirectory: true)
            .appendingPathComponent("AI", isDirectory: true)
            .appendingPathComponent("lexical-profile.json", isDirectory: false)
    }

    public func currentProfile() -> PersistentLexicalProfile? {
        lock.lock()
        let current = profile
        lock.unlock()
        return current
    }

    public func currentSnapshot() -> LexicalContextSnapshot? {
        currentProfile()?.lexicalContext
    }

    @discardableResult
    public func save(
        snapshot: LexicalContextSnapshot,
        schemaID: String,
        rimeSnapshotURL: URL?,
        rimeSnapshotModifiedAt: Date?,
        generatedAt: Date = Date()
    ) throws -> PersistentLexicalProfile {
        try saveIfCurrent(
            snapshot: snapshot,
            schemaID: schemaID,
            rimeSnapshotURL: rimeSnapshotURL,
            rimeSnapshotModifiedAt: rimeSnapshotModifiedAt,
            generatedAt: generatedAt,
            shouldCommit: { true }
        )!
    }

    @discardableResult
    public func saveIfCurrent(
        snapshot: LexicalContextSnapshot,
        schemaID: String,
        rimeSnapshotURL: URL?,
        rimeSnapshotModifiedAt: Date?,
        generatedAt: Date = Date(),
        shouldCommit: () -> Bool
    ) throws -> PersistentLexicalProfile? {
        let next = PersistentLexicalProfile(
            generatedAt: generatedAt,
            schemaID: schemaID,
            rimeSnapshotPath: rimeSnapshotURL?.path,
            rimeSnapshotModifiedAt: rimeSnapshotModifiedAt,
            lexicalContext: snapshot
        )
        guard shouldCommit() else {
            return nil
        }
        if let jsonURL {
            guard try writeJSON(next, to: jsonURL, shouldCommit: shouldCommit) else {
                return nil
            }
        }
        if let markdownURL {
            guard try atomicWrite(snapshot.markdown, to: markdownURL, shouldCommit: shouldCommit) else {
                return nil
            }
        }
        guard shouldCommit() else {
            return nil
        }
        lock.lock()
        profile = next
        lock.unlock()
        return next
    }

    private static func loadProfile(from url: URL, fileManager: FileManager) -> PersistentLexicalProfile? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PersistentLexicalProfile.self, from: data)
    }

    private func writeJSON(
        _ profile: PersistentLexicalProfile,
        to url: URL,
        shouldCommit: () -> Bool
    ) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)
        return try atomicWrite(data, to: url, shouldCommit: shouldCommit)
    }

    private func atomicWrite(_ content: String, to url: URL) throws {
        _ = try atomicWrite(content, to: url, shouldCommit: { true })
    }

    private func atomicWrite(
        _ content: String,
        to url: URL,
        shouldCommit: () -> Bool
    ) throws -> Bool {
        try atomicWrite(Data(content.utf8), to: url, shouldCommit: shouldCommit)
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        _ = try atomicWrite(data, to: url, shouldCommit: { true })
    }

    private func atomicWrite(
        _ data: Data,
        to url: URL,
        shouldCommit: () -> Bool
    ) throws -> Bool {
        guard shouldCommit() else {
            return false
        }
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporaryURL, options: .atomic)
        guard shouldCommit() else {
            try? fileManager.removeItem(at: temporaryURL)
            return false
        }
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: url)
        }
        return true
    }
}
