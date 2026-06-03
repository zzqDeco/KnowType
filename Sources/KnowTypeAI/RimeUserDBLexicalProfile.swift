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
        [firstColumn, secondColumn]
            .enumerated()
            .compactMap { index, column -> (text: String, score: Int, index: Int)? in
                let raw = String(column).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let text = LexicalContextBuilder.sanitizedProfileText(raw) else {
                    return nil
                }
                return (text, metadataTextScore(raw), index)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.index < rhs.index
                }
                return lhs.score > rhs.score
            }
            .first { $0.score >= 0 }?
            .text
    }

    private func looksLikeRimeCode(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        return trimmed.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (97...122).contains(value)
                || (48...57).contains(value)
                || value == 0x20
                || value == 0x27
                || value == 0x2D
                || value == 0x5F
        }
    }

    private func metadataTextScore(_ value: String) -> Int {
        var score = 0
        if value.range(of: #"\p{Han}"#, options: .regularExpression) != nil {
            score += 6
        }
        if value.unicodeScalars.contains(where: { $0.value > 127 }) {
            score += 2
        }
        if looksLikeRimeCode(value) {
            score -= 4
        }
        return score
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

public struct LexicalProfileSaveTransaction: Sendable {
    public let profile: PersistentLexicalProfile
    fileprivate let stagedWrites: [StagedLexicalProfileWrite]
}

private struct StagedLexicalProfileWrite: Sendable {
    var temporaryURL: URL
    var destinationURL: URL
}

private struct PublishedLexicalProfileBackup: Sendable {
    var destinationURL: URL
    var backupURL: URL?
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

    public func reloadFromDisk() -> PersistentLexicalProfile? {
        guard let jsonURL else {
            return currentProfile()
        }
        let reloaded = Self.loadProfile(from: jsonURL, fileManager: fileManager)
        lock.lock()
        profile = reloaded
        lock.unlock()
        return reloaded
    }

    @discardableResult
    public func save(
        snapshot: LexicalContextSnapshot,
        schemaID: String,
        rimeSnapshotURL: URL?,
        rimeSnapshotModifiedAt: Date?,
        generatedAt: Date = Date()
    ) throws -> PersistentLexicalProfile {
        let transaction = try prepareSave(
            snapshot: snapshot,
            schemaID: schemaID,
            rimeSnapshotURL: rimeSnapshotURL,
            rimeSnapshotModifiedAt: rimeSnapshotModifiedAt,
            generatedAt: generatedAt
        )
        return try commitPreparedSave(transaction)
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
        guard shouldCommit() else {
            return nil
        }
        let transaction = try prepareSave(
            snapshot: snapshot,
            schemaID: schemaID,
            rimeSnapshotURL: rimeSnapshotURL,
            rimeSnapshotModifiedAt: rimeSnapshotModifiedAt,
            generatedAt: generatedAt
        )
        guard shouldCommit() else {
            discardPreparedSave(transaction)
            return nil
        }
        return try commitPreparedSaveIfCurrent(transaction, shouldCommit: shouldCommit)
    }

    public func prepareSave(
        snapshot: LexicalContextSnapshot,
        schemaID: String,
        rimeSnapshotURL: URL?,
        rimeSnapshotModifiedAt: Date?,
        generatedAt: Date = Date()
    ) throws -> LexicalProfileSaveTransaction {
        let next = PersistentLexicalProfile(
            generatedAt: generatedAt,
            schemaID: schemaID,
            rimeSnapshotPath: rimeSnapshotURL?.path,
            rimeSnapshotModifiedAt: rimeSnapshotModifiedAt,
            lexicalContext: snapshot
        )
        var stagedWrites: [StagedLexicalProfileWrite] = []
        do {
            if let jsonURL {
                stagedWrites.append(try stageJSON(next, to: jsonURL))
            }
            if let markdownURL {
                stagedWrites.append(try stageWrite(Data(snapshot.markdown.utf8), to: markdownURL))
            }
            return LexicalProfileSaveTransaction(profile: next, stagedWrites: stagedWrites)
        } catch {
            cleanup(stagedWrites)
            throw error
        }
    }

    @discardableResult
    public func commitPreparedSave(_ transaction: LexicalProfileSaveTransaction) throws -> PersistentLexicalProfile {
        _ = try publish(transaction, shouldContinue: { true })
        lock.lock()
        profile = transaction.profile
        lock.unlock()
        return transaction.profile
    }

    @discardableResult
    public func commitPreparedSaveIfCurrent(
        _ transaction: LexicalProfileSaveTransaction,
        shouldCommit: () -> Bool
    ) throws -> PersistentLexicalProfile? {
        guard shouldCommit() else {
            discardPreparedSave(transaction)
            return nil
        }
        guard try publish(transaction, shouldContinue: shouldCommit) else {
            return nil
        }
        lock.lock()
        profile = transaction.profile
        lock.unlock()
        return transaction.profile
    }

    public func discardPreparedSave(_ transaction: LexicalProfileSaveTransaction) {
        cleanup(transaction.stagedWrites)
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

    private func stageJSON(_ profile: PersistentLexicalProfile, to url: URL) throws -> StagedLexicalProfileWrite {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)
        return try stageWrite(data, to: url)
    }

    private func atomicWrite(_ content: String, to url: URL) throws {
        try atomicWrite(Data(content.utf8), to: url)
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        let stagedWrite = try stageWrite(data, to: url)
        try promote(stagedWrite)
    }

    private func stageWrite(_ data: Data, to url: URL) throws -> StagedLexicalProfileWrite {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporaryURL, options: .atomic)
        return StagedLexicalProfileWrite(temporaryURL: temporaryURL, destinationURL: url)
    }

    private func promote(_ stagedWrite: StagedLexicalProfileWrite) throws {
        let url = stagedWrite.destinationURL
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: stagedWrite.temporaryURL)
        } else {
            try fileManager.moveItem(at: stagedWrite.temporaryURL, to: url)
        }
    }

    private func publish(
        _ transaction: LexicalProfileSaveTransaction,
        shouldContinue: () -> Bool
    ) throws -> Bool {
        var backups: [PublishedLexicalProfileBackup] = []
        do {
            for stagedWrite in transaction.stagedWrites {
                guard shouldContinue() else {
                    rollback(backups)
                    cleanup(transaction.stagedWrites)
                    return false
                }
                let backup = try backupDestination(stagedWrite.destinationURL)
                backups.append(backup)
                try promote(stagedWrite)
            }
            guard shouldContinue() else {
                rollback(backups)
                cleanup(transaction.stagedWrites)
                return false
            }
            cleanupBackups(backups)
            return true
        } catch {
            rollback(backups)
            cleanup(transaction.stagedWrites)
            throw error
        }
    }

    private func backupDestination(_ destinationURL: URL) throws -> PublishedLexicalProfileBackup {
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            return PublishedLexicalProfileBackup(destinationURL: destinationURL, backupURL: nil)
        }
        let directory = destinationURL.deletingLastPathComponent()
        let backupURL = directory.appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString).bak")
        try fileManager.copyItem(at: destinationURL, to: backupURL)
        return PublishedLexicalProfileBackup(destinationURL: destinationURL, backupURL: backupURL)
    }

    private func rollback(_ backups: [PublishedLexicalProfileBackup]) {
        for backup in backups.reversed() {
            if fileManager.fileExists(atPath: backup.destinationURL.path) {
                try? fileManager.removeItem(at: backup.destinationURL)
            }
            if let backupURL = backup.backupURL {
                try? fileManager.moveItem(at: backupURL, to: backup.destinationURL)
            }
        }
    }

    private func cleanupBackup(_ backup: PublishedLexicalProfileBackup) {
        if let backupURL = backup.backupURL {
            try? fileManager.removeItem(at: backupURL)
        }
    }

    private func cleanupBackups(_ backups: [PublishedLexicalProfileBackup]) {
        for backup in backups {
            cleanupBackup(backup)
        }
    }

    private func cleanup(_ stagedWrites: [StagedLexicalProfileWrite]) {
        for stagedWrite in stagedWrites {
            try? fileManager.removeItem(at: stagedWrite.temporaryURL)
        }
    }
}
