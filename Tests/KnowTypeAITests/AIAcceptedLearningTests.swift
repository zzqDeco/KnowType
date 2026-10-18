import Foundation
import KnowTypeCore
import XCTest
@testable import KnowTypeAI

final class AIAcceptedLearningTests: XCTestCase {
    func testAppendTrimsRecordsToMaxRecordCountInMemoryAndOnDiskAfterReload() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")

        let store = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 3
        )

        let texts = [
            "RecordOne 第一条记录",
            "RecordTwo 第二条记录",
            "RecordThree 第三条记录",
            "RecordFour 第四条记录",
            "RecordFive 第五条记录"
        ]

        for (index, text) in texts.enumerated() {
            await store.recordAcceptedAI(
                AIAcceptedLearningRecord(
                    acceptedAt: Date(timeIntervalSince1970: TimeInterval(index + 1)),
                    schemaID: "pinyin_simp",
                    rawInput: "rec\(index + 1)",
                    acceptedText: text,
                    provider: "ai-test",
                    contextVersion: "test",
                    candidateSource: "ai:ai-test"
                )
            )
        }

        let expectedTexts = Array(texts.suffix(3))
        XCTAssertEqual(store.allRecords().map(\.acceptedText), expectedTexts)

        let historyContent = try String(contentsOf: historyURL, encoding: .utf8)
        let historyLines = historyContent.split(whereSeparator: \.isNewline)
        XCTAssertEqual(historyLines.count, 3)
        XCTAssertFalse(historyContent.contains("RecordOne"))
        XCTAssertFalse(historyContent.contains("RecordTwo"))
        XCTAssertTrue(historyContent.contains("RecordThree"))
        XCTAssertTrue(historyContent.contains("RecordFour"))
        XCTAssertTrue(historyContent.contains("RecordFive"))

        let reloaded = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0
        )
        XCTAssertEqual(reloaded.allRecords().map(\.acceptedText), expectedTexts)
    }

    func testInitTrimsAndCompactsExistingHistoryExceedingMaxRecordCount() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let records = (1...5).map { index in
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                schemaID: "pinyin_simp",
                rawInput: "init\(index)",
                acceptedText: "InitToken\(index) 历史记录 \(index)",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        }
        let initialLines = try records
            .map { try XCTUnwrap(String(data: encoder.encode($0), encoding: .utf8)) }
            .joined(separator: "\n") + "\n"
        try initialLines.write(to: historyURL, atomically: true, encoding: .utf8)

        let store = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 2
        )

        let expectedTexts = ["InitToken4 历史记录 4", "InitToken5 历史记录 5"]
        XCTAssertEqual(store.allRecords().map(\.acceptedText), expectedTexts)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("accepted-ai-learning.lock").path
            )
        )

        let compactedContent = try String(contentsOf: historyURL, encoding: .utf8)
        let compactedLines = compactedContent.split(whereSeparator: \.isNewline)
        XCTAssertEqual(compactedLines.count, 2)
        XCTAssertFalse(compactedContent.contains("InitToken1"))
        XCTAssertFalse(compactedContent.contains("InitToken2"))
        XCTAssertFalse(compactedContent.contains("InitToken3"))
        XCTAssertTrue(compactedContent.contains("InitToken4"))
        XCTAssertTrue(compactedContent.contains("InitToken5"))

        let summary = try XCTUnwrap(store.snapshot())
        XCTAssertEqual(summary.acceptedCount, 2)
        XCTAssertEqual(summary.historyHash, AIAcceptedLearningStore.historyHash(store.allRecords()))
    }

    func testRebuildSummaryReflectsRetainedSlidingWindow() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")

        let store = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 2
        )

        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 1),
                schemaID: "double_pinyin",
                rawInput: "legacy",
                acceptedText: "LegacyToken 早期方案",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 2),
                schemaID: "pinyin_simp",
                rawInput: "json",
                acceptedText: "JSON Schema 中期方案",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 3),
                schemaID: "pinyin_simp",
                rawInput: "swift",
                acceptedText: "SwiftActor 最新方案",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )

        let summary = try XCTUnwrap(store.snapshot())
        XCTAssertEqual(summary.acceptedCount, 2)
        XCTAssertEqual(summary.historyHash, AIAcceptedLearningStore.historyHash(store.allRecords()))
        XCTAssertFalse(summary.termProfile.contains { $0.text == "LegacyToken" })
        XCTAssertTrue(summary.termProfile.contains { $0.text == "JSON" })
        XCTAssertTrue(summary.termProfile.contains { $0.text == "JSON Schema" })
        XCTAssertTrue(summary.termProfile.contains { $0.text == "SwiftActor" })
        XCTAssertEqual(summary.recentAcceptedCommits, ["JSON Schema 中期方案", "SwiftActor 最新方案"])
        XCTAssertNil(store.snapshot(schemaID: "double_pinyin"))
        XCTAssertEqual(store.snapshot(schemaID: "pinyin_simp")?.acceptedCount, 2)

        let mirror = try String(contentsOf: mirrorURL, encoding: .utf8)
        XCTAssertTrue(mirror.contains("Accepted count: 2"))
        XCTAssertFalse(mirror.contains("LegacyToken"))
        XCTAssertTrue(mirror.contains("SwiftActor"))
    }

    func testMaxRecordCountClampsToAtLeastOneAndDefaultsTo500() async throws {
        XCTAssertEqual(AIAcceptedLearningStore.defaultMaxRecordCount, 500)
        XCTAssertEqual(AIAcceptedLearningStore.inMemory().maxRecordCount, 500)

        let store = AIAcceptedLearningStore.inMemory(maxRecordCount: 0)
        XCTAssertEqual(store.maxRecordCount, 1)

        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                schemaID: "pinyin_simp",
                rawInput: "one",
                acceptedText: "FirstToken 第一条",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                schemaID: "pinyin_simp",
                rawInput: "two",
                acceptedText: "SecondToken 第二条",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )

        XCTAssertEqual(store.allRecords().map(\.acceptedText), ["SecondToken 第二条"])
        XCTAssertEqual(store.snapshot()?.acceptedCount, 1)
    }

    func testCompactionReloadsOnDiskHistoryAcrossMultipleStoreInstances() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")

        let storeA = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 2
        )
        let storeB = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 2
        )

        await storeA.recordAcceptedAI(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 1),
                schemaID: "pinyin_simp",
                rawInput: "a1",
                acceptedText: "StoreA 第一条",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        await storeB.recordAcceptedAI(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 2),
                schemaID: "pinyin_simp",
                rawInput: "b1",
                acceptedText: "StoreB 第二条",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        await storeA.recordAcceptedAI(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 3),
                schemaID: "pinyin_simp",
                rawInput: "a2",
                acceptedText: "StoreA 第三条",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )

        let reloaded = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 2
        )
        XCTAssertEqual(reloaded.allRecords().map(\.acceptedText), ["StoreB 第二条", "StoreA 第三条"])
    }

    func testEvictedSchemaEmitsZeroCountSummaryReadyInvalidationEvent() async {
        let store = AIAcceptedLearningStore.inMemory(maxRecordCount: 1)
        let collector = SummaryReadyEventCollector()
        _ = store.addSummaryReadyObserver { event in
            collector.record(event)
        }

        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 1),
                schemaID: "double_pinyin",
                rawInput: "dp",
                acceptedText: "DoublePinyin 旧方案",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        collector.reset()

        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 2),
                schemaID: "pinyin_simp",
                rawInput: "ps",
                acceptedText: "PinyinSimp 新方案",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )

        let events = collector.snapshot()
        XCTAssertEqual(events.map(\.schemaID), ["double_pinyin", "pinyin_simp"])
        let evictedEvent = events.first { $0.schemaID == "double_pinyin" }
        XCTAssertEqual(evictedEvent?.acceptedCount, 0)
        XCTAssertEqual(evictedEvent?.historyHash, "")
        XCTAssertEqual(evictedEvent?.termCount, 0)
        XCTAssertEqual(evictedEvent?.recentCommitCount, 0)
    }

    func testMaintenanceRebuildAppliesMaxRecordCountAndClearScrubsEvictedCommits() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
        let feedbackHistoryURL = directory.appendingPathComponent("accepted-ai-feedback.jsonl")
        let feedbackSummaryURL = directory.appendingPathComponent("accepted-ai-feedback-summary.json")
        let feedbackMirrorURL = directory.appendingPathComponent("AI_FEEDBACK.md")
        let lexicalJSONURL = directory.appendingPathComponent("lexical-profile.json")
        let lexicalMarkdownURL = directory.appendingPathComponent("LEXICAL_PROFILE.md")

        let store = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 2
        )
        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 1),
                schemaID: "pinyin_simp",
                rawInput: "one",
                acceptedText: "EvictedAICommit 被淘汰的提交",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 2),
                schemaID: "pinyin_simp",
                rawInput: "two",
                acceptedText: "RetainedAICommitOne 保留提交一",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 3),
                schemaID: "pinyin_simp",
                rawInput: "three",
                acceptedText: "RetainedAICommitTwo 保留提交二",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )

        let evictedCommitsURL = directory.appendingPathComponent("accepted-ai-learning.evicted-commits.json")
        let evictedCommitsContent = try String(contentsOf: evictedCommitsURL, encoding: .utf8)
        XCTAssertFalse(evictedCommitsContent.contains("EvictedAICommit"))
        XCTAssertFalse(evictedCommitsContent.contains("被淘汰的提交"))

        let context = LexicalContextSnapshot(
            terms: [
                LexicalContextTerm(text: "RetainedAICommitOne", score: 1, source: "accepted-ai"),
                LexicalContextTerm(text: "长期高频", score: 0.9, source: "rime-userdb")
            ],
            recentCommits: [
                "EvictedAICommit 被淘汰的提交",
                "RetainedAICommitOne 保留提交一",
                "普通传统输入提交"
            ],
            toneProfile: ToneProfile(codeSwitchingRatio: 0.5),
            sourceSummary: [
                "accepted-ai-summary: terms=1 commits=2 history=abc123",
                "rime-userdb: 1"
            ]
        )
        let profile = PersistentLexicalProfile(
            schemaID: "pinyin_simp",
            rimeSnapshotPath: "/tmp/pinyin_simp.userdb.txt",
            rimeSnapshotModifiedAt: Date(timeIntervalSince1970: 1),
            lexicalContext: context
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(profile).write(to: lexicalJSONURL, options: .atomic)
        try Data(context.markdown.utf8).write(to: lexicalMarkdownURL, options: .atomic)

        let maintenance = AIAcceptedLearningMaintenance(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            feedbackHistoryURL: feedbackHistoryURL,
            feedbackSummaryURL: feedbackSummaryURL,
            feedbackMirrorURL: feedbackMirrorURL,
            lexicalJSONURL: lexicalJSONURL,
            lexicalMarkdownURL: lexicalMarkdownURL,
            maxRecordCount: 1
        )
        let rebuiltStatus = try maintenance.rebuild()
        XCTAssertEqual(rebuiltStatus.history.recordCount, 1)
        XCTAssertEqual(rebuiltStatus.summary.acceptedCount, 1)
        XCTAssertTrue(rebuiltStatus.summary.isCurrentWithHistory)

        _ = try maintenance.clear(confirm: true)
        let scrubbedMarkdown = try String(contentsOf: lexicalMarkdownURL, encoding: .utf8)
        XCTAssertFalse(scrubbedMarkdown.contains("EvictedAICommit 被淘汰的提交"))
        XCTAssertFalse(scrubbedMarkdown.contains("RetainedAICommitOne 保留提交一"))
        XCTAssertFalse(scrubbedMarkdown.contains("RetainedAICommitTwo 保留提交二"))
        XCTAssertTrue(scrubbedMarkdown.contains("普通传统输入提交"))
    }

    func testDelayedSummaryRebuildReloadsCompactedHistoryFromConcurrentStore() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")

        let storeA = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 250_000_000,
            maxRecordCount: 2
        )
        let storeB = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 2
        )

        await storeA.recordAcceptedAI(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 1),
                schemaID: "pinyin_simp",
                rawInput: "one",
                acceptedText: "StaleRecordOne 旧记录一",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        await storeB.recordAcceptedAI(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 2),
                schemaID: "pinyin_simp",
                rawInput: "two",
                acceptedText: "RetainedRecordTwo 保留记录二",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        await storeB.recordAcceptedAI(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 3),
                schemaID: "pinyin_simp",
                rawInput: "three",
                acceptedText: "RetainedRecordThree 保留记录三",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )

        // Wait for storeA's delayed rebuild to fire after storeB already compacted historyURL.
        try await Task.sleep(nanoseconds: 400_000_000)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let persistedSummary = try decoder.decode(
            AIAcceptedLanguageSummary.self,
            from: Data(contentsOf: summaryURL)
        )
        XCTAssertEqual(persistedSummary.acceptedCount, 2)
        XCTAssertFalse(persistedSummary.recentAcceptedCommits.contains("StaleRecordOne 旧记录一"))
        XCTAssertTrue(persistedSummary.recentAcceptedCommits.contains("RetainedRecordTwo 保留记录二"))
        XCTAssertTrue(persistedSummary.recentAcceptedCommits.contains("RetainedRecordThree 保留记录三"))
        XCTAssertEqual(storeA.snapshot()?.historyHash, persistedSummary.historyHash)
    }

    func testMaintenanceClampsMutatedMaxRecordCountToPositiveMinimum() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
        let feedbackHistoryURL = directory.appendingPathComponent("accepted-ai-feedback.jsonl")
        let feedbackSummaryURL = directory.appendingPathComponent("accepted-ai-feedback-summary.json")
        let feedbackMirrorURL = directory.appendingPathComponent("AI_FEEDBACK.md")
        let lexicalJSONURL = directory.appendingPathComponent("lexical-profile.json")
        let lexicalMarkdownURL = directory.appendingPathComponent("LEXICAL_PROFILE.md")

        let store = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 2
        )
        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 1),
                schemaID: "pinyin_simp",
                rawInput: "one",
                acceptedText: "FirstCommit 第一条",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 2),
                schemaID: "pinyin_simp",
                rawInput: "two",
                acceptedText: "SecondCommit 第二条",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )

        var maintenance = AIAcceptedLearningMaintenance(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            feedbackHistoryURL: feedbackHistoryURL,
            feedbackSummaryURL: feedbackSummaryURL,
            feedbackMirrorURL: feedbackMirrorURL,
            lexicalJSONURL: lexicalJSONURL,
            lexicalMarkdownURL: lexicalMarkdownURL,
            maxRecordCount: 2
        )
        maintenance.maxRecordCount = 0
        XCTAssertEqual(maintenance.maxRecordCount, 1)

        let rebuiltStatus = try maintenance.rebuild()
        XCTAssertEqual(rebuiltStatus.history.recordCount, 1)
        XCTAssertEqual(rebuiltStatus.summary.acceptedCount, 1)
        XCTAssertTrue(rebuiltStatus.summary.isCurrentWithHistory)
    }

    func testClearRetainsNewestEvictedCommitWhenEvictionLedgerReachesCapacity() async throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let historyURL = dir.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = dir.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = dir.appendingPathComponent("accepted-ai-learning.md")
        let evictedCommitsURL = dir.appendingPathComponent("accepted-ai-learning.evicted-commits.json")
        let feedbackHistoryURL = dir.appendingPathComponent("accepted-ai-feedback.jsonl")
        let feedbackSummaryURL = dir.appendingPathComponent("accepted-ai-feedback-summary.json")
        let feedbackMirrorURL = dir.appendingPathComponent("accepted-ai-feedback.md")
        let lexicalJSONURL = dir.appendingPathComponent("lexical-profile.json")
        let lexicalMarkdownURL = dir.appendingPathComponent("lexical-profile.md")

        let prefilledLedger = (0..<4_096).map { index in
            String(format: "ffff%060x", index)
        }
        try JSONEncoder().encode(prefilledLedger).write(to: evictedCommitsURL, options: .atomic)

        let store = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 1
        )

        let evictedCommitText = "EvictedNewestLedgerCommit 最新淘汰提交"
        let retainedCommitText = "RetainedLatestCommit 保留提交"
        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                schemaID: "luna_pinyin",
                rawInput: "one",
                acceptedText: evictedCommitText,
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                schemaID: "luna_pinyin",
                rawInput: "two",
                acceptedText: retainedCommitText,
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )

        let context = LexicalContextSnapshot(
            terms: [
                LexicalContextTerm(text: "EvictedNewestLedgerCommit", score: 0.9, source: "accepted-ai")
            ],
            recentCommits: [
                evictedCommitText,
                retainedCommitText,
                "NormalUserCommit 普通提交"
            ],
            toneProfile: ToneProfile(),
            sourceSummary: [
                "accepted-ai-summary: terms=1 commits=2 history=deadbeef"
            ]
        )
        let profile = PersistentLexicalProfile(
            schemaID: "luna_pinyin",
            rimeSnapshotPath: nil,
            rimeSnapshotModifiedAt: nil,
            lexicalContext: context
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(profile).write(to: lexicalJSONURL, options: .atomic)
        try Data(context.markdown.utf8).write(to: lexicalMarkdownURL, options: .atomic)

        let maintenance = AIAcceptedLearningMaintenance(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            feedbackHistoryURL: feedbackHistoryURL,
            feedbackSummaryURL: feedbackSummaryURL,
            feedbackMirrorURL: feedbackMirrorURL,
            lexicalJSONURL: lexicalJSONURL,
            lexicalMarkdownURL: lexicalMarkdownURL,
            maxRecordCount: 1
        )
        _ = try maintenance.clear(confirm: true)

        let scrubbedMarkdown = try String(contentsOf: lexicalMarkdownURL, encoding: .utf8)
        XCTAssertFalse(scrubbedMarkdown.contains(evictedCommitText))
        XCTAssertFalse(scrubbedMarkdown.contains(retainedCommitText))
        XCTAssertTrue(scrubbedMarkdown.contains("NormalUserCommit 普通提交"))
    }
}

private final class SummaryReadyEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [AIAcceptedLearningSummaryReadyEvent] = []

    func record(_ event: AIAcceptedLearningSummaryReadyEvent) {
        lock.withLock {
            events.append(event)
        }
    }

    func reset() {
        lock.withLock {
            events.removeAll()
        }
    }

    func snapshot() -> [AIAcceptedLearningSummaryReadyEvent] {
        lock.withLock {
            events
        }
    }
}

private func temporaryDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("KnowTypeAIAcceptedLearningCapTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
