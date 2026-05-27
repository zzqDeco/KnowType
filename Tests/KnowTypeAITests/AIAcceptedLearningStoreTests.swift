import Foundation
import XCTest
@testable import KnowTypeAI

final class AIAcceptedLearningStoreTests: XCTestCase {
    func testStoreWritesHistorySummaryAndMirror() async throws {
        let directory = temporaryDirectory()
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
        let store = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0
        )

        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 1),
                schemaID: "pinyin_simp",
                appBundleID: "com.apple.TextEdit",
                rawInput: "jsonschema",
                lockedPrefix: nil,
                acceptedText: "JSON Schema 可以继续推进这个方案",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )

        let records = store.allRecords()
        let summary = try XCTUnwrap(store.snapshot())
        let historyContent = try String(contentsOf: historyURL, encoding: .utf8)
        let mirror = try String(contentsOf: mirrorURL, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let savedSummary = try decoder.decode(AIAcceptedLanguageSummary.self, from: Data(contentsOf: summaryURL))

        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(historyContent.contains("JSON Schema 可以继续推进这个方案"))
        XCTAssertEqual(summary.acceptedCount, 1)
        XCTAssertEqual(savedSummary.historyHash, summary.historyHash)
        XCTAssertTrue(summary.termProfile.contains { $0.text == "JSON" })
        XCTAssertTrue(summary.termProfile.contains { $0.text == "JSON Schema" })
        XCTAssertTrue(summary.recentAcceptedCommits.contains("JSON Schema 可以继续推进这个方案"))
        XCTAssertTrue(mirror.contains("Accepted count: 1"))
        XCTAssertTrue(mirror.contains("JSON Schema"))
    }

    func testSecretLikeRecordIsSkipped() async {
        let diagnosticSink = RecordingDiagnosticSink()
        let store = AIAcceptedLearningStore.inMemory(diagnosticSink: diagnosticSink)

        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                schemaID: "pinyin_simp",
                rawInput: "secret",
                acceptedText: "API_KEY=sk-1234567890abcdef1234567890",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )

        XCTAssertTrue(store.allRecords().isEmpty)
        XCTAssertNil(store.snapshot())
        XCTAssertTrue(diagnosticSink.events.contains { $0.stage == .acceptedLearningSkippedSecret })
    }

    func testStoreRepairsStaleSummaryOnLoad() throws {
        let directory = temporaryDirectory()
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
        let first = AIAcceptedLearningRecord(
            acceptedAt: Date(timeIntervalSince1970: 1),
            schemaID: "pinyin_simp",
            rawInput: "json",
            acceptedText: "JSON Schema 可以继续推进",
            provider: "ai-test",
            contextVersion: "test",
            candidateSource: "ai:ai-test"
        )
        let second = AIAcceptedLearningRecord(
            acceptedAt: Date(timeIntervalSince1970: 2),
            schemaID: "pinyin_simp",
            rawInput: "api",
            acceptedText: "API 设计可以保持简洁",
            provider: "ai-test",
            contextVersion: "test",
            candidateSource: "ai:ai-test"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let historyLines = try [first, second]
            .map { try String(data: encoder.encode($0), encoding: .utf8) ?? "" }
            .joined(separator: "\n") + "\n"
        try historyLines.write(to: historyURL, atomically: true, encoding: .utf8)
        let staleSummary = AIAcceptedLanguageSummary(
            generatedAt: Date(timeIntervalSince1970: 3),
            historyHash: "stale",
            acceptedCount: 1,
            termProfile: first.extractedTerms,
            styleProfile: ToneProfile(),
            recentAcceptedCommits: [first.acceptedText],
            sourceSummary: ["accepted-ai-summary: terms=1 commits=1 history=stale"]
        )
        try encoder.encode(staleSummary).write(to: summaryURL, options: .atomic)

        let store = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0
        )
        let repairedSummary = try XCTUnwrap(store.snapshot())
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let savedSummary = try decoder.decode(AIAcceptedLanguageSummary.self, from: Data(contentsOf: summaryURL))
        let mirror = try String(contentsOf: mirrorURL, encoding: .utf8)

        XCTAssertEqual(repairedSummary.acceptedCount, 2)
        XCTAssertEqual(savedSummary.acceptedCount, 2)
        XCTAssertEqual(savedSummary.historyHash, repairedSummary.historyHash)
        XCTAssertNotEqual(repairedSummary.historyHash, "stale")
        XCTAssertTrue(mirror.contains("Accepted count: 2"))
    }

    func testLevelZeroAcceptedTextStaysInHistoryButOutOfInjectedSummary() async throws {
        let directory = temporaryDirectory()
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
        let store = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0
        )

        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                schemaID: "pinyin_simp",
                rawInput: "url",
                acceptedText: "https://example.com/private/path",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )

        let historyContent = try String(contentsOf: historyURL, encoding: .utf8)
        let summary = try XCTUnwrap(store.snapshot())
        let lexical = LexicalContextBuilder().snapshot(
            acceptedAITerms: summary.termProfile,
            acceptedAIRecentCommits: summary.recentAcceptedCommits,
            acceptedAISourceSummary: summary.sourceSummary
        )

        XCTAssertEqual(store.allRecords().count, 1)
        XCTAssertTrue(historyContent.contains("example.com"))
        XCTAssertEqual(summary.acceptedCount, 1)
        XCTAssertFalse(summary.recentAcceptedCommits.contains { $0.contains("example.com") })
        XCTAssertFalse(summary.termProfile.contains { $0.text.contains("example.com") })
        XCTAssertFalse(lexical?.markdown.contains("example.com") ?? false)
    }

    func testLexicalContextMergesAcceptedTechnicalTermsWithoutFullHistory() throws {
        let summary = AIAcceptedLanguageSummary(
            historyHash: "abc123",
            acceptedCount: 3,
            termProfile: [
                LexicalContextTerm(text: "JSON", score: 1, source: "accepted-ai"),
                LexicalContextTerm(text: "snake_case", score: 0.8, source: "accepted-ai")
            ],
            styleProfile: ToneProfile(codeSwitchingRatio: 0.5),
            recentAcceptedCommits: ["JSON Schema 可以继续推进这个方案"],
            sourceSummary: ["accepted-ai-summary: terms=2 commits=1 history=abc123"]
        )

        let snapshot = try XCTUnwrap(
            LexicalContextBuilder().snapshot(
                recentCommits: [],
                selectionHistory: [],
                acceptedAITerms: summary.termProfile,
                acceptedAIRecentCommits: summary.recentAcceptedCommits,
                acceptedAISourceSummary: summary.sourceSummary,
                persistentTerms: [
                    LexicalContextTerm(text: "长期高频", score: 1, source: "rime-userdb")
                ]
            )
        )

        XCTAssertTrue(snapshot.terms.contains { $0.text == "JSON" && $0.source == "accepted-ai" })
        XCTAssertTrue(snapshot.terms.contains { $0.text == "snake_case" })
        XCTAssertTrue(snapshot.recentCommits.contains("JSON Schema 可以继续推进这个方案"))
        XCTAssertTrue(snapshot.sourceSummary.contains("accepted-ai-summary: terms=2 commits=1 history=abc123"))
        XCTAssertTrue(snapshot.sourceSummary.contains("rime-userdb: 1"))
    }
}

private final class RecordingDiagnosticSink: AIRecommendationDiagnosticSink, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [AIRecommendationDiagnosticEvent] = []

    func record(_ event: AIRecommendationDiagnosticEvent) {
        lock.lock()
        recordedEvents.append(event)
        lock.unlock()
    }

    var events: [AIRecommendationDiagnosticEvent] {
        lock.lock()
        let events = recordedEvents
        lock.unlock()
        return events
    }
}

private func temporaryDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("KnowTypeAIAcceptedLearningTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
