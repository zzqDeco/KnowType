import CryptoKit
import Foundation
import KnowTypeCore

private let acceptedLearningFileLock = NSLock()

private func withAcceptedLearningFileLock<T>(_ body: () throws -> T) rethrows -> T {
    acceptedLearningFileLock.lock()
    defer { acceptedLearningFileLock.unlock() }
    return try body()
}

public struct AIAcceptedLearningRecord: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var acceptedAt: Date
    public var schemaID: String
    public var appBundleID: String?
    public var rawInput: String?
    public var lockedPrefix: String?
    public var acceptedText: String
    public var provider: String
    public var contextVersion: String
    public var textHash: String
    public var commitKind: String
    public var candidateSource: String
    public var extractedTerms: [LexicalContextTerm]

    public init(
        schemaVersion: Int = 1,
        acceptedAt: Date = Date(),
        schemaID: String,
        appBundleID: String? = nil,
        rawInput: String? = nil,
        lockedPrefix: String? = nil,
        acceptedText: String,
        provider: String,
        contextVersion: String,
        textHash: String? = nil,
        commitKind: String = "ai",
        candidateSource: String,
        extractedTerms: [LexicalContextTerm]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.acceptedAt = acceptedAt
        self.schemaID = schemaID
        self.appBundleID = appBundleID
        self.rawInput = rawInput
        self.lockedPrefix = lockedPrefix
        self.acceptedText = acceptedText
        self.provider = provider
        self.contextVersion = contextVersion
        self.textHash = textHash ?? Self.hash(acceptedText)
        self.commitKind = commitKind
        self.candidateSource = candidateSource
        self.extractedTerms = extractedTerms ?? AIAcceptedTermExtractor().extractTerms(from: acceptedText)
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public struct AIAcceptedLanguageSummary: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var historyHash: String
    public var acceptedCount: Int
    public var termProfile: [LexicalContextTerm]
    public var styleProfile: ToneProfile
    public var recentAcceptedCommits: [String]
    public var sourceSummary: [String]

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        historyHash: String,
        acceptedCount: Int,
        termProfile: [LexicalContextTerm],
        styleProfile: ToneProfile,
        recentAcceptedCommits: [String],
        sourceSummary: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.historyHash = historyHash
        self.acceptedCount = acceptedCount
        self.termProfile = termProfile
        self.styleProfile = styleProfile
        self.recentAcceptedCommits = recentAcceptedCommits
        self.sourceSummary = sourceSummary
    }
}

public protocol AIAcceptedLearningRecording: Sendable {
    func recordAcceptedAI(_ record: AIAcceptedLearningRecord) async
}

public protocol AIAcceptedLearningSnapshotProviding: Sendable {
    func snapshot() -> AIAcceptedLanguageSummary?
}

public struct AIAcceptedTermExtractor: Sendable {
    public var maxTerms: Int

    public init(maxTerms: Int = 24) {
        self.maxTerms = max(1, maxTerms)
    }

