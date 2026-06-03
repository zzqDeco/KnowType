import Foundation

public struct AIAcceptedLearningMaintenanceStatus: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var action: String?
    public var history: AIAcceptedLearningHistoryStatus
    public var summary: AIAcceptedLearningSummaryStatus
    public var mirror: AIAcceptedLearningMirrorStatus
    public var lexicalProfile: AIAcceptedLearningLexicalProfileStatus
    public var warnings: [String]
}

public struct AIAcceptedLearningHistoryStatus: Codable, Equatable, Sendable {
    public var path: String
    public var exists: Bool
    public var recordCount: Int
    public var historyHash: String?
    public var mtime: String?
}

public struct AIAcceptedLearningSummaryStatus: Codable, Equatable, Sendable {
    public var path: String
    public var exists: Bool
    public var acceptedCount: Int
    public var historyHash: String?
    public var termCount: Int
    public var recentCommitCount: Int
    public var generatedAt: String?
    public var mtime: String?
    public var isCurrentWithHistory: Bool
}

public struct AIAcceptedLearningMirrorStatus: Codable, Equatable, Sendable {
    public var path: String
    public var exists: Bool
    public var mtime: String?
}

public struct AIAcceptedLearningLexicalProfileStatus: Codable, Equatable, Sendable {
    public var jsonPath: String
    public var markdownPath: String
    public var jsonExists: Bool
    public var markdownExists: Bool
    public var containsAcceptedAISummary: Bool
    public var mtime: String?
}

public struct AIAcceptedLearningMaintenance {
    public enum Error: LocalizedError, Equatable {
        case clearRequiresConfirmation

        public var errorDescription: String? {
            switch self {
            case .clearRequiresConfirmation:
                return "clear requires --yes to delete accepted AI learning history"
            }
        }
    }

    public var historyURL: URL
    public var summaryURL: URL
    public var mirrorURL: URL
    public var lexicalJSONURL: URL
    public var lexicalMarkdownURL: URL
    public var fileManager: FileManager

    public init(
        historyURL: URL = AIAcceptedLearningStore.defaultHistoryURL(),
        summaryURL: URL = AIAcceptedLearningStore.defaultSummaryURL(),
        mirrorURL: URL = AIUserDirectory.defaultDirectory().acceptedLearningMirrorURL,
        lexicalJSONURL: URL = LexicalProfileStore.defaultJSONURL(),
        lexicalMarkdownURL: URL = AIUserDirectory.defaultDirectory().lexicalProfileURL,
        fileManager: FileManager = .default
    ) {
        self.historyURL = historyURL
        self.summaryURL = summaryURL
        self.mirrorURL = mirrorURL
        self.lexicalJSONURL = lexicalJSONURL
        self.lexicalMarkdownURL = lexicalMarkdownURL
        self.fileManager = fileManager
    }

    public func status(action: String? = nil) -> AIAcceptedLearningMaintenanceStatus {
        let loaded = loadRecords()
        let records = loaded.records
        let historyHash = records.isEmpty ? nil : AIAcceptedLearningStore.historyHash(records)
        let summary = loadSummary()
        let summaryIsCurrent: Bool
        if records.isEmpty {
            summaryIsCurrent = summary == nil
        } else {
            summaryIsCurrent = summary?.acceptedCount == records.count
                && summary?.historyHash == historyHash
        }

        var warnings = loaded.warnings
        if !records.isEmpty, summary == nil {
            warnings.append("summary_missing")
        } else if !summaryIsCurrent {
            warnings.append("summary_stale")
        }

        return AIAcceptedLearningMaintenanceStatus(
            schemaVersion: 1,
            action: action,
            history: AIAcceptedLearningHistoryStatus(
                path: historyURL.path,
                exists: fileManager.fileExists(atPath: historyURL.path),
                recordCount: records.count,
                historyHash: historyHash,
                mtime: modificationDateString(historyURL)
            ),
            summary: AIAcceptedLearningSummaryStatus(
                path: summaryURL.path,
                exists: fileManager.fileExists(atPath: summaryURL.path),
                acceptedCount: summary?.acceptedCount ?? 0,
                historyHash: summary?.historyHash,
                termCount: summary?.termProfile.count ?? 0,
                recentCommitCount: summary?.recentAcceptedCommits.count ?? 0,
                generatedAt: summary.map { dateString($0.generatedAt) },
                mtime: modificationDateString(summaryURL),
                isCurrentWithHistory: summaryIsCurrent
            ),
            mirror: AIAcceptedLearningMirrorStatus(
                path: mirrorURL.path,
                exists: fileManager.fileExists(atPath: mirrorURL.path),
                mtime: modificationDateString(mirrorURL)
            ),
            lexicalProfile: AIAcceptedLearningLexicalProfileStatus(
                jsonPath: lexicalJSONURL.path,
                markdownPath: lexicalMarkdownURL.path,
                jsonExists: fileManager.fileExists(atPath: lexicalJSONURL.path),
                markdownExists: fileManager.fileExists(atPath: lexicalMarkdownURL.path),
                containsAcceptedAISummary: markdownContainsAcceptedAISummary(),
                mtime: modificationDateString(lexicalMarkdownURL)
            ),
            warnings: warnings
        )
    }

    @discardableResult
    public func rebuild() throws -> AIAcceptedLearningMaintenanceStatus {
        let records = loadRecords().records
        let summary = AIAcceptedLearningStore.buildSummary(records: records, generatedAt: Date())
        try withAcceptedLearningFileLock {
            if let summary {
                try atomicWrite(encode(summary), to: summaryURL)
                try atomicWrite(Data(AIAcceptedLearningStore.renderMarkdown(summary).utf8), to: mirrorURL)
            } else {
                try removeIfExists(summaryURL)
                try removeIfExists(mirrorURL)
            }
        }
        return status(action: "rebuilt")
    }

    @discardableResult
    public func clear(confirm: Bool) throws -> AIAcceptedLearningMaintenanceStatus {
        guard confirm else {
            throw Error.clearRequiresConfirmation
        }
        try withAcceptedLearningFileLock {
            try removeIfExists(historyURL)
            try removeIfExists(summaryURL)
            try removeIfExists(mirrorURL)
        }
        return status(action: "cleared")
    }

    private func loadRecords() -> (records: [AIAcceptedLearningRecord], warnings: [String]) {
        guard let content = try? String(contentsOf: historyURL, encoding: .utf8) else {
            return ([], [])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var records: [AIAcceptedLearningRecord] = []
        var invalidLineCount = 0
        for line in content.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let record = try? decoder.decode(AIAcceptedLearningRecord.self, from: data) else {
                invalidLineCount += 1
                continue
            }
            records.append(record)
        }

        let warnings = invalidLineCount > 0 ? ["invalid_history_lines:\(invalidLineCount)"] : []
        return (records, warnings)
    }

    private func loadSummary() -> AIAcceptedLanguageSummary? {
        guard let data = try? Data(contentsOf: summaryURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AIAcceptedLanguageSummary.self, from: data)
    }

    private func markdownContainsAcceptedAISummary() -> Bool {
        guard let content = try? String(contentsOf: lexicalMarkdownURL, encoding: .utf8) else {
            return false
        }
        return content.contains("accepted-ai-summary:")
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private func removeIfExists(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    private func modificationDateString(_ url: URL) -> String? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date else {
            return nil
        }
        return dateString(date)
    }

    private func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
