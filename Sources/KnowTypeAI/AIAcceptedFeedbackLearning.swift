import Darwin
import CryptoKit
import Foundation
import KnowTypeCore

let acceptedFeedbackFileLock = NSLock()

public enum AIAcceptedFeedbackStrength: String, Codable, Sendable, Equatable {
    case weak
    case medium
    case strong
}

public struct AIAcceptedFeedbackTextRange: Codable, Sendable, Equatable, Hashable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

public struct AIAcceptedFeedbackRecord: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var observedAt: Date
    public var acceptID: UUID
    public var schemaID: String
    public var appBundleID: String?
    public var provider: String
    public var contextVersion: String
    public var acceptedTextHash: String
    public var deletedRanges: [AIAcceptedFeedbackTextRange]
    public var deletedTexts: [String]
    public var deletedVisibleCharacterCount: Int
    public var deletedRatio: Double
    public var strength: AIAcceptedFeedbackStrength
    public var replacementText: String?
    public var reason: String

    public init(
        schemaVersion: Int = 1,
        observedAt: Date = Date(),
        acceptID: UUID,
        schemaID: String,
        appBundleID: String? = nil,
        provider: String,
        contextVersion: String,
        acceptedTextHash: String,
        deletedRanges: [AIAcceptedFeedbackTextRange],
        deletedTexts: [String],
        deletedVisibleCharacterCount: Int,
        deletedRatio: Double,
        strength: AIAcceptedFeedbackStrength,
        replacementText: String? = nil,
        reason: String
    ) {
        self.schemaVersion = schemaVersion
        self.observedAt = observedAt
        self.acceptID = acceptID
        self.schemaID = schemaID
        self.appBundleID = appBundleID
        self.provider = provider
        self.contextVersion = contextVersion
        self.acceptedTextHash = acceptedTextHash
        self.deletedRanges = deletedRanges
        self.deletedTexts = deletedTexts
        self.deletedVisibleCharacterCount = deletedVisibleCharacterCount
        self.deletedRatio = max(0, min(1, deletedRatio))
        self.strength = strength
        self.replacementText = replacementText
        self.reason = reason
    }
}

public struct AIAcceptedFeedbackSummary: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var historyHash: String
    public var feedbackCount: Int
    public var strongCount: Int
    public var avoidTerms: [String]
    public var styleAdjustments: [String]
    public var replacementPatterns: [String]
    public var sourceSummary: [String]

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        historyHash: String,
        feedbackCount: Int,
        strongCount: Int,
        avoidTerms: [String],
        styleAdjustments: [String],
        replacementPatterns: [String],
        sourceSummary: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.historyHash = historyHash
        self.feedbackCount = feedbackCount
        self.strongCount = strongCount
        self.avoidTerms = avoidTerms
        self.styleAdjustments = styleAdjustments
        self.replacementPatterns = replacementPatterns
        self.sourceSummary = sourceSummary
    }
}

public struct AIAcceptedFeedbackContextSnapshot: Codable, Sendable, Equatable {
    public var summary: AIAcceptedFeedbackSummary
    public var markdown: String
    public var sha256: String

    public init(summary: AIAcceptedFeedbackSummary) {
        self.summary = summary
        self.markdown = AIAcceptedFeedbackStore.renderContextMarkdown(summary)
        self.sha256 = Self.hash(markdown)
    }

