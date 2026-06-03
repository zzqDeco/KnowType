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
    public var clearMarkerURL: URL
    public var lockURL: URL
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
        self.clearMarkerURL = acceptedLearningClearMarkerURL(historyURL: historyURL)
            ?? historyURL.deletingLastPathComponent().appendingPathComponent("accepted-ai-learning.clear.json")
        self.lockURL = acceptedLearningLockURL(historyURL: historyURL)
            ?? historyURL.deletingLastPathComponent().appendingPathComponent("accepted-ai-learning.lock")
        self.fileManager = fileManager
    }

    public func status(action: String? = nil) -> AIAcceptedLearningMaintenanceStatus {
        let loaded = loadRecords()
        let records = loaded.records
        let historyHash = records.isEmpty ? nil : AIAcceptedLearningStore.historyHash(records)
        let loadedSummary = loadSummary()
        let summary = loadedSummary.summary
        let summaryIsCurrent: Bool
        if records.isEmpty, !loadedSummary.exists {
            summaryIsCurrent = summary == nil
        } else {
            summaryIsCurrent = summary?.acceptedCount == records.count
                && summary?.historyHash == historyHash
        }

        var warnings = loaded.warnings
        if !records.isEmpty, summary == nil {
            warnings.append("summary_missing")
        } else if loadedSummary.exists, loadedSummary.summary == nil {
            warnings.append("summary_unreadable")
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
        try withAcceptedLearningFileLock(lockURL: lockURL, fileManager: fileManager) {
            let records = loadRecords().records
            let summary = AIAcceptedLearningStore.buildSummary(records: records, generatedAt: Date())
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
        try withAcceptedLearningFileLock(lockURL: lockURL, fileManager: fileManager) {
            let acceptedCommitTexts = acceptedCommitTextVariants(from: loadRecords().records)
            try removeIfExists(historyURL)
            try removeIfExists(summaryURL)
            try removeIfExists(mirrorURL)
            try atomicWrite(clearMarkerPayload(), to: clearMarkerURL)
            try scrubAcceptedAIFromLexicalProfile(acceptedCommitTexts: acceptedCommitTexts)
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

    private func loadSummary() -> (exists: Bool, summary: AIAcceptedLanguageSummary?) {
        let exists = fileManager.fileExists(atPath: summaryURL.path)
        guard let data = try? Data(contentsOf: summaryURL) else {
            return (exists, nil)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (exists, try? decoder.decode(AIAcceptedLanguageSummary.self, from: data))
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

    private func clearMarkerPayload() -> Data {
        let payload: [String: Any] = [
            "schemaVersion": 1,
            "clearedAt": dateString(Date())
        ]
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        return data ?? Data()
    }

    private func scrubAcceptedAIFromLexicalProfile(acceptedCommitTexts: Set<String>) throws {
        guard fileManager.fileExists(atPath: lexicalJSONURL.path),
              let data = try? Data(contentsOf: lexicalJSONURL) else {
            if fileManager.fileExists(atPath: lexicalMarkdownURL.path) {
                try scrubAcceptedAIFromLexicalMarkdownOnly(acceptedCommitTexts: acceptedCommitTexts)
            }
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let profile = try? decoder.decode(PersistentLexicalProfile.self, from: data) else {
            if fileManager.fileExists(atPath: lexicalMarkdownURL.path) {
                try scrubAcceptedAIFromLexicalMarkdownOnly(acceptedCommitTexts: acceptedCommitTexts)
            }
            return
        }

        let hadAcceptedSource = profile.lexicalContext.sourceSummary.contains {
            $0.hasPrefix("accepted-ai")
        } || profile.lexicalContext.terms.contains { $0.source == "accepted-ai" }
        guard hadAcceptedSource else {
            if fileManager.fileExists(atPath: lexicalMarkdownURL.path) {
                try scrubAcceptedAIFromLexicalMarkdownOnly(acceptedCommitTexts: acceptedCommitTexts)
            }
            return
        }

        let scrubbedRecentCommits = profile.lexicalContext.recentCommits.filter {
            !acceptedCommitTexts.contains(normalizedCommitText($0))
        }
        let scrubbedContext = LexicalContextSnapshot(
            terms: profile.lexicalContext.terms.filter { $0.source != "accepted-ai" },
            recentCommits: scrubbedRecentCommits,
            toneProfile: profile.lexicalContext.toneProfile,
            sourceSummary: profile.lexicalContext.sourceSummary.filter { !$0.hasPrefix("accepted-ai") }
        )
        let scrubbedProfile = PersistentLexicalProfile(
            generatedAt: Date(),
            schemaID: profile.schemaID,
            rimeSnapshotPath: profile.rimeSnapshotPath,
            rimeSnapshotModifiedAt: profile.rimeSnapshotModifiedAt,
            lexicalContext: scrubbedContext
        )
        try atomicWrite(encode(scrubbedProfile), to: lexicalJSONURL)
        try atomicWrite(Data(scrubbedContext.markdown.utf8), to: lexicalMarkdownURL)
    }

    private func scrubAcceptedAIFromLexicalMarkdownOnly(
        acceptedCommitTexts: Set<String>
    ) throws {
        guard let content = try? String(contentsOf: lexicalMarkdownURL, encoding: .utf8),
              content.contains("accepted-ai") || !acceptedCommitTexts.isEmpty else {
            return
        }
        var output: [String] = []
        var inRecentCommits = false
        var removedRecentCommit = false
        var recentCommitItemCount = 0
        let lines = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        for line in lines {
            if line.hasPrefix("## ") {
                if inRecentCommits, recentCommitItemCount == 0 {
                    output.append("- No recent committed text yet.")
                    output.append("")
                }
                inRecentCommits = line == "## Recent Commits"
                if inRecentCommits {
                    recentCommitItemCount = 0
                }
                output.append(line)
                continue
            }
            if line.contains("accepted-ai") {
                continue
            }
            if inRecentCommits, line.hasPrefix("- ") {
                let commit = normalizedCommitText(String(line.dropFirst(2)))
                if acceptedCommitTexts.contains(commit) {
                    removedRecentCommit = true
                    continue
                }
                recentCommitItemCount += 1
            }
            output.append(line)
        }
        if inRecentCommits, recentCommitItemCount == 0 {
            output.append("- No recent committed text yet.")
        }
        guard removedRecentCommit || content.contains("accepted-ai") else {
            return
        }
        try atomicWrite(Data((output.joined(separator: "\n") + "\n").utf8), to: lexicalMarkdownURL)
    }

    private func acceptedCommitTextVariants(from records: [AIAcceptedLearningRecord]) -> Set<String> {
        Set(
            records.flatMap { record in
                let clean = normalizedCommitText(record.acceptedText)
                guard !clean.isEmpty else {
                    return [String]()
                }
                if clean.count <= 48 {
                    return [clean]
                }
                return [clean, String(clean.prefix(48)) + "..."]
            }
        )
    }

    private func normalizedCommitText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
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