    public func extractTerms(from text: String) -> [LexicalContextTerm] {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              !TextProtection.containsSecretLikeContent(clean) else {
            return []
        }

        var counts: [String: Int] = [:]
        addTechnicalTerms(from: clean, to: &counts)
        addHanTerms(from: clean, to: &counts)

        return counts
            .map { term, count in
                LexicalContextTerm(
                    text: term,
                    score: min(1, 0.52 + Double(count) * 0.12),
                    source: "accepted-ai"
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

    private func addTechnicalTerms(from text: String, to counts: inout [String: Int]) {
        let tokens = matches(#"\b[A-Za-z][A-Za-z0-9_+.-]{1,}\b"#, in: text)
            .map { token -> String in
                TextProtection.canonicalTechnicalToken(token) ?? token
            }
            .filter { token in
                token.count >= 2 && token.count <= 32
            }

        for token in tokens where isInjectableToken(token) {
            counts[token, default: 0] += 1
        }

        for index in tokens.indices.dropLast() {
            let phrase = "\(tokens[index]) \(tokens[index + 1])"
            guard phrase.count <= 40,
                  phrase.range(of: #"[A-Z_]"#, options: .regularExpression) != nil else {
                continue
            }
            counts[phrase, default: 0] += 1
        }
    }

    private func addHanTerms(from text: String, to counts: inout [String: Int]) {
        for run in matches(#"\p{Han}+"#, in: text) {
            let chars = Array(run)
            if (2...8).contains(chars.count) {
                let term = String(chars)
                if isUsefulHanTerm(term) {
                    counts[term, default: 0] += 1
                }
                continue
            }
            guard chars.count > 8 else {
                continue
            }
            for width in 2...4 {
                guard chars.count >= width else {
                    continue
                }
                for start in 0...(chars.count - width) {
                    let term = String(chars[start..<(start + width)])
                    if isUsefulHanTerm(term) {
                        counts[term, default: 0] += 1
                    }
                }
            }
        }
    }

    private func isInjectableToken(_ token: String) -> Bool {
        guard LexicalContextBuilder.sanitizedAcceptedProfileText(token) != nil else {
            return false
        }
        if TextProtection.canonicalTechnicalToken(token) != nil {
            return true
        }
        return token.range(of: #"[A-Z_]"#, options: .regularExpression) != nil
            || token.count >= 3
    }

    private func isUsefulHanTerm(_ term: String) -> Bool {
        let stopTerms: Set<String> = [
            "这个", "那个", "就是", "然后", "所以", "但是", "可以", "需要", "觉得",
            "我们", "你们", "他们", "一个", "一下", "这里", "那里"
        ]
        return !stopTerms.contains(term)
            && LexicalContextBuilder.sanitizedAcceptedProfileText(term) != nil
    }

    private func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: text) else {
                return nil
            }
            return String(text[range])
        }
    }
}

public final class AIAcceptedLearningStore:
    AIAcceptedLearningRecording,
    AIAcceptedLearningSnapshotProviding,
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
    private var records: [AIAcceptedLearningRecord]
    private var summary: AIAcceptedLanguageSummary?
    private var summaryTask: Task<Void, Never>?

    public init(
        historyURL: URL? = AIAcceptedLearningStore.defaultHistoryURL(),
        summaryURL: URL? = AIAcceptedLearningStore.defaultSummaryURL(),
        mirrorURL: URL? = AIUserDirectory.defaultDirectory().acceptedLearningMirrorURL,
        fileManager: FileManager = .default,
        diagnosticSink: any AIRecommendationDiagnosticSink = NoopAIRecommendationDiagnosticSink(),
        summaryDelayNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.historyURL = historyURL
        self.summaryURL = summaryURL
        self.mirrorURL = mirrorURL
        self.fileManager = fileManager
        self.diagnosticSink = diagnosticSink
        self.summaryDelayNanoseconds = summaryDelayNanoseconds
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
        self.records = Self.loadRecords(from: historyURL, decoder: decoder)
        self.summary = Self.loadSummary(from: summaryURL, decoder: decoder)
            ?? Self.buildSummary(records: records, generatedAt: Date())
    }

    public static func inMemory(
        diagnosticSink: any AIRecommendationDiagnosticSink = NoopAIRecommendationDiagnosticSink()
    ) -> AIAcceptedLearningStore {
        AIAcceptedLearningStore(
            historyURL: nil,
            summaryURL: nil,
            mirrorURL: nil,
            diagnosticSink: diagnosticSink,
            summaryDelayNanoseconds: 0
        )
    }

    public static func defaultHistoryURL(fileManager: FileManager = .default) -> URL {
        defaultApplicationSupportAIDirectory(fileManager: fileManager)
            .appendingPathComponent("accepted-ai-learning.jsonl", isDirectory: false)
    }

    public static func defaultSummaryURL(fileManager: FileManager = .default) -> URL {
        defaultApplicationSupportAIDirectory(fileManager: fileManager)
            .appendingPathComponent("accepted-ai-summary.json", isDirectory: false)
    }

    public func recordAcceptedAI(_ record: AIAcceptedLearningRecord) async {
        let protectedValues = [record.rawInput, record.lockedPrefix, record.acceptedText].compactMap { $0 }
        guard !protectedValues.contains(where: TextProtection.containsSecretLikeContent) else {
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .acceptedLearningSkippedSecret,
                    rawLength: record.rawInput?.count,
                    candidateCount: record.extractedTerms.count,
                    reason: "secret_like_text"
                )
            )
            return
        }

