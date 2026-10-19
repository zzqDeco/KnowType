import Foundation

public struct AIAcceptedLearningMaintenanceStatus: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var action: String?
    public var history: AIAcceptedLearningHistoryStatus
    public var summary: AIAcceptedLearningSummaryStatus
    public var mirror: AIAcceptedLearningMirrorStatus
    public var feedback: AIAcceptedFeedbackMaintenanceStatus
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

public struct AIAcceptedFeedbackMaintenanceStatus: Codable, Equatable, Sendable {
    public var history: AIAcceptedFeedbackHistoryStatus
    public var summary: AIAcceptedFeedbackSummaryStatus
    public var mirror: AIAcceptedLearningMirrorStatus
}

public struct AIAcceptedFeedbackHistoryStatus: Codable, Equatable, Sendable {
    public var path: String
    public var exists: Bool
    public var recordCount: Int
    public var historyHash: String?
    public var mtime: String?
}

public struct AIAcceptedFeedbackSummaryStatus: Codable, Equatable, Sendable {
    public var path: String
    public var exists: Bool
    public var feedbackCount: Int
    public var strongCount: Int
    public var avoidTermCount: Int
    public var generatedAt: String?
    public var historyHash: String?
    public var mtime: String?
    public var isCurrentWithHistory: Bool
}

public struct AIAcceptedLearningMaintenance {
    public enum Error: LocalizedError, Equatable {
        case clearRequiresConfirmation
        case undecodableHistoryRows

        public var errorDescription: String? {
            switch self {
            case .clearRequiresConfirmation:
                return "clear requires --yes to delete accepted AI learning history"
            case .undecodableHistoryRows:
                return "rebuild refused: accepted AI learning history contains undecodable rows"
            }
        }
    }

    private struct ClearMarker: Codable {
        var schemaVersion: Int = 1
        var clearedAt: String
        var pendingEvictedCommitEntries: [String]?
    }

    public var historyURL: URL
    public var summaryURL: URL
    public var mirrorURL: URL
    public var feedbackHistoryURL: URL
    public var feedbackSummaryURL: URL
    public var feedbackMirrorURL: URL
    public var lexicalJSONURL: URL
    public var lexicalMarkdownURL: URL
    public var clearMarkerURL: URL
    public var evictedCommitsURL: URL
    public var feedbackClearMarkerURL: URL
    public var lockURL: URL
    public var maxRecordCount: Int {
        didSet {
            if maxRecordCount < 1 {
                maxRecordCount = 1
            }
        }
    }
    public var fileManager: FileManager

    public init(
        historyURL: URL = AIAcceptedLearningStore.defaultHistoryURL(),
        summaryURL: URL = AIAcceptedLearningStore.defaultSummaryURL(),
        mirrorURL: URL = AIUserDirectory.defaultDirectory().acceptedLearningMirrorURL,
        feedbackHistoryURL: URL = AIAcceptedFeedbackStore.defaultHistoryURL(),
        feedbackSummaryURL: URL = AIAcceptedFeedbackStore.defaultSummaryURL(),
        feedbackMirrorURL: URL = AIUserDirectory.defaultDirectory().acceptedFeedbackMirrorURL,
        lexicalJSONURL: URL = LexicalProfileStore.defaultJSONURL(),
        lexicalMarkdownURL: URL = AIUserDirectory.defaultDirectory().lexicalProfileURL,
        maxRecordCount: Int = AIAcceptedLearningStore.defaultMaxRecordCount,
        fileManager: FileManager = .default
    ) {
        self.historyURL = historyURL
        self.summaryURL = summaryURL
        self.mirrorURL = mirrorURL
        self.feedbackHistoryURL = feedbackHistoryURL
        self.feedbackSummaryURL = feedbackSummaryURL
        self.feedbackMirrorURL = feedbackMirrorURL
        self.lexicalJSONURL = lexicalJSONURL
        self.lexicalMarkdownURL = lexicalMarkdownURL
        self.clearMarkerURL = acceptedLearningClearMarkerURL(historyURL: historyURL)
            ?? historyURL.deletingLastPathComponent().appendingPathComponent("accepted-ai-learning.clear.json")
        self.evictedCommitsURL = acceptedLearningEvictedCommitsURL(historyURL: historyURL)
            ?? historyURL.deletingLastPathComponent().appendingPathComponent("accepted-ai-learning.evicted-commits.json")
        self.feedbackClearMarkerURL = acceptedFeedbackClearMarkerURL(historyURL: feedbackHistoryURL)
            ?? feedbackHistoryURL.deletingLastPathComponent().appendingPathComponent("accepted-ai-feedback.clear.json")
        self.lockURL = acceptedLearningLockURL(historyURL: historyURL)
            ?? historyURL.deletingLastPathComponent().appendingPathComponent("accepted-ai-learning.lock")
        self.maxRecordCount = max(1, maxRecordCount)
        self.fileManager = fileManager
    }

