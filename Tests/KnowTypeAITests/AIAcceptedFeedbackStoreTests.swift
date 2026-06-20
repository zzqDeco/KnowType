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

    func testContextMarkdownIncludesReplacementPatterns() {
        let summary = AIAcceptedFeedbackSummary(
            generatedAt: Date(timeIntervalSince1970: 0),
            historyHash: "hash",
            feedbackCount: 1,
            strongCount: 1,
            avoidTerms: ["冗长表达"],
            styleAdjustments: ["Prefer shorter AI continuations when context is ambiguous."],
            replacementPatterns: ["冗长表达 -> 简洁说法"],
            sourceSummary: ["accepted-ai-feedback-summary: records=1 strong=1 history=hash"]
        )

        let markdown = AIAcceptedFeedbackStore.renderContextMarkdown(summary)

        XCTAssertTrue(markdown.contains("## Replacement Patterns"))
        XCTAssertTrue(markdown.contains("冗长表达 -> 简洁说法"))
    }

    func testReplacementPatternsReconstructMultiBackspaceDeletion() async throws {
        let store = AIAcceptedFeedbackStore.inMemory()
        await store.recordAcceptedFeedback(
            AIAcceptedFeedbackRecord(
                acceptID: UUID(),
                schemaID: "pinyin_simp",
                provider: "test-provider",
                contextVersion: "ctx",
                acceptedTextHash: "abc",
                deletedRanges: [
                    AIAcceptedFeedbackTextRange(location: 12, length: 1),
                    AIAcceptedFeedbackTextRange(location: 11, length: 1),
                    AIAcceptedFeedbackTextRange(location: 10, length: 1)
                ],
                deletedTexts: ["c", "b", "a"],
                deletedVisibleCharacterCount: 3,
                deletedRatio: 0.5,
                strength: .medium,
                replacementText: "xyz",
                reason: "replacement_commit"
            )
        )

        XCTAssertEqual(store.snapshot()?.summary.replacementPatterns, ["abc -> xyz"])
    }

    func testReplacementPatternsSkipNonContiguousDeletedText() async throws {
        let store = AIAcceptedFeedbackStore.inMemory()
        await store.recordAcceptedFeedback(
            AIAcceptedFeedbackRecord(
                acceptID: UUID(),
                schemaID: "pinyin_simp",
                provider: "test-provider",
                contextVersion: "ctx",
                acceptedTextHash: "abc",
                deletedRanges: [
                    AIAcceptedFeedbackTextRange(location: 10, length: 1),
                    AIAcceptedFeedbackTextRange(location: 12, length: 1)
                ],
                deletedTexts: ["a", "c"],
                deletedVisibleCharacterCount: 2,
                deletedRatio: 0.5,
                strength: .medium,
                replacementText: "xyz",
                reason: "replacement_commit"
            )
        )

        XCTAssertEqual(store.snapshot()?.summary.replacementPatterns, [])
    }

    func testReplacementPatternsSkipProtectedSummaryTextButKeepHistory() async throws {
        let store = AIAcceptedFeedbackStore.inMemory()
        await store.recordAcceptedFeedback(
            AIAcceptedFeedbackRecord(
                acceptID: UUID(),
                schemaID: "pinyin_simp",
                provider: "test-provider",
                contextVersion: "ctx",
                acceptedTextHash: "abc",
                deletedRanges: [AIAcceptedFeedbackTextRange(location: 10, length: 17)],
                deletedTexts: ["alice@example.com"],
                deletedVisibleCharacterCount: 17,
                deletedRatio: 0.5,
                strength: .medium,
                replacementText: "/Users/example/project",
                reason: "replacement_commit"
            )
        )

        XCTAssertEqual(store.allRecords().count, 1)
        XCTAssertEqual(store.snapshot()?.summary.replacementPatterns, [])
        XCTAssertFalse(store.snapshot()?.markdown.contains("alice@example.com") ?? true)
        XCTAssertFalse(store.snapshot()?.markdown.contains("/Users/example/project") ?? true)
    }

    func testReplacementPatternsKeepOrdinaryLanguageSummaryText() async throws {
        let store = AIAcceptedFeedbackStore.inMemory()
        await store.recordAcceptedFeedback(
            AIAcceptedFeedbackRecord(
                acceptID: UUID(),
                schemaID: "pinyin_simp",
                provider: "test-provider",
                contextVersion: "ctx",
                acceptedTextHash: "abc",
                deletedRanges: [AIAcceptedFeedbackTextRange(location: 10, length: 4)],
                deletedTexts: ["冗长表达"],
                deletedVisibleCharacterCount: 4,
                deletedRatio: 0.5,
                strength: .medium,
                replacementText: "简洁说法",
                reason: "replacement_commit"
            )
        )

        XCTAssertEqual(store.snapshot()?.summary.replacementPatterns, ["冗长表达 -> 简洁说法"])
    }

    func testHistoryHashIncludesSummaryDrivingTextFields() {
        let acceptID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let base = AIAcceptedFeedbackRecord(
            acceptID: acceptID,
            schemaID: "pinyin_simp",
            provider: "test-provider",
            contextVersion: "ctx",
            acceptedTextHash: "abc",
            deletedRanges: [AIAcceptedFeedbackTextRange(location: 10, length: 4)],
            deletedTexts: ["冗长表达"],
            deletedVisibleCharacterCount: 4,
            deletedRatio: 0.5,
            strength: .medium,
            replacementText: "简洁说法",
            reason: "replacement_commit"
        )
        let changedDeletedText = AIAcceptedFeedbackRecord(
            acceptID: acceptID,
            schemaID: "pinyin_simp",
            provider: "test-provider",
            contextVersion: "ctx",
            acceptedTextHash: "abc",
            deletedRanges: [AIAcceptedFeedbackTextRange(location: 10, length: 4)],
            deletedTexts: ["别的表达"],
            deletedVisibleCharacterCount: 4,
            deletedRatio: 0.5,
            strength: .medium,
            replacementText: "简洁说法",
            reason: "replacement_commit"
        )
        let changedReplacementText = AIAcceptedFeedbackRecord(
            acceptID: acceptID,
            schemaID: "pinyin_simp",
            provider: "test-provider",
            contextVersion: "ctx",
            acceptedTextHash: "abc",
            deletedRanges: [AIAcceptedFeedbackTextRange(location: 10, length: 4)],
            deletedTexts: ["冗长表达"],
            deletedVisibleCharacterCount: 4,
            deletedRatio: 0.5,
            strength: .medium,
            replacementText: "另一种说法",
            reason: "replacement_commit"
        )

        XCTAssertNotEqual(
            AIAcceptedFeedbackStore.historyHash([base]),
            AIAcceptedFeedbackStore.historyHash([changedDeletedText])
        )
        XCTAssertNotEqual(
            AIAcceptedFeedbackStore.historyHash([base]),
            AIAcceptedFeedbackStore.historyHash([changedReplacementText])
        )
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

    func testStartupBuildsMissingFeedbackSummaryInMemoryWithoutWritingOnDisk() throws {
        let directory = temporaryDirectory()
        let historyURL = directory.appendingPathComponent("accepted-ai-feedback.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-feedback-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_FEEDBACK.md")
        let record = AIAcceptedFeedbackRecord(
            acceptID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
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
        try line.write(to: historyURL, options: .atomic)

        let store = AIAcceptedFeedbackStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL
        )

        XCTAssertEqual(store.snapshot()?.summary.feedbackCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: summaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: mirrorURL.path))
    }

    func testStoreInitDoesNotCreateFeedbackFilesWhenHistoryIsMissing() {
        let directory = temporaryDirectory().appendingPathComponent("missing-feedback", isDirectory: true)
        let historyURL = directory.appendingPathComponent("accepted-ai-feedback.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-feedback-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_FEEDBACK.md")
        let lockURL = directory.appendingPathComponent("accepted-ai-feedback.lock")
        defer {
            try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
        }

        let store = AIAcceptedFeedbackStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL
        )

        XCTAssertTrue(store.allRecords().isEmpty)
        XCTAssertNil(store.snapshot())
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: lockURL.path))
    }

    func testRunningStoreDropsFeedbackAfterExternalClear() async throws {
        let directory = temporaryDirectory()
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
        let feedbackHistoryURL = directory.appendingPathComponent("accepted-ai-feedback.jsonl")
        let feedbackSummaryURL = directory.appendingPathComponent("accepted-ai-feedback-summary.json")
        let feedbackMirrorURL = directory.appendingPathComponent("ACCEPTED_AI_FEEDBACK.md")
        let lexicalJSONURL = directory.appendingPathComponent("lexical-profile.json")
        let lexicalMarkdownURL = directory.appendingPathComponent("LEXICAL_PROFILE.md")
        let store = AIAcceptedFeedbackStore(
            historyURL: feedbackHistoryURL,
            summaryURL: feedbackSummaryURL,
            mirrorURL: feedbackMirrorURL,
            summaryDelayNanoseconds: 0
        )
        await store.recordAcceptedFeedback(
            AIAcceptedFeedbackRecord(
                acceptID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                schemaID: "pinyin_simp",
                provider: "test-provider",
                contextVersion: "ctx",
                acceptedTextHash: "old",
                deletedRanges: [AIAcceptedFeedbackTextRange(location: 2, length: 8)],
                deletedTexts: ["旧表达"],
                deletedVisibleCharacterCount: 3,
                deletedRatio: 0.5,
                strength: .medium,
                reason: "delete_idle"
            )
        )
        XCTAssertEqual(store.allRecords().count, 1)
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

        _ = try maintenance.clear(confirm: true)

        XCTAssertTrue(store.allRecords().isEmpty)
        XCTAssertNil(store.snapshot())
        await store.recordAcceptedFeedback(
            AIAcceptedFeedbackRecord(
                acceptID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                schemaID: "pinyin_simp",
                provider: "test-provider",
                contextVersion: "ctx",
                acceptedTextHash: "new",
                deletedRanges: [AIAcceptedFeedbackTextRange(location: 2, length: 8)],
                deletedTexts: ["新表达"],
                deletedVisibleCharacterCount: 3,
                deletedRatio: 0.5,
                strength: .medium,
                reason: "delete_idle"
            )
        )
        XCTAssertEqual(store.allRecords().map(\.acceptedTextHash), ["new"])
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
