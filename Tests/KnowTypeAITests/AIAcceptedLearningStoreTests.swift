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
