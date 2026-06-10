import Foundation
import XCTest
@testable import KnowTypeAI

final class AIAcceptedFeedbackStoreTests: XCTestCase {
    func testRecordAcceptedFeedbackBuildsSummaryAndSnapshot() async throws {
        let store = AIAcceptedFeedbackStore.inMemory()
        let acceptID = UUID()
        await store.recordAcceptedFeedback(
            AIAcceptedFeedbackRecord(
                acceptID: acceptID,
                schemaID: "pinyin_simp",
                provider: "test-provider",
                contextVersion: "ctx",
                acceptedTextHash: "abc",
                deletedRanges: [AIAcceptedFeedbackTextRange(location: 10, length: 6)],
                deletedTexts: ["这个表达太长"],
                deletedVisibleCharacterCount: 6,
                deletedRatio: 0.6,
                strength: .strong,
                reason: "delete_idle"
            )
        )

        let records = store.allRecords()
        XCTAssertEqual(records.count, 1)
        let snapshot = store.snapshot(schemaID: "pinyin_simp")
        XCTAssertEqual(snapshot?.summary.feedbackCount, 1)
        XCTAssertEqual(snapshot?.summary.strongCount, 1)
        XCTAssertEqual(snapshot?.markdown.contains("AI Feedback"), true)
        XCTAssertEqual(snapshot?.markdown.contains("accepted-ai-feedback-summary:"), true)
    }

    func testSecretLikeFeedbackIsSkipped() async throws {
        let store = AIAcceptedFeedbackStore.inMemory()
        await store.recordAcceptedFeedback(
            AIAcceptedFeedbackRecord(
                acceptID: UUID(),
                schemaID: "pinyin_simp",
                provider: "test-provider",
                contextVersion: "ctx",
                acceptedTextHash: "abc",
                deletedRanges: [AIAcceptedFeedbackTextRange(location: 0, length: 20)],
                deletedTexts: ["API_KEY=sk-testsecret"],
                deletedVisibleCharacterCount: 20,
                deletedRatio: 1,
                strength: .strong,
                reason: "delete_idle"
            )
        )

        XCTAssertTrue(store.allRecords().isEmpty)
        XCTAssertNil(store.snapshot())
    }

    func testMaintenanceRebuildAndClearCoverFeedbackFiles() throws {
        let directory = temporaryDirectory()
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
        let feedbackHistoryURL = directory.appendingPathComponent("accepted-ai-feedback.jsonl")
        let feedbackSummaryURL = directory.appendingPathComponent("accepted-ai-feedback-summary.json")
        let feedbackMirrorURL = directory.appendingPathComponent("ACCEPTED_AI_FEEDBACK.md")
        let lexicalJSONURL = directory.appendingPathComponent("lexical-profile.json")
        let lexicalMarkdownURL = directory.appendingPathComponent("LEXICAL_PROFILE.md")

        let record = AIAcceptedFeedbackRecord(
            acceptID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            schemaID: "pinyin_simp",
            provider: "test-provider",
            contextVersion: "ctx",
            acceptedTextHash: "abc",
            deletedRanges: [AIAcceptedFeedbackTextRange(location: 2, length: 8)],
            deletedTexts: ["冗长表达"],
            deletedVisibleCharacterCount: 4,
            deletedRatio: 0.5,
            strength: .medium,
            reason: "delete_idle"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(record)
        line.append(0x0A)
        try line.write(to: feedbackHistoryURL, options: .atomic)

        let maintenance = AIAcceptedLearningMaintenance(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            feedbackHistoryURL: feedbackHistoryURL,
            feedbackSummaryURL: feedbackSummaryURL,
            feedbackMirrorURL: feedbackMirrorURL,
            lexicalJSONURL: lexicalJSONURL,
            lexicalMarkdownURL: lexicalMarkdownURL
        )

        let rebuilt = try maintenance.rebuild()
        XCTAssertEqual(rebuilt.feedback.history.recordCount, 1)
        XCTAssertEqual(rebuilt.feedback.summary.feedbackCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: feedbackSummaryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: feedbackMirrorURL.path))

        let cleared = try maintenance.clear(confirm: true)
        XCTAssertEqual(cleared.feedback.history.recordCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: feedbackHistoryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: feedbackSummaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: feedbackMirrorURL.path))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowTypeAcceptedFeedbackTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
