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
        let preCompactionSummary = try XCTUnwrap(
            AIAcceptedLearningStore.buildSummary(
                records: records,
                generatedAt: Date(timeIntervalSince1970: 10)
            )
        )
        try encoder.encode(preCompactionSummary).write(to: summaryURL, options: .atomic)
        try Data(AIAcceptedLearningStore.renderMarkdown(preCompactionSummary).utf8)
            .write(to: mirrorURL, options: .atomic)

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

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let persistedSummary = try decoder.decode(
            AIAcceptedLanguageSummary.self,
            from: Data(contentsOf: summaryURL)
        )
        XCTAssertEqual(persistedSummary.acceptedCount, 2)
        XCTAssertEqual(persistedSummary.historyHash, summary.historyHash)
        XCTAssertFalse(persistedSummary.termProfile.contains { $0.text == "InitToken1" })
        let persistedMirror = try String(contentsOf: mirrorURL, encoding: .utf8)
        XCTAssertTrue(persistedMirror.contains("Retained history (a sliding window of the latest 2 records"))
        XCTAssertFalse(persistedMirror.contains("InitToken1"))
        XCTAssertTrue(persistedMirror.contains("InitToken4"))
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

        let oldestSurvivingPreClearCommitText = "OldestPreClearEvictedCommit 最早存活淘汰提交"
        let oldestSurvivingPreClearDigest = acceptedLearningCommitTextDigest(oldestSurvivingPreClearCommitText)
        let prefilledLedger = [String(format: "ffff%060x", 0), oldestSurvivingPreClearDigest] + (2..<4_096).map { index in
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
        let mirrorMarkdown = try String(contentsOf: mirrorURL, encoding: .utf8)
        XCTAssertTrue(mirrorMarkdown.contains("Retained history (a sliding window of the latest 1 record"))
        XCTAssertFalse(mirrorMarkdown.contains("Full history stays local"))
        _ = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 500
        )
        let refreshedMirrorMarkdown = try String(contentsOf: mirrorURL, encoding: .utf8)
        XCTAssertTrue(refreshedMirrorMarkdown.contains("Retained history (a sliding window of the latest 500 records"))

        let context = LexicalContextSnapshot(
            terms: [
                LexicalContextTerm(text: "普通词条", score: 0.9, source: "rime-userdb")
            ],
            recentCommits: [
                oldestSurvivingPreClearCommitText,
                evictedCommitText,
                retainedCommitText,
                "NormalUserCommit 普通提交"
            ],
            toneProfile: ToneProfile(),
            sourceSummary: [
                "rime-userdb: 1"
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

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let scrubbedProfile = try decoder.decode(
            PersistentLexicalProfile.self,
            from: Data(contentsOf: lexicalJSONURL)
        )
        XCTAssertEqual(scrubbedProfile.lexicalContext.recentCommits, ["NormalUserCommit 普通提交"])
        let scrubbedMarkdown = try String(contentsOf: lexicalMarkdownURL, encoding: .utf8)
        XCTAssertFalse(scrubbedMarkdown.contains(oldestSurvivingPreClearCommitText))
        XCTAssertFalse(scrubbedMarkdown.contains(evictedCommitText))
        XCTAssertFalse(scrubbedMarkdown.contains(retainedCommitText))
        XCTAssertTrue(scrubbedMarkdown.contains("NormalUserCommit 普通提交"))
    }

    func testClearRetryScrubsEvictedAndRetainedCommitsAfterLexicalWriteFailure() async throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let historyURL = dir.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = dir.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = dir.appendingPathComponent("accepted-ai-learning.md")
        let evictedCommitsURL = dir.appendingPathComponent("accepted-ai-learning.evicted-commits.json")
        let feedbackHistoryURL = dir.appendingPathComponent("accepted-ai-feedback.jsonl")
        let feedbackSummaryURL = dir.appendingPathComponent("accepted-ai-feedback-summary.json")
        let feedbackMirrorURL = dir.appendingPathComponent("accepted-ai-feedback.md")
        let lexicalDir = dir.appendingPathComponent("lexical", isDirectory: true)
        try FileManager.default.createDirectory(at: lexicalDir, withIntermediateDirectories: true)
        let lexicalJSONURL = lexicalDir.appendingPathComponent("lexical-profile.json")
        let lexicalMarkdownURL = lexicalDir.appendingPathComponent("lexical-profile.md")

        let store = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 1
        )

        let evictedCommitText = "EvictedBeforeFailedScrub 淘汰提交"
        let retainedCommitText = "RetainedBeforeFailedScrub 保留提交"
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
                LexicalContextTerm(text: "普通词条", score: 0.9, source: "rime-userdb")
            ],
            recentCommits: [
                evictedCommitText,
                retainedCommitText,
                "NormalUserCommit 普通提交"
            ],
            toneProfile: ToneProfile(),
            sourceSummary: [
                "rime-userdb: 1"
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

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: lexicalDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: lexicalDir.path)
        }

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

        XCTAssertThrowsError(try maintenance.clear(confirm: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: evictedCommitsURL.path))

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: lexicalDir.path)
        _ = try maintenance.clear(confirm: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: evictedCommitsURL.path))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let scrubbedProfile = try decoder.decode(
            PersistentLexicalProfile.self,
            from: Data(contentsOf: lexicalJSONURL)
        )
        XCTAssertEqual(scrubbedProfile.lexicalContext.recentCommits, ["NormalUserCommit 普通提交"])
    }

    func testFailedClearPinsScrubEntriesAcrossFurtherCompactionAndReload() async throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let historyURL = dir.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = dir.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = dir.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
        let evictedURL = dir.appendingPathComponent("accepted-ai-learning.evicted-commits.json")
        let lexicalDir = dir.appendingPathComponent("lexical", isDirectory: true)
        try FileManager.default.createDirectory(at: lexicalDir, withIntermediateDirectories: true)
        let lexicalJSONURL = lexicalDir.appendingPathComponent("lexical-profile.json")
        let lexicalMarkdownURL = lexicalDir.appendingPathComponent("LEXICAL_PROFILE.md")
        let oldCommit = "OldEvictedCommit " + String(repeating: "old accepted text ", count: 5)
        let activeCommit = "ActiveBeforeClear " + String(repeating: "active accepted text ", count: 5)
        let oldVariants = [oldCommit, String(oldCommit.prefix(48)) + "..."]
        let activeVariants = [activeCommit, String(activeCommit.prefix(48)) + "..."]
        let prefilledLedger = oldVariants.map(acceptedLearningCommitTextDigest) + (2..<4_096).map {
            String(format: "%064x", $0)
        }
        try JSONEncoder().encode(prefilledLedger).write(to: evictedURL, options: .atomic)
        let store = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0
        )
        await store.recordAcceptedAI(AIAcceptedLearningRecord(
            schemaID: "pinyin_simp",
            acceptedText: activeCommit,
            provider: "ai-test",
            contextVersion: "test",
            candidateSource: "ai:ai-test",
            extractedTerms: []
        ))
        let context = LexicalContextSnapshot(
            terms: [LexicalContextTerm(text: "NormalTerm", score: 0.9, source: "rime-userdb")],
            recentCommits: oldVariants + activeVariants + ["Normal user commit"],
            toneProfile: ToneProfile(),
            sourceSummary: ["rime-userdb: 1"]
        )
        let profile = PersistentLexicalProfile(
            schemaID: "pinyin_simp",
            rimeSnapshotPath: nil,
            rimeSnapshotModifiedAt: nil,
            lexicalContext: context
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let originalProfile = try encoder.encode(profile)
        try originalProfile.write(to: lexicalJSONURL, options: .atomic)
        try Data(context.markdown.utf8).write(to: lexicalMarkdownURL, options: .atomic)
        let maintenance = AIAcceptedLearningMaintenance(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            feedbackHistoryURL: dir.appendingPathComponent("feedback.jsonl"),
            feedbackSummaryURL: dir.appendingPathComponent("feedback-summary.json"),
            feedbackMirrorURL: dir.appendingPathComponent("FEEDBACK.md"),
            lexicalJSONURL: lexicalJSONURL,
            lexicalMarkdownURL: lexicalMarkdownURL,
            fileManager: DirectoryWriteFailingFileManager(blockedDirectory: lexicalDir)
        )
        XCTAssertThrowsError(try maintenance.clear(confirm: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyURL.path))
        XCTAssertEqual(try Data(contentsOf: lexicalJSONURL), originalProfile)
        let pinnedMarker = try Data(contentsOf: maintenance.clearMarkerURL)
        let marker = try XCTUnwrap(JSONSerialization.jsonObject(with: pinnedMarker) as? [String: Any])
        let pinnedEntries = Set(try XCTUnwrap(marker["pendingEvictedCommitEntries"] as? [String]))
        XCTAssertTrue(Set(prefilledLedger).isSubset(of: pinnedEntries))
        XCTAssertTrue(Set(activeVariants.map(acceptedLearningCommitTextDigest)).isSubset(of: pinnedEntries))
        XCTAssertFalse(String(decoding: pinnedMarker, as: UTF8.self).contains("OldEvictedCommit"))

        for index in 1...501 {
            await store.recordAcceptedAI(AIAcceptedLearningRecord(
                schemaID: "pinyin_simp",
                acceptedText: "AfterFailedClear\(index) " + String(repeating: "long accepted text ", count: 4),
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test",
                extractedTerms: []
            ))
        }
        XCTAssertEqual(store.allRecords().count, 500)
        let rotatedLedger = try JSONDecoder().decode([String].self, from: Data(contentsOf: evictedURL))
        XCTAssertEqual(rotatedLedger.count, 4_096)
        XCTAssertFalse(rotatedLedger.contains(acceptedLearningCommitTextDigest(oldCommit)))
        XCTAssertEqual(try Data(contentsOf: maintenance.clearMarkerURL), pinnedMarker)

        // A fresh maintenance value must recover solely from persisted retry state.
        let retryMaintenance = AIAcceptedLearningMaintenance(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            feedbackHistoryURL: maintenance.feedbackHistoryURL,
            feedbackSummaryURL: maintenance.feedbackSummaryURL,
            feedbackMirrorURL: maintenance.feedbackMirrorURL,
            lexicalJSONURL: lexicalJSONURL,
            lexicalMarkdownURL: lexicalMarkdownURL
        )
        _ = try retryMaintenance.clear(confirm: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: evictedURL.path))
        let completedMarker = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: maintenance.clearMarkerURL)) as? [String: Any]
        )
        XCTAssertNil(completedMarker["pendingEvictedCommitEntries"])
        let reloadedProfile = LexicalProfileStore(jsonURL: lexicalJSONURL, markdownURL: lexicalMarkdownURL)
        XCTAssertEqual(reloadedProfile.currentSnapshot()?.recentCommits, ["Normal user commit"])
        XCTAssertTrue(reloadedProfile.currentSnapshot()?.terms.contains { $0.text == "NormalTerm" } == true)
        let markdown = try String(contentsOf: lexicalMarkdownURL, encoding: .utf8)
        XCTAssertFalse(markdown.contains("OldEvictedCommit"))
        XCTAssertFalse(markdown.contains("ActiveBeforeClear"))
        let reloadedLearning = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0
        )
        XCTAssertNil(reloadedLearning.snapshot())
    }

    func testFailedAppendDeliversPeerInvalidationsOnceOutsideLocks() async throws {
        for capacity in [2, 3] {
            let dir = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }
            let historyURL = dir.appendingPathComponent("accepted-ai-learning.jsonl")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            func record(_ text: String, schemaID: String) -> AIAcceptedLearningRecord {
                AIAcceptedLearningRecord(
                    schemaID: schemaID,
                    acceptedText: text,
                    provider: "ai-test",
                    contextVersion: "test",
                    candidateSource: "ai:ai-test"
                )
            }
            let removed = record("Removed peer commit", schemaID: "removed")
            let retained = record("Retained peer commit", schemaID: "surviving")
            let added = record("Added peer commit", schemaID: "surviving")
            let initial = try [removed, retained].reduce(into: Data()) { data, record in
                data.append(try encoder.encode(record))
                data.append(0x0A)
            }
            try initial.write(to: historyURL, options: .atomic)
            let diagnostics = DiagnosticEventCollector()
            let store = AIAcceptedLearningStore(
                historyURL: historyURL,
                summaryURL: nil,
                mirrorURL: nil,
                diagnosticSink: diagnostics,
                summaryDelayNanoseconds: 0,
                maxRecordCount: capacity
            )
            let events = SummaryReadyEventCollector()
            let observerID = store.addSummaryReadyObserver { event in
                events.record(event)
                // Reentrant reads exercise both the store lock and the file lock.
                let snapshot = store.snapshot(schemaID: event.schemaID)
                XCTAssertEqual(snapshot?.acceptedCount ?? 0, event.acceptedCount)
                XCTAssertEqual(snapshot?.historyHash ?? "", event.historyHash)
                _ = store.allRecords()
            }
            defer { store.removeSummaryReadyObserver(observerID) }

            // Model another process's already-compacted, within-capacity history.
            let peerHistory = try [retained, added].reduce(into: Data()) { data, record in
                data.append(try encoder.encode(record))
                data.append(0x0A)
            }
            try peerHistory.write(to: historyURL, options: .atomic)
            var failedRecord = record("Unencodable local append", schemaID: "local")
            failedRecord.extractedTerms = [LexicalContextTerm(text: "InvalidScore", score: .nan, source: "accepted-ai")]
            await store.recordAcceptedAI(failedRecord)

            XCTAssertTrue(diagnostics.reasons().contains { $0.hasPrefix("accepted_learning_write_failed:") })
            XCTAssertEqual(try Data(contentsOf: historyURL), peerHistory)
            let invalidations = events.snapshot()
            XCTAssertEqual(invalidations.map(\.schemaID), ["removed", "surviving"])
            XCTAssertEqual(invalidations.map(\.acceptedCount), [0, 2])
            XCTAssertEqual(invalidations.last?.historyHash, AIAcceptedLearningStore.historyHash([retained, added]))
            for _ in 0..<3 {
                XCTAssertNil(store.snapshot(schemaID: "removed"))
                XCTAssertEqual(store.snapshot(schemaID: "surviving")?.acceptedCount, 2)
            }
            XCTAssertEqual(events.snapshot(), invalidations)
            await store.recordAcceptedAI(record("Recovered local append", schemaID: "local"))
            XCTAssertEqual(store.allRecords().count, capacity)
            XCTAssertEqual(events.snapshot().filter { $0.schemaID == "removed" }.count, 1)
        }
    }

    func testCompactionInPeerStoreInvalidatesLiveStoreSchemaSnapshotAndNotifiesObserver() async throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let historyURL = dir.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = dir.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = dir.appendingPathComponent("ACCEPTED_AI_LEARNING.md")

        let storeA = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 1
        )
        let storeB = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 1
        )

        let collectorA = SummaryReadyEventCollector()
        _ = storeA.addSummaryReadyObserver { event in
            collectorA.record(event)
        }

        await storeA.recordAcceptedAI(
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
        XCTAssertNotNil(storeA.snapshot(schemaID: "double_pinyin"))
        collectorA.reset()

        await storeB.recordAcceptedAI(
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

        let eventsOnA = collectorA.snapshot()
        XCTAssertEqual(eventsOnA.map(\.schemaID), ["double_pinyin", "pinyin_simp"])
        let evictedEventOnA = eventsOnA.first { $0.schemaID == "double_pinyin" }
        XCTAssertEqual(evictedEventOnA?.acceptedCount, 0)
        XCTAssertEqual(evictedEventOnA?.historyHash, "")
        XCTAssertNil(storeA.snapshot(schemaID: "double_pinyin"))
        XCTAssertEqual(storeA.snapshot(schemaID: "pinyin_simp")?.acceptedCount, 1)
    }

    func testClearPreservesEvictionLedgerWhenCanonicalLexicalProfileIsUnreadableAndRefusesMalformedLedger() async throws {
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

        let store = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 1
        )
        let evictedCommitText = "EvictedUnreadableProfileCommit 淘汰提交"
        let retainedCommitText = "RetainedUnreadableProfileCommit 保留提交"
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
                LexicalContextTerm(text: "普通词条", score: 0.9, source: "rime-userdb")
            ],
            recentCommits: [
                evictedCommitText,
                retainedCommitText,
                "NormalUserCommit 普通提交"
            ],
            toneProfile: ToneProfile(),
            sourceSummary: ["rime-userdb: 1"]
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

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lexicalJSONURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: lexicalJSONURL.path)
        }

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

        XCTAssertThrowsError(try maintenance.clear(confirm: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: evictedCommitsURL.path))
        XCTAssertNil(store.snapshot())

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: lexicalJSONURL.path)
        _ = try maintenance.clear(confirm: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: evictedCommitsURL.path))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let scrubbedProfile = try decoder.decode(
            PersistentLexicalProfile.self,
            from: Data(contentsOf: lexicalJSONURL)
        )
        XCTAssertEqual(scrubbedProfile.lexicalContext.recentCommits, ["NormalUserCommit 普通提交"])

        try Data("{corrupt-json".utf8).write(to: evictedCommitsURL, options: .atomic)
        XCTAssertThrowsError(try maintenance.clear(confirm: true))
        XCTAssertEqual(try String(contentsOf: evictedCommitsURL, encoding: .utf8), "{corrupt-json")
    }

    func testTransientHistoryReadFailureRetainsCachedSummariesAndRetriesOnceReadable() async throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let historyURL = dir.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = dir.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = dir.appendingPathComponent("ACCEPTED_AI_LEARNING.md")

        let writer = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 5
        )
        let reader = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 5
        )

        await writer.recordAcceptedAI(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 1),
                schemaID: "pinyin_simp",
                rawInput: "one",
                acceptedText: "FirstCachedRecord 第一条",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        XCTAssertEqual(reader.snapshot(schemaID: "pinyin_simp")?.acceptedCount, 1)

        let record2 = AIAcceptedLearningRecord(
            acceptedAt: Date(timeIntervalSince1970: 2),
            schemaID: "pinyin_simp",
            rawInput: "two",
            acceptedText: "SecondReloadedRecord 第二条",
            provider: "ai-test",
            contextVersion: "test",
            candidateSource: "ai:ai-test"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let existingContent = try String(contentsOf: historyURL, encoding: .utf8)
        let line2 = try XCTUnwrap(String(data: encoder.encode(record2), encoding: .utf8)) + "\n"
        try (existingContent + line2).write(to: historyURL, atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: historyURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
        }

        XCTAssertEqual(reader.snapshot(schemaID: "pinyin_simp")?.acceptedCount, 1)
        XCTAssertEqual(reader.allRecords().count, 1)

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
        XCTAssertEqual(reader.snapshot(schemaID: "pinyin_simp")?.acceptedCount, 2)
        XCTAssertEqual(reader.allRecords().count, 2)

        let lockURL = dir.appendingPathComponent("test-optimistic.lock")
        var bodyCalls = 0
        var commitCalls = 0
        let committedValue: Int = try withExistingAcceptedLearningFileLock(
            lockURL: lockURL,
            {
                bodyCalls += 1
                if bodyCalls == 1 {
                    FileManager.default.createFile(atPath: lockURL.path, contents: nil)
                }
                return bodyCalls
            },
            commit: { candidate in
                commitCalls += 1
                return candidate * 10
            }
        )
        XCTAssertEqual(bodyCalls, 2)
        XCTAssertEqual(commitCalls, 1)
        XCTAssertEqual(committedValue, 20)

        let unwritableDir = dir.appendingPathComponent("unwritable-startup", isDirectory: true)
        try FileManager.default.createDirectory(at: unwritableDir, withIntermediateDirectories: true)
        let deferredHistoryURL = unwritableDir.appendingPathComponent("accepted-ai-learning.jsonl")
        let deferredSummaryURL = unwritableDir.appendingPathComponent("accepted-ai-summary.json")
        let deferredMirrorURL = unwritableDir.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
        let deferredEvictedURL = unwritableDir.appendingPathComponent("accepted-ai-learning.evicted-commits.json")
        let line1 = try XCTUnwrap(
            String(
                data: encoder.encode(
                    AIAcceptedLearningRecord(
                        acceptedAt: Date(timeIntervalSince1970: 1),
                        schemaID: "pinyin_simp",
                        rawInput: "one",
                        acceptedText: "DeferredEvictedOne 待淘汰一",
                        provider: "ai-test",
                        contextVersion: "test",
                        candidateSource: "ai:ai-test"
                    )
                ),
                encoding: .utf8
            )
        )
        try (line1 + "\n" + line2).write(to: deferredHistoryURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: unwritableDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unwritableDir.path)
        }

        let diagnostics = DiagnosticEventCollector()
        let deferredStore = AIAcceptedLearningStore(
            historyURL: deferredHistoryURL,
            summaryURL: deferredSummaryURL,
            mirrorURL: deferredMirrorURL,
            diagnosticSink: diagnostics,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 1
        )
        let initialRepairFailures = diagnostics.reasons().filter {
            $0.hasPrefix("accepted_learning_summary_repair_failed:")
        }
        XCTAssertEqual(initialRepairFailures.count, 1)
        XCTAssertEqual(deferredStore.snapshot()?.acceptedCount, 1)
        XCTAssertEqual(deferredStore.snapshot(schemaID: "pinyin_simp")?.acceptedCount, 1)
        XCTAssertEqual(deferredStore.allRecords().count, 1)
        XCTAssertEqual(
            diagnostics.reasons().filter {
                $0.hasPrefix("accepted_learning_summary_repair_failed:")
                    || $0.hasPrefix("accepted_learning_clear_sync_failed:")
            }.count,
            1
        )
        XCTAssertEqual(
            try String(contentsOf: deferredHistoryURL, encoding: .utf8).split(whereSeparator: \.isNewline).count,
            2
        )

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unwritableDir.path)
        XCTAssertEqual(deferredStore.snapshot()?.acceptedCount, 1)
        XCTAssertEqual(
            try String(contentsOf: deferredHistoryURL, encoding: .utf8).split(whereSeparator: \.isNewline).count,
            1
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: deferredEvictedURL.path))

        let mirrorDir = dir.appendingPathComponent("unwritable-mirror", isDirectory: true)
        try FileManager.default.createDirectory(at: mirrorDir, withIntermediateDirectories: true)
        let isolatedMirrorURL = mirrorDir.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
        try Data("# Stale Mirror\n".utf8).write(to: isolatedMirrorURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: mirrorDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: mirrorDir.path)
        }

        let mirrorRepairStore = AIAcceptedLearningStore(
            historyURL: deferredHistoryURL,
            summaryURL: deferredSummaryURL,
            mirrorURL: isolatedMirrorURL,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 5
        )
        let mirrorRepairEvents = SummaryReadyEventCollector()
        _ = mirrorRepairStore.addSummaryReadyObserver { event in
            mirrorRepairEvents.record(event)
        }
        await mirrorRepairStore.recordAcceptedAI(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 3),
                schemaID: "pinyin_simp",
                rawInput: "three",
                acceptedText: "AppendedWhileMirrorUnwritable 第三条",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        XCTAssertEqual(mirrorRepairStore.allRecords().count, 2)
        XCTAssertEqual(mirrorRepairStore.snapshot()?.acceptedCount, 2)
        XCTAssertEqual(mirrorRepairEvents.snapshot(), [])
        XCTAssertEqual(
            try String(contentsOf: deferredHistoryURL, encoding: .utf8).split(whereSeparator: \.isNewline).count,
            2
        )

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: mirrorDir.path)
        XCTAssertEqual(mirrorRepairStore.snapshot()?.acceptedCount, 2)
        XCTAssertEqual(mirrorRepairEvents.snapshot().map(\.schemaID), ["pinyin_simp"])
        XCTAssertEqual(mirrorRepairEvents.snapshot().last?.acceptedCount, 2)
        XCTAssertTrue(
            try String(contentsOf: isolatedMirrorURL, encoding: .utf8)
                .contains("Accepted count: 2")
        )

        let missingMirrorURL = mirrorDir.appendingPathComponent("MISSING_MIRROR.md")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: mirrorDir.path)
        let partialCompactionStore = AIAcceptedLearningStore(
            historyURL: deferredHistoryURL,
            summaryURL: deferredSummaryURL,
            mirrorURL: missingMirrorURL,
            summaryDelayNanoseconds: 0,
            maxRecordCount: 1
        )
        XCTAssertEqual(
            try String(contentsOf: deferredHistoryURL, encoding: .utf8).split(whereSeparator: \.isNewline).count,
            1
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingMirrorURL.path))

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: mirrorDir.path)
        XCTAssertEqual(partialCompactionStore.snapshot()?.acceptedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: missingMirrorURL.path))

        let extraRecordLine = try encoder.encode(
            AIAcceptedLearningRecord(
                acceptedAt: Date(timeIntervalSince1970: 4),
                schemaID: "pinyin_simp",
                rawInput: "four",
                acceptedText: "ExternalOverflow 第四条",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        let handle = try FileHandle(forWritingTo: deferredHistoryURL)
        try handle.seekToEnd()
        var lineWithNewline = extraRecordLine
        lineWithNewline.append(0x0A)
        try handle.write(contentsOf: lineWithNewline)
        try handle.close()
        XCTAssertEqual(
            try String(contentsOf: deferredHistoryURL, encoding: .utf8).split(whereSeparator: \.isNewline).count,
            2
        )

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: unwritableDir.path)
        XCTAssertEqual(partialCompactionStore.snapshot()?.acceptedCount, 1)
        XCTAssertEqual(partialCompactionStore.allRecords().map(\.rawInput), ["four"])
        XCTAssertEqual(
            try String(contentsOf: deferredHistoryURL, encoding: .utf8).split(whereSeparator: \.isNewline).count,
            2
        )

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unwritableDir.path)
        XCTAssertEqual(partialCompactionStore.snapshot()?.acceptedCount, 1)
        XCTAssertEqual(
            try String(contentsOf: deferredHistoryURL, encoding: .utf8).split(whereSeparator: \.isNewline).count,
            1
        )
    }
}

private final class DiagnosticEventCollector: AIRecommendationDiagnosticSink, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [AIRecommendationDiagnosticEvent] = []

    func record(_ event: AIRecommendationDiagnosticEvent) {
        lock.withLock {
            events.append(event)
        }
    }

    func reasons() -> [String] {
        lock.withLock {
            events.compactMap(\.reason)
        }
    }
}

private final class DirectoryWriteFailingFileManager: FileManager, @unchecked Sendable {
    private let blockedDirectory: URL

    init(blockedDirectory: URL) {
        self.blockedDirectory = blockedDirectory
        super.init()
    }

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        if url.standardizedFileURL.path == blockedDirectory.standardizedFileURL.path {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
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
