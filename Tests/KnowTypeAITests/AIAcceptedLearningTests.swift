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
}

private func temporaryDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("KnowTypeAIAcceptedLearningCapTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