        do {
            try append(record)
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .acceptedLearningRecorded,
                    rawLength: record.rawInput?.count,
                    candidateCount: record.extractedTerms.count,
                    reason: "text_hash=\(String(record.textHash.prefix(8)))"
                )
            )
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .acceptedLearningTermsExtracted,
                    candidateCount: record.extractedTerms.count,
                    reason: "source=ai-accepted"
                )
            )
        } catch {
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .lexicalProfileFallback,
                    reason: "accepted_learning_write_failed:\(String(describing: type(of: error)))"
                )
            )
        }
    }

    public func snapshot() -> AIAcceptedLanguageSummary? {
        lock.lock()
        let current = summary
        lock.unlock()
        return current
    }

    public func allRecords() -> [AIAcceptedLearningRecord] {
        lock.lock()
        let current = records
        lock.unlock()
        return current
    }

    private func append(_ record: AIAcceptedLearningRecord) throws {
        try withAcceptedLearningFileLock {
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
        }
        lock.lock()
        records.append(record)
        lock.unlock()
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
        lock.lock()
        let currentRecords = records
        lock.unlock()

        let nextSummary = Self.buildSummary(records: currentRecords, generatedAt: Date())

        lock.lock()
        summary = nextSummary
        lock.unlock()

        guard let nextSummary else {
            return
        }

        do {
            try withAcceptedLearningFileLock {
                if let summaryURL {
                    try atomicWrite(try encoder.encode(nextSummary), to: summaryURL)
                }
                if let mirrorURL {
                    try atomicWrite(Data(Self.renderMarkdown(nextSummary).utf8), to: mirrorURL)
                }
            }
        } catch {
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .lexicalProfileFallback,
                    reason: "accepted_learning_summary_write_failed:\(String(describing: type(of: error)))"
                )
            )
        }
    }

    private static func buildSummary(
        records: [AIAcceptedLearningRecord],
        generatedAt: Date
    ) -> AIAcceptedLanguageSummary? {
        guard !records.isEmpty else {
            return nil
        }

        var termScores: [String: (score: Double, source: String)] = [:]
        for record in records {
            for term in record.extractedTerms {
                guard let clean = LexicalContextBuilder.sanitizedAcceptedProfileText(term.text) else {
                    continue
                }
                let nextScore = min(1, max(0, term.score))
                if let existing = termScores[clean] {
                    termScores[clean] = (
                        score: min(1, existing.score + nextScore * 0.18),
                        source: existing.source
                    )
                } else {
                    termScores[clean] = (score: nextScore, source: "accepted-ai")
                }
            }
        }

        let terms = termScores
            .map { text, value in
                LexicalContextTerm(text: text, score: value.score, source: value.source)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.text < rhs.text
                }
                return lhs.score > rhs.score
            }
            .prefix(32)
            .map { $0 }

        let recentCommits = records
            .suffix(16)
            .compactMap { boundedCommit($0.acceptedText) }
            .suffix(8)

        let style = LexicalContextBuilder().acceptedStyleProfile(from: Array(recentCommits))
        let historyHash = Self.historyHash(records)
        return AIAcceptedLanguageSummary(
            generatedAt: generatedAt,
            historyHash: historyHash,
            acceptedCount: records.count,
            termProfile: terms,
            styleProfile: style,
            recentAcceptedCommits: Array(recentCommits),
            sourceSummary: [
                "accepted-ai-summary: terms=\(terms.count) commits=\(recentCommits.count) history=\(String(historyHash.prefix(8)))"
            ]
        )
    }

    private static func boundedCommit(_ text: String) -> String? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              !TextProtection.containsSecretLikeContent(clean) else {
            return nil
        }
        if clean.count <= 48 {
            return clean
        }
        return String(clean.prefix(48)) + "..."
    }

    private static func historyHash(_ records: [AIAcceptedLearningRecord]) -> String {
        let joined = records.map(\.textHash).joined(separator: "\n")
        return SHA256.hash(data: Data(joined.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func renderMarkdown(_ summary: AIAcceptedLanguageSummary) -> String {
        var lines: [String] = [
            "# KnowType Accepted AI Learning",
            "",
            "This is a local summary of AI recommendations the user explicitly accepted. Full history stays local and is not injected into provider requests.",
            "",
            "## Stats",
            "- Accepted count: \(summary.acceptedCount)",
            "- History hash: \(summary.historyHash)",
            "- Generated at: \(ISO8601DateFormatter().string(from: summary.generatedAt))",
            "",
            "## Style",
            "- Register: \(summary.styleProfile.register)",
            "- Technical density: \(String(format: "%.2f", summary.styleProfile.technicalDensity))",
            "- Code switching ratio: \(String(format: "%.2f", summary.styleProfile.codeSwitchingRatio))",
            "- Punctuation style: \(summary.styleProfile.punctuationStyle)"
        ]
        if !summary.styleProfile.connectors.isEmpty {
            lines.append("- Connectors: \(summary.styleProfile.connectors.joined(separator: ", "))")
        }
        if !summary.styleProfile.endings.isEmpty {
            lines.append("- Common endings: \(summary.styleProfile.endings.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("## Accepted Terms")
        if summary.termProfile.isEmpty {
            lines.append("- No accepted AI terms yet.")
        } else {
            for term in summary.termProfile {
                lines.append("- \(term.text) [\(term.source), \(String(format: "%.2f", term.score))]")
            }
        }
        lines.append("")
        lines.append("## Recent Accepted Commits")
        if summary.recentAcceptedCommits.isEmpty {
            lines.append("- No recent accepted AI commits yet.")
        } else {
            summary.recentAcceptedCommits.forEach { lines.append("- \($0)") }
        }
        lines.append("")
        lines.append("## Sources")
        summary.sourceSummary.forEach { lines.append("- \($0)") }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func loadRecords(
        from url: URL?,
        decoder: JSONDecoder
    ) -> [AIAcceptedLearningRecord] {
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
                return try? decoder.decode(AIAcceptedLearningRecord.self, from: data)
            }
    }

    private static func loadSummary(
        from url: URL?,
        decoder: JSONDecoder
    ) -> AIAcceptedLanguageSummary? {
        guard let url,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(AIAcceptedLanguageSummary.self, from: data)
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