    public func status(action: String? = nil) -> AIAcceptedLearningMaintenanceStatus {
        let effectiveMaxRecordCount = max(1, maxRecordCount)
        let loaded = loadRecords()
        let records = loaded.records
        let historyHash = records.isEmpty ? nil : AIAcceptedLearningStore.historyHash(records)
        let loadedSummary = loadSummary()
        let summary = loadedSummary.summary
        let loadedFeedback = loadFeedbackRecords()
        let feedbackRecords = loadedFeedback.records
        let feedbackHistoryHash = feedbackRecords.isEmpty ? nil : AIAcceptedFeedbackStore.historyHash(feedbackRecords)
        let loadedFeedbackSummary = loadFeedbackSummary()
        let feedbackSummary = loadedFeedbackSummary.summary
        let summaryIsCurrent: Bool
        if records.isEmpty, !loadedSummary.exists {
            summaryIsCurrent = summary == nil
        } else {
            summaryIsCurrent = records.count <= effectiveMaxRecordCount
                && summary?.acceptedCount == records.count
                && summary?.historyHash == historyHash
        }

        var warnings = loaded.warnings + loadedFeedback.warnings
        if !records.isEmpty, summary == nil {
            warnings.append("summary_missing")
        } else if loadedSummary.exists, loadedSummary.summary == nil {
            warnings.append("summary_unreadable")
        } else if !summaryIsCurrent {
            warnings.append("summary_stale")
        }
        let feedbackSummaryIsCurrent: Bool
        if feedbackRecords.isEmpty, !loadedFeedbackSummary.exists {
            feedbackSummaryIsCurrent = feedbackSummary == nil
        } else {
            feedbackSummaryIsCurrent = feedbackSummary?.feedbackCount == feedbackRecords.count
                && feedbackSummary?.historyHash == feedbackHistoryHash
        }
        if !feedbackRecords.isEmpty, feedbackSummary == nil {
            warnings.append("feedback_summary_missing")
        } else if loadedFeedbackSummary.exists, loadedFeedbackSummary.summary == nil {
            warnings.append("feedback_summary_unreadable")
        } else if !feedbackSummaryIsCurrent {
            warnings.append("feedback_summary_stale")
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
            feedback: AIAcceptedFeedbackMaintenanceStatus(
                history: AIAcceptedFeedbackHistoryStatus(
                    path: feedbackHistoryURL.path,
                    exists: fileManager.fileExists(atPath: feedbackHistoryURL.path),
                    recordCount: feedbackRecords.count,
                    historyHash: feedbackHistoryHash,
                    mtime: modificationDateString(feedbackHistoryURL)
                ),
                summary: AIAcceptedFeedbackSummaryStatus(
                    path: feedbackSummaryURL.path,
                    exists: fileManager.fileExists(atPath: feedbackSummaryURL.path),
                    feedbackCount: feedbackSummary?.feedbackCount ?? 0,
                    strongCount: feedbackSummary?.strongCount ?? 0,
                    avoidTermCount: feedbackSummary?.avoidTerms.count ?? 0,
                    generatedAt: feedbackSummary.map { dateString($0.generatedAt) },
                    historyHash: feedbackSummary?.historyHash,
                    mtime: modificationDateString(feedbackSummaryURL),
                    isCurrentWithHistory: feedbackSummaryIsCurrent
                ),
                mirror: AIAcceptedLearningMirrorStatus(
                    path: feedbackMirrorURL.path,
                    exists: fileManager.fileExists(atPath: feedbackMirrorURL.path),
                    mtime: modificationDateString(feedbackMirrorURL)
                )
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
        let effectiveMaxRecordCount = max(1, maxRecordCount)
        try withAcceptedLearningFileLock(lockURL: lockURL, fileManager: fileManager) {
            let loaded = try loadRecordsOrThrow()
            guard loaded.warnings.isEmpty else {
                throw Error.undecodableHistoryRows
            }
            let loadedRecords = loaded.records
            let records: [AIAcceptedLearningRecord]
            if loadedRecords.count > effectiveMaxRecordCount {
                let overflowCount = loadedRecords.count - effectiveMaxRecordCount
                try recordAcceptedLearningEvictedCommits(
                    Array(loadedRecords.prefix(overflowCount)),
                    historyURL: historyURL,
                    evictedCommitsURL: evictedCommitsURL,
                    fileManager: fileManager
                )
                records = Array(loadedRecords.suffix(effectiveMaxRecordCount))
                try writeHistoryRecords(records)
            } else {
                records = loadedRecords
            }
            let summary = AIAcceptedLearningStore.buildSummary(records: records, generatedAt: Date())
            if let summary {
                try atomicWrite(encode(summary), to: summaryURL)
                try atomicWrite(
                    Data(AIAcceptedLearningStore.renderMarkdown(summary, maxRecordCount: effectiveMaxRecordCount).utf8),
                    to: mirrorURL
                )
            } else {
                try removeIfExists(summaryURL)
                try removeIfExists(mirrorURL)
            }
            try withAcceptedFeedbackFileLock(
                lockURL: acceptedFeedbackLockURL(historyURL: feedbackHistoryURL),
                fileManager: fileManager
            ) {
                let feedbackRecords = loadFeedbackRecords().records
                let feedbackSummary = AIAcceptedFeedbackStore.buildSummary(records: feedbackRecords, generatedAt: Date())
                if let feedbackSummary {
                    try atomicWrite(encode(feedbackSummary), to: feedbackSummaryURL)
                    try atomicWrite(Data(AIAcceptedFeedbackStore.renderMarkdown(feedbackSummary).utf8), to: feedbackMirrorURL)
                } else {
                    try removeIfExists(feedbackSummaryURL)
                    try removeIfExists(feedbackMirrorURL)
                }
            }
        }
        synchronizePeerAcceptedLearningStores(for: historyURL)
        return status(action: "rebuilt")
    }

    @discardableResult
    public func clear(confirm: Bool) throws -> AIAcceptedLearningMaintenanceStatus {
        guard confirm else {
            throw Error.clearRequiresConfirmation
        }
        var didWriteClearMarkers = false
        defer {
            if didWriteClearMarkers {
                synchronizePeerAcceptedLearningStores(for: historyURL)
            }
        }
        try withAcceptedLearningFileLock(lockURL: lockURL, fileManager: fileManager) {
            let currentRecords = try loadRecordsOrThrow().records
            let acceptedCommitTexts = acceptedCommitTextVariants(from: currentRecords)
            let preClearEvictedEntries = Set(
                try loadAcceptedLearningEvictedCommitListOrThrow(
                    from: evictedCommitsURL,
                    fileManager: fileManager
                )
            )
            let pendingClearEntries = try pendingClearEvictedCommitEntries()
            let currentRecordDigests = acceptedLearningCommitDigestVariants(from: currentRecords)
            if !currentRecords.isEmpty {
                try recordAcceptedLearningEvictedCommits(
                    currentRecords,
                    historyURL: historyURL,
                    evictedCommitsURL: evictedCommitsURL,
                    maxEntries: preClearEvictedEntries.count + currentRecordDigests.count,
                    fileManager: fileManager
                )
            }
            let evictedCommitEntries = pendingClearEntries
                .union(preClearEvictedEntries)
                .union(currentRecordDigests)
            // Pin scrub inputs separately from the ordinary, rotating eviction ledger.
            try atomicWrite(clearMarkerPayload(pendingEvictedCommitEntries: evictedCommitEntries), to: clearMarkerURL)
            didWriteClearMarkers = true
            try removeIfExists(historyURL)
            try removeIfExists(summaryURL)
            try removeIfExists(mirrorURL)
            try withAcceptedFeedbackFileLock(
                lockURL: acceptedFeedbackLockURL(historyURL: feedbackHistoryURL),
                fileManager: fileManager
            ) {
                try removeIfExists(feedbackHistoryURL)
                try removeIfExists(feedbackSummaryURL)
                try removeIfExists(feedbackMirrorURL)
                try atomicWrite(clearMarkerPayload(), to: feedbackClearMarkerURL)
            }
            try scrubAcceptedAIFromLexicalProfile(
                acceptedCommitTexts: acceptedCommitTexts,
                evictedCommitEntries: evictedCommitEntries
            )
            try removeIfExists(evictedCommitsURL)
            try atomicWrite(clearMarkerPayload(), to: clearMarkerURL)
        }
        return status(action: "cleared")
    }

    private func loadRecordsOrThrow() throws -> (records: [AIAcceptedLearningRecord], warnings: [String]) {
        let content: String
        do {
            content = try String(contentsOf: historyURL, encoding: .utf8)
        } catch {
            if isAcceptedLearningNoSuchFileError(error) || !fileManager.fileExists(atPath: historyURL.path) {
                return ([], [])
            }
            throw error
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var records: [AIAcceptedLearningRecord] = []
        var invalidLineCount = 0
        for line in content.split(whereSeparator: \.isNewline) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                continue
            }
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

    private func loadRecords() -> (records: [AIAcceptedLearningRecord], warnings: [String]) {
        (try? loadRecordsOrThrow()) ?? ([], [])
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

    private func loadFeedbackRecords() -> (records: [AIAcceptedFeedbackRecord], warnings: [String]) {
        guard let content = try? String(contentsOf: feedbackHistoryURL, encoding: .utf8) else {
            return ([], [])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var records: [AIAcceptedFeedbackRecord] = []
        var invalidLineCount = 0
        for line in content.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let record = try? decoder.decode(AIAcceptedFeedbackRecord.self, from: data) else {
                invalidLineCount += 1
                continue
            }
            records.append(record)
        }

        let warnings = invalidLineCount > 0 ? ["invalid_feedback_history_lines:\(invalidLineCount)"] : []
        return (records, warnings)
    }

    private func loadFeedbackSummary() -> (exists: Bool, summary: AIAcceptedFeedbackSummary?) {
        let exists = fileManager.fileExists(atPath: feedbackSummaryURL.path)
        guard let data = try? Data(contentsOf: feedbackSummaryURL) else {
            return (exists, nil)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (exists, try? decoder.decode(AIAcceptedFeedbackSummary.self, from: data))
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

    private func writeHistoryRecords(_ records: [AIAcceptedLearningRecord]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var buffer = Data()
        for record in records {
            let data = try encoder.encode(record)
            buffer.append(data)
            buffer.append(0x0A)
        }
        try atomicWrite(buffer, to: historyURL)
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

    private func pendingClearEvictedCommitEntries() throws -> Set<String> {
        let data: Data
        do {
            data = try Data(contentsOf: clearMarkerURL)
        } catch {
            if isAcceptedLearningNoSuchFileError(error) || !fileManager.fileExists(atPath: clearMarkerURL.path) {
                return []
            }
            throw error
        }
        let marker = try JSONDecoder().decode(ClearMarker.self, from: data)
        return Set(marker.pendingEvictedCommitEntries ?? [])
    }

    private func clearMarkerPayload(pendingEvictedCommitEntries: Set<String> = []) throws -> Data {
        try encode(ClearMarker(
            clearedAt: dateString(Date()),
            pendingEvictedCommitEntries: pendingEvictedCommitEntries.isEmpty
                ? nil
                : pendingEvictedCommitEntries.sorted()
        ))
    }

    private func scrubAcceptedAIFromLexicalProfile(
        acceptedCommitTexts: Set<String>,
        evictedCommitEntries: Set<String>
    ) throws {
        guard fileManager.fileExists(atPath: lexicalJSONURL.path) else {
            if fileManager.fileExists(atPath: lexicalMarkdownURL.path) {
                try scrubAcceptedAIFromLexicalMarkdownOnly(
                    acceptedCommitTexts: acceptedCommitTexts,
                    evictedCommitEntries: evictedCommitEntries
                )
            }
            return
        }
        let data: Data
        do {
            data = try Data(contentsOf: lexicalJSONURL)
        } catch {
            if fileManager.fileExists(atPath: lexicalMarkdownURL.path) {
                try? scrubAcceptedAIFromLexicalMarkdownOnly(
                    acceptedCommitTexts: acceptedCommitTexts,
                    evictedCommitEntries: evictedCommitEntries
                )
            }
            throw error
        }
        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           jsonObject.isEmpty {
            if fileManager.fileExists(atPath: lexicalMarkdownURL.path) {
                try scrubAcceptedAIFromLexicalMarkdownOnly(
                    acceptedCommitTexts: acceptedCommitTexts,
                    evictedCommitEntries: evictedCommitEntries
                )
            }
            return
        }
        let profile: PersistentLexicalProfile
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            profile = try decoder.decode(PersistentLexicalProfile.self, from: data)
        } catch {
            if fileManager.fileExists(atPath: lexicalMarkdownURL.path) {
                try? scrubAcceptedAIFromLexicalMarkdownOnly(
                    acceptedCommitTexts: acceptedCommitTexts,
                    evictedCommitEntries: evictedCommitEntries
                )
            }
            throw error
        }

        let hadAcceptedSource = profile.lexicalContext.sourceSummary.contains {
            $0.hasPrefix("accepted-ai")
        } || profile.lexicalContext.terms.contains { $0.source == "accepted-ai" }
        let scrubbedRecentCommits = profile.lexicalContext.recentCommits.filter {
            !matchesAcceptedCommit(
                $0,
                acceptedCommitTexts: acceptedCommitTexts,
                evictedCommitEntries: evictedCommitEntries
            )
        }
        let hadMatchingRecentCommit = scrubbedRecentCommits.count != profile.lexicalContext.recentCommits.count
        guard hadAcceptedSource || hadMatchingRecentCommit else {
            if fileManager.fileExists(atPath: lexicalMarkdownURL.path) {
                try scrubAcceptedAIFromLexicalMarkdownOnly(
                    acceptedCommitTexts: acceptedCommitTexts,
                    evictedCommitEntries: evictedCommitEntries
                )
            }
            return
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
        acceptedCommitTexts: Set<String>,
        evictedCommitEntries: Set<String>
    ) throws {
        guard fileManager.fileExists(atPath: lexicalMarkdownURL.path) else {
            return
        }
        let content: String
        do {
            content = try String(contentsOf: lexicalMarkdownURL, encoding: .utf8)
        } catch {
            if isAcceptedLearningNoSuchFileError(error) || !fileManager.fileExists(atPath: lexicalMarkdownURL.path) {
                return
            }
            throw error
        }
        guard content.contains("accepted-ai") || !acceptedCommitTexts.isEmpty || !evictedCommitEntries.isEmpty else {
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
                let commit = String(line.dropFirst(2))
                if matchesAcceptedCommit(
                    commit,
                    acceptedCommitTexts: acceptedCommitTexts,
                    evictedCommitEntries: evictedCommitEntries
                ) {
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

    private func matchesAcceptedCommit(
        _ text: String,
        acceptedCommitTexts: Set<String>,
        evictedCommitEntries: Set<String>
    ) -> Bool {
        let normalized = normalizedCommitText(text)
        guard !normalized.isEmpty else {
            return false
        }
        if acceptedCommitTexts.contains(normalized) || evictedCommitEntries.contains(normalized) {
            return true
        }
        return evictedCommitEntries.contains(acceptedLearningCommitTextDigest(normalized))
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