    private static func hash(_ content: String) -> String {
        SHA256.hash(data: Data(content.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public protocol AIAcceptedFeedbackRecording: Sendable {
    func recordAcceptedFeedback(_ record: AIAcceptedFeedbackRecord) async
}

public protocol AIAcceptedFeedbackSnapshotProviding: Sendable {
    func snapshot() -> AIAcceptedFeedbackContextSnapshot?
    func snapshot(schemaID: String?) -> AIAcceptedFeedbackContextSnapshot?
}

public extension AIAcceptedFeedbackSnapshotProviding {
    func snapshot(schemaID _: String?) -> AIAcceptedFeedbackContextSnapshot? {
        snapshot()
    }
}

public final class AIAcceptedFeedbackStore:
    AIAcceptedFeedbackRecording,
    AIAcceptedFeedbackSnapshotProviding,
    @unchecked Sendable
{
    private let historyURL: URL?
    private let summaryURL: URL?
    private let mirrorURL: URL?
    private let fileManager: FileManager
    private let diagnosticSink: any AIRecommendationDiagnosticSink
    private let summaryDelayNanoseconds: UInt64
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()
    private var records: [AIAcceptedFeedbackRecord]
    private var summary: AIAcceptedFeedbackSummary?
    private var schemaSummaries: [String: AIAcceptedFeedbackSummary]
    private var summaryTask: Task<Void, Never>?
    private var lastClearMarkerModifiedAt: Date?

    public init(
        historyURL: URL? = AIAcceptedFeedbackStore.defaultHistoryURL(),
        summaryURL: URL? = AIAcceptedFeedbackStore.defaultSummaryURL(),
        mirrorURL: URL? = AIUserDirectory.defaultDirectory().acceptedFeedbackMirrorURL,
        fileManager: FileManager = .default,
        diagnosticSink: any AIRecommendationDiagnosticSink = NoopAIRecommendationDiagnosticSink(),
        summaryDelayNanoseconds: UInt64 = 1_000_000_000
    ) {
        let configuredEncoder = JSONEncoder()
        configuredEncoder.dateEncodingStrategy = .iso8601
        let configuredDecoder = JSONDecoder()
        configuredDecoder.dateDecodingStrategy = .iso8601
        let loadedRecords = Self.loadRecords(from: historyURL, decoder: configuredDecoder)
        let loadedSummary = Self.loadSummary(from: summaryURL, decoder: configuredDecoder)
        let rebuiltSummary = Self.buildSummary(records: loadedRecords, generatedAt: Date())
        let summaryMatches = Self.summary(loadedSummary, matches: loadedRecords)
        self.historyURL = historyURL
        self.summaryURL = summaryURL
        self.mirrorURL = mirrorURL
        self.fileManager = fileManager
        self.diagnosticSink = diagnosticSink
        self.summaryDelayNanoseconds = summaryDelayNanoseconds
        self.encoder = configuredEncoder
        self.decoder = configuredDecoder
        self.records = loadedRecords
        self.summary = summaryMatches ? loadedSummary : rebuiltSummary
        self.schemaSummaries = Self.buildSchemaSummaries(records: loadedRecords, generatedAt: Date())
        self.lastClearMarkerModifiedAt = Self.fileModificationDate(
            acceptedFeedbackClearMarkerURL(historyURL: historyURL),
            fileManager: fileManager
        )
        if !summaryMatches {
            do {
                try withAcceptedFeedbackFileLock(
                    lockURL: acceptedFeedbackLockURL(historyURL: historyURL),
                    fileManager: fileManager
                ) {
                    try persistSummary(rebuiltSummary)
                }
            } catch {
                diagnosticSink.record(
                    AIRecommendationDiagnosticEvent(
                        stage: .lexicalProfileFallback,
                        reason: "accepted_feedback_summary_repair_failed:\(String(describing: type(of: error)))"
                    )
                )
            }
        }
    }

    public static func inMemory(
        diagnosticSink: any AIRecommendationDiagnosticSink = NoopAIRecommendationDiagnosticSink()
    ) -> AIAcceptedFeedbackStore {
        AIAcceptedFeedbackStore(
            historyURL: nil,
            summaryURL: nil,
            mirrorURL: nil,
            diagnosticSink: diagnosticSink,
            summaryDelayNanoseconds: 0
        )
    }

    public static func defaultHistoryURL(fileManager: FileManager = .default) -> URL {
        defaultApplicationSupportAIDirectory(fileManager: fileManager)
            .appendingPathComponent("accepted-ai-feedback.jsonl", isDirectory: false)
    }

    public static func defaultSummaryURL(fileManager: FileManager = .default) -> URL {
        defaultApplicationSupportAIDirectory(fileManager: fileManager)
            .appendingPathComponent("accepted-ai-feedback-summary.json", isDirectory: false)
    }

    public func recordAcceptedFeedback(_ record: AIAcceptedFeedbackRecord) async {
        let protectedValues = record.deletedTexts + [record.replacementText].compactMap { $0 }
        guard !protectedValues.contains(where: TextProtection.containsSecretLikeContent) else {
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .acceptedFeedbackSkippedSecret,
                    rawLength: record.deletedVisibleCharacterCount,
                    reason: "secret_like_text"
                )
            )
            return
        }
        do {
            try append(record)
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .acceptedFeedbackRecorded,
                    rawLength: record.deletedVisibleCharacterCount,
                    candidateCount: record.deletedRanges.count,
                    reason: "accept_id=\(record.acceptID.uuidString.prefix(8)) strength=\(record.strength.rawValue)"
                )
            )
        } catch {
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .lexicalProfileFallback,
                    reason: "accepted_feedback_write_failed:\(String(describing: type(of: error)))"
                )
            )
        }
    }

    public func snapshot() -> AIAcceptedFeedbackContextSnapshot? {
        syncRecordsAfterExternalClear()
        lock.lock()
        let current = summary
        lock.unlock()
        return current.map(AIAcceptedFeedbackContextSnapshot.init(summary:))
    }

    public func snapshot(schemaID: String?) -> AIAcceptedFeedbackContextSnapshot? {
        guard let schemaID else {
            return snapshot()
        }
        syncRecordsAfterExternalClear()
        lock.lock()
        let current = schemaSummaries[schemaID]
        lock.unlock()
        return current.map(AIAcceptedFeedbackContextSnapshot.init(summary:))
    }

    public func allRecords() -> [AIAcceptedFeedbackRecord] {
        syncRecordsAfterExternalClear()
        lock.lock()
        let current = records
        lock.unlock()
        return current
    }

    private func append(_ record: AIAcceptedFeedbackRecord) throws {
        try withAcceptedFeedbackFileLock(lockURL: acceptedFeedbackLockURL(historyURL: historyURL), fileManager: fileManager) {
            syncRecordsAfterExternalClearLocked()
            if let historyURL {
                try fileManager.createDirectory(
                    at: historyURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = try encoder.encode(record)
                var line = data
                line.append(0x0A)
                if fileManager.fileExists(atPath: historyURL.path) {
                    let handle = try FileHandle(forWritingTo: historyURL)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: line)
                } else {
                    try line.write(to: historyURL, options: .atomic)
                }
            }
            lock.lock()
            records.append(record)
            lock.unlock()
        }
        scheduleSummaryRebuild()
    }

    private func scheduleSummaryRebuild() {
        lock.lock()
        summaryTask?.cancel()
        lock.unlock()
        if summaryDelayNanoseconds == 0 {
            rebuildSummary()
            return
        }
        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self else {
                return
            }
            do {
                try await Task.sleep(nanoseconds: self.summaryDelayNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            self.rebuildSummary()
        }
        lock.lock()
        summaryTask = task
        lock.unlock()
    }

    private func rebuildSummary() {
        do {
            try withAcceptedFeedbackFileLock(lockURL: acceptedFeedbackLockURL(historyURL: historyURL), fileManager: fileManager) {
                syncRecordsAfterExternalClearLocked()
                lock.lock()
                let currentRecords = records
                lock.unlock()
                let generatedAt = Date()
                let nextSummary = Self.buildSummary(records: currentRecords, generatedAt: generatedAt)
                let nextSchemaSummaries = Self.buildSchemaSummaries(records: currentRecords, generatedAt: generatedAt)
                lock.lock()
                summary = nextSummary
                schemaSummaries = nextSchemaSummaries
                lock.unlock()
                try persistSummary(nextSummary)
            }
        } catch {
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .lexicalProfileFallback,
                    reason: "accepted_feedback_summary_write_failed:\(String(describing: type(of: error)))"
                )
            )
        }
    }

    private func syncRecordsAfterExternalClear() {
        do {
            try withAcceptedFeedbackFileLock(
                lockURL: acceptedFeedbackLockURL(historyURL: historyURL),
                fileManager: fileManager
            ) {
                syncRecordsAfterExternalClearLocked()
            }
        } catch {
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .lexicalProfileFallback,
                    reason: "accepted_feedback_clear_sync_failed:\(String(describing: type(of: error)))"
                )
            )
        }
    }

    private func syncRecordsAfterExternalClearLocked() {
        guard let markerURL = acceptedFeedbackClearMarkerURL(historyURL: historyURL) else {
            return
        }
        let markerModifiedAt = Self.fileModificationDate(markerURL, fileManager: fileManager)
        guard let markerModifiedAt else {
            return
        }
        lock.lock()
        let shouldReload = lastClearMarkerModifiedAt == nil || markerModifiedAt > (lastClearMarkerModifiedAt ?? .distantPast)
        lock.unlock()
        guard shouldReload else {
            return
        }
        let reloadedRecords = Self.loadRecords(from: historyURL, decoder: decoder)
        let generatedAt = Date()
        let reloadedSummary = Self.buildSummary(records: reloadedRecords, generatedAt: generatedAt)
        let reloadedSchemaSummaries = Self.buildSchemaSummaries(records: reloadedRecords, generatedAt: generatedAt)
        lock.lock()
        records = reloadedRecords
        summary = reloadedSummary
        schemaSummaries = reloadedSchemaSummaries
        lastClearMarkerModifiedAt = markerModifiedAt
        summaryTask?.cancel()
        summaryTask = nil
        lock.unlock()
    }

    public static func buildSummary(
        records: [AIAcceptedFeedbackRecord],
        generatedAt: Date
    ) -> AIAcceptedFeedbackSummary? {
        guard !records.isEmpty else {
            return nil
        }
        let promotedRecords = records.filter { $0.strength == .medium || $0.strength == .strong }
        let strongCount = records.filter { $0.strength == .strong }.count
        var avoidScores: [String: Double] = [:]
        for record in promotedRecords {
            for text in record.deletedTexts {
                for term in extractedAvoidTerms(from: text) {
                    avoidScores[term, default: 0] += record.strength == .strong ? 1.0 : 0.55
                }
            }
        }
        let avoidTerms = avoidScores
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(24)
            .map(\.key)

        var adjustments: [String] = []
        let longDeletionCount = promotedRecords.filter { $0.deletedRatio >= 0.35 }.count
        if longDeletionCount > 0 {
            adjustments.append("Prefer shorter AI continuations when context is ambiguous.")
        }
        let fullDeletionCount = promotedRecords.filter { $0.deletedRatio >= 0.8 }.count
        if fullDeletionCount > 0 {
            adjustments.append("Avoid confidently completing with phrases the user tends to delete soon after accepting.")
        }
        if promotedRecords.contains(where: { $0.deletedTexts.contains { $0.contains("。") || $0.contains(".") } }) {
            adjustments.append("Keep sentence endings lightweight; avoid adding unnecessary final clauses.")
        }

        let replacementPatterns = promotedRecords
            .compactMap { record -> String? in
                guard let replacement = boundedText(record.replacementText),
                      let deleted = record.deletedTexts.first.flatMap(boundedText) else {
                    return nil
                }
                return "\(deleted) -> \(replacement)"
            }
            .prefix(8)
            .map { $0 }

        let historyHash = historyHash(records)
        return AIAcceptedFeedbackSummary(
            generatedAt: generatedAt,
            historyHash: historyHash,
            feedbackCount: records.count,
            strongCount: strongCount,
            avoidTerms: Array(avoidTerms),
            styleAdjustments: Array(adjustments.prefix(8)),
            replacementPatterns: Array(replacementPatterns),
            sourceSummary: [
                "accepted-ai-feedback-summary: records=\(records.count) strong=\(strongCount) history=\(String(historyHash.prefix(8)))"
            ]
        )
    }

    public static func historyHash(_ records: [AIAcceptedFeedbackRecord]) -> String {
        let joined = records.map { record in
            [
                record.acceptID.uuidString,
                record.acceptedTextHash,
                record.deletedRanges.map { "\($0.location):\($0.length)" }.joined(separator: ","),
                record.deletedTexts.joined(separator: "\u{1F}"),
                record.replacementText ?? "",
                String(format: "%.4f", record.deletedRatio),
                record.strength.rawValue
            ].joined(separator: "|")
        }.joined(separator: "\n")
        return SHA256.hash(data: Data(joined.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public static func renderMarkdown(_ summary: AIAcceptedFeedbackSummary) -> String {
        var lines = [
            "# KnowType Accepted AI Feedback",
            "",
            "This is a local bounded summary of verified edits made immediately after accepted AI recommendations. Full feedback history stays local.",
            "",
            "## Stats",
            "- Feedback count: \(summary.feedbackCount)",
            "- Strong count: \(summary.strongCount)",
            "- History hash: \(summary.historyHash)",
            "- Generated at: \(ISO8601DateFormatter().string(from: summary.generatedAt))",
            "",
            "## Avoid Terms"
        ]
        if summary.avoidTerms.isEmpty {
            lines.append("- No verified avoid terms yet.")
        } else {
            summary.avoidTerms.forEach { lines.append("- \($0)") }
        }
        lines.append("")
        lines.append("## Style Adjustments")
        if summary.styleAdjustments.isEmpty {
            lines.append("- No verified style adjustments yet.")
        } else {
            summary.styleAdjustments.forEach { lines.append("- \($0)") }
        }
        lines.append("")
        lines.append("## Replacement Patterns")
        if summary.replacementPatterns.isEmpty {
            lines.append("- No verified replacement patterns yet.")
        } else {
            summary.replacementPatterns.forEach { lines.append("- \($0)") }
        }
        lines.append("")
        lines.append("## Sources")
        summary.sourceSummary.forEach { lines.append("- \($0)") }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func renderContextMarkdown(_ summary: AIAcceptedFeedbackSummary) -> String {
        var lines = [
            "# KnowType AI Feedback",
            "",
            "This is a bounded local summary of verified post-accept edits. Treat it as a soft style signal only.",
            "",
            "## Avoid Terms"
        ]
        if summary.avoidTerms.isEmpty {
            lines.append("- none")
        } else {
            summary.avoidTerms.prefix(16).forEach { lines.append("- \($0)") }
        }
        lines.append("")
        lines.append("## Style Adjustments")
        if summary.styleAdjustments.isEmpty {
            lines.append("- none")
        } else {
            summary.styleAdjustments.prefix(6).forEach { lines.append("- \($0)") }
        }
        lines.append("")
        lines.append("## Replacement Patterns")
        if summary.replacementPatterns.isEmpty {
            lines.append("- none")
        } else {
            summary.replacementPatterns.prefix(6).forEach { lines.append("- \($0)") }
        }
        lines.append("")
        lines.append("## Sources")
        summary.sourceSummary.forEach { lines.append("- \($0)") }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func buildSchemaSummaries(
        records: [AIAcceptedFeedbackRecord],
        generatedAt: Date
    ) -> [String: AIAcceptedFeedbackSummary] {
        Dictionary(
            uniqueKeysWithValues: Dictionary(grouping: records, by: \.schemaID).compactMap { schemaID, schemaRecords in
                guard let summary = buildSummary(records: schemaRecords, generatedAt: generatedAt) else {
                    return nil
                }
                return (schemaID, summary)
            }
        )
    }

    private static func summary(
        _ summary: AIAcceptedFeedbackSummary?,
        matches records: [AIAcceptedFeedbackRecord]
    ) -> Bool {
        guard let rebuilt = buildSummary(records: records, generatedAt: Date()) else {
            return summary == nil
        }
        guard let summary else {
            return false
        }
        return summary.feedbackCount == records.count
            && summary.historyHash == rebuilt.historyHash
    }

    private static func extractedAvoidTerms(from text: String) -> [String] {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard !normalized.isEmpty,
              !TextProtection.containsSecretLikeContent(normalized) else {
            return []
        }
        var terms: [String] = []
        let patterns = [
            #"[A-Za-z][A-Za-z0-9_./:-]{1,}"#,
            #"\p{Han}{2,8}"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            for match in regex.matches(in: normalized, range: nsRange) {
                guard let range = Range(match.range, in: normalized) else {
                    continue
                }
                let term = String(normalized[range])
                guard term.count <= 32,
                      LexicalContextBuilder.sanitizedAcceptedProfileText(term) != nil else {
                    continue
                }
                terms.append(term)
            }
        }
        if terms.isEmpty,
           normalized.count <= 24,
           LexicalContextBuilder.sanitizedAcceptedProfileText(normalized) != nil {
            terms.append(normalized)
        }
        return Array(Set(terms)).sorted()
    }

    private static func boundedText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }
        let clean = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard !clean.isEmpty,
              !TextProtection.containsSecretLikeContent(clean) else {
            return nil
        }
        if clean.count <= 36 {
            return clean
        }
        return String(clean.prefix(36)) + "..."
    }

    private static func loadRecords(
        from url: URL?,
        decoder: JSONDecoder
    ) -> [AIAcceptedFeedbackRecord] {
        guard let url,
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return content
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                guard let data = String(line).data(using: .utf8) else {
                    return nil
                }
                return try? decoder.decode(AIAcceptedFeedbackRecord.self, from: data)
            }
    }

    private static func loadSummary(
        from url: URL?,
        decoder: JSONDecoder
    ) -> AIAcceptedFeedbackSummary? {
        guard let url,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(AIAcceptedFeedbackSummary.self, from: data)
    }

    private static func fileModificationDate(_ url: URL?, fileManager: FileManager) -> Date? {
        guard let url else {
            return nil
        }
        return try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    private func persistSummary(_ summary: AIAcceptedFeedbackSummary?) throws {
        if let summary {
            if let summaryURL {
                try atomicWrite(try encoder.encode(summary), to: summaryURL)
            }
            if let mirrorURL {
                try atomicWrite(Data(Self.renderMarkdown(summary).utf8), to: mirrorURL)
            }
            return
        }
        if let summaryURL,
           fileManager.fileExists(atPath: summaryURL.path) {
            try fileManager.removeItem(at: summaryURL)
        }
        if let mirrorURL,
           fileManager.fileExists(atPath: mirrorURL.path) {
            try fileManager.removeItem(at: mirrorURL)
        }
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private static func defaultApplicationSupportAIDirectory(fileManager: FileManager) -> URL {
        let root = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return root
            .appendingPathComponent("KnowType", isDirectory: true)
            .appendingPathComponent("AI", isDirectory: true)
    }
}

func acceptedFeedbackLockURL(historyURL: URL?) -> URL? {
    historyURL?.deletingLastPathComponent().appendingPathComponent("accepted-ai-feedback.lock")
}

func acceptedFeedbackClearMarkerURL(historyURL: URL?) -> URL? {
    historyURL?.deletingLastPathComponent().appendingPathComponent("accepted-ai-feedback.clear.json")
}

func withAcceptedFeedbackFileLock<T>(
    lockURL: URL?,
    fileManager: FileManager = .default,
    _ body: () throws -> T
) throws -> T {
    acceptedFeedbackFileLock.lock()
    defer {
        acceptedFeedbackFileLock.unlock()
    }

    guard let lockURL else {
        return try body()
    }

    try fileManager.createDirectory(
        at: lockURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    if !fileManager.fileExists(atPath: lockURL.path) {
        fileManager.createFile(atPath: lockURL.path, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: lockURL)
    defer {
        try? handle.close()
    }
    guard flock(handle.fileDescriptor, LOCK_EX) == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }
    defer {
        flock(handle.fileDescriptor, LOCK_UN)
    }
    return try body()
}
