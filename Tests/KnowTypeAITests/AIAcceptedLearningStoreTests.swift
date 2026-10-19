import Foundation
import XCTest
@testable import KnowTypeAI

final class AIAcceptedLearningStoreTests: XCTestCase {
    func testAppendSeparatesValidFinalRecordWithoutLineFeed() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let records = acceptedHistoryRecords(3)
        var original = try acceptedHistoryData(Array(records.prefix(2)))
        original.removeLast()
        XCTAssertEqual(original.last, 0x7D)
        try original.write(to: historyURL, options: .atomic)
        let store = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: nil,
            mirrorURL: nil,
            summaryDelayNanoseconds: 0
        )
        XCTAssertEqual(store.snapshot()?.acceptedCount, 2)

        await store.recordAcceptedAI(records[2])

        let appended = try Data(contentsOf: historyURL)
        XCTAssertEqual(Data(appended.prefix(original.count)), original)
        XCTAssertEqual(appended.dropFirst(original.count).first, 0x0A)
        let lines = appended.split(separator: 0x0A)
        XCTAssertEqual(lines.count, 3)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try lines.map { try decoder.decode(AIAcceptedLearningRecord.self, from: Data($0)) }
        XCTAssertEqual(decoded.map(\.textHash), records.map(\.textHash))
        let reloaded = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: nil,
            mirrorURL: nil,
            summaryDelayNanoseconds: 0
        )
        XCTAssertEqual(reloaded.allRecords().map(\.textHash), records.map(\.textHash))
        XCTAssertEqual(reloaded.snapshot()?.acceptedCount, 3)
    }

    func testAppendPreservesTruncatedFinalRecordWithoutLineFeed() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let records = acceptedHistoryRecords(3)
        let firstRow = try acceptedHistoryData([records[0]])
        try firstRow.write(to: historyURL, options: .atomic)
        let diagnostics = RecordingDiagnosticSink()
        let store = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: nil,
            mirrorURL: nil,
            diagnosticSink: diagnostics,
            summaryDelayNanoseconds: 0
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var truncatedRow = try encoder.encode(records[1])
        XCTAssertEqual(truncatedRow.removeLast(), 0x7D)
        var original = firstRow
        original.append(truncatedRow)
        XCTAssertNotEqual(original.last, 0x0A)
        try original.write(to: historyURL, options: .atomic)

        await store.recordAcceptedAI(records[2])

        XCTAssertEqual(try Data(contentsOf: historyURL), original)
        XCTAssertEqual(store.allRecords().map(\.textHash), [records[0].textHash])
        XCTAssertTrue(diagnostics.events.contains { $0.reason?.hasPrefix("accepted_learning_write_failed:") == true })
        let reloaded = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: nil,
            mirrorURL: nil,
            summaryDelayNanoseconds: 0
        )
        _ = reloaded.snapshot()
        XCTAssertEqual(try Data(contentsOf: historyURL), original)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("accepted-ai-learning.evicted-commits.json").path
        ))
    }

    func testAppendRefusesUndecodableHistoryRowsAndRecoversAfterRepair() async throws {
        for undecodableRow in try undecodableHistoryRows() {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
            let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
            let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
            let records = acceptedHistoryRecords(501)
            let validHistory = try acceptedHistoryData(Array(records.prefix(500)))
            try validHistory.write(to: historyURL, options: .atomic)
            let diagnostics = RecordingDiagnosticSink()
            let store = AIAcceptedLearningStore(
                historyURL: historyURL,
                summaryURL: summaryURL,
                mirrorURL: mirrorURL,
                diagnosticSink: diagnostics,
                summaryDelayNanoseconds: 0
            )
            XCTAssertEqual(store.snapshot()?.acceptedCount, 500)
            var original = validHistory
            original.append(undecodableRow)
            original.append(0x0A)
            try original.write(to: historyURL, options: .atomic)

            await store.recordAcceptedAI(records[500])

            XCTAssertEqual(try Data(contentsOf: historyURL), original)
            XCTAssertEqual(store.snapshot()?.acceptedCount, 500)
            XCTAssertEqual(store.allRecords().map(\.textHash), records.prefix(500).map(\.textHash))
            XCTAssertFalse(FileManager.default.fileExists(atPath: summaryURL.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: mirrorURL.path))
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("accepted-ai-learning.evicted-commits.json").path
            ))
            XCTAssertTrue(diagnostics.events.contains { $0.reason?.hasPrefix("accepted_learning_write_failed:") == true })

            // An explicit external repair removes only the incompatible row.
            try validHistory.write(to: historyURL, options: .atomic)
            await store.recordAcceptedAI(records[500])
            let expectedHashes = records.suffix(500).map(\.textHash)
            XCTAssertEqual(store.allRecords().map(\.textHash), expectedHashes)
            XCTAssertEqual(store.snapshot()?.acceptedCount, 500)
            let reloaded = AIAcceptedLearningStore(
                historyURL: historyURL,
                summaryURL: summaryURL,
                mirrorURL: mirrorURL,
                summaryDelayNanoseconds: 0
            )
            XCTAssertEqual(reloaded.allRecords().map(\.textHash), expectedHashes)
        }
    }

    func testStartupCapPreservesUndecodableHistoryBytesAndRetriesAfterRepair() throws {
        for undecodableRow in try undecodableHistoryRows() {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
            let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
            let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
            let records = acceptedHistoryRecords(501)
            let validHistory = try acceptedHistoryData(records)
            var original = validHistory
            original.append(undecodableRow)
            original.append(0x0A)
            try original.write(to: historyURL, options: .atomic)
            let diagnostics = RecordingDiagnosticSink()
            let store = AIAcceptedLearningStore(
                historyURL: historyURL,
                summaryURL: summaryURL,
                mirrorURL: mirrorURL,
                diagnosticSink: diagnostics,
                summaryDelayNanoseconds: 0
            )
            _ = store.snapshot()
            XCTAssertEqual(try Data(contentsOf: historyURL), original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: summaryURL.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: mirrorURL.path))
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("accepted-ai-learning.evicted-commits.json").path
            ))
            XCTAssertTrue(diagnostics.events.contains {
                $0.reason?.hasPrefix("accepted_learning_summary_repair_failed:") == true
            })

            try validHistory.write(to: historyURL, options: .atomic)
            XCTAssertEqual(store.snapshot()?.acceptedCount, 500)
            XCTAssertEqual(store.allRecords().map(\.textHash), records.suffix(500).map(\.textHash))
            let compacted = try String(contentsOf: historyURL, encoding: .utf8)
            XCTAssertEqual(compacted.split(whereSeparator: \.isNewline).count, 500)
            XCTAssertTrue(FileManager.default.fileExists(atPath: summaryURL.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: mirrorURL.path))
        }
    }

    func testMaintenanceRebuildRefusesUndecodableHistoryRowsBeforeAnyWrite() throws {
        for recordCount in [1, 501] {
            for undecodableRow in try undecodableHistoryRows() {
                let directory = temporaryDirectory()
                defer { try? FileManager.default.removeItem(at: directory) }
                let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
                let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
                let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
                let records = acceptedHistoryRecords(recordCount)
                let validHistory = try acceptedHistoryData(records)
                var original = validHistory
                original.append(undecodableRow)
                original.append(0x0A)
                try original.write(to: historyURL, options: .atomic)
                let summaryBytes = Data("preexisting summary bytes".utf8)
                let mirrorBytes = Data("preexisting mirror bytes".utf8)
                try summaryBytes.write(to: summaryURL, options: .atomic)
                try mirrorBytes.write(to: mirrorURL, options: .atomic)
                let maintenance = AIAcceptedLearningMaintenance(
                    historyURL: historyURL,
                    summaryURL: summaryURL,
                    mirrorURL: mirrorURL,
                    feedbackHistoryURL: directory.appendingPathComponent("feedback.jsonl"),
                    feedbackSummaryURL: directory.appendingPathComponent("feedback-summary.json"),
                    feedbackMirrorURL: directory.appendingPathComponent("FEEDBACK.md"),
                    lexicalJSONURL: directory.appendingPathComponent("lexical-profile.json"),
                    lexicalMarkdownURL: directory.appendingPathComponent("LEXICAL_PROFILE.md")
                )

                XCTAssertTrue(maintenance.status().warnings.contains("invalid_history_lines:1"))
                XCTAssertThrowsError(try maintenance.rebuild()) { error in
                    XCTAssertEqual(error as? AIAcceptedLearningMaintenance.Error, .undecodableHistoryRows)
                }
                XCTAssertEqual(try Data(contentsOf: historyURL), original)
                XCTAssertEqual(try Data(contentsOf: summaryURL), summaryBytes)
                XCTAssertEqual(try Data(contentsOf: mirrorURL), mirrorBytes)
                XCTAssertFalse(FileManager.default.fileExists(atPath: maintenance.evictedCommitsURL.path))
                XCTAssertFalse(FileManager.default.fileExists(atPath: maintenance.feedbackSummaryURL.path))
                XCTAssertFalse(FileManager.default.fileExists(atPath: maintenance.feedbackMirrorURL.path))

                try validHistory.write(to: historyURL, options: .atomic)
                let rebuilt = try maintenance.rebuild()
                XCTAssertEqual(rebuilt.history.recordCount, min(500, recordCount))
                XCTAssertTrue(rebuilt.summary.isCurrentWithHistory)
                XCTAssertFalse(rebuilt.warnings.contains("invalid_history_lines:1"))
            }
        }
    }

    func testExplicitClearCanRemoveUndecodableHistoryRows() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        var history = try acceptedHistoryData(acceptedHistoryRecords(1))
        history.append(try XCTUnwrap(undecodableHistoryRows().first))
        history.append(0x0A)
        try history.write(to: historyURL, options: .atomic)
        let maintenance = AIAcceptedLearningMaintenance(
            historyURL: historyURL,
            summaryURL: directory.appendingPathComponent("accepted-ai-summary.json"),
            mirrorURL: directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md"),
            feedbackHistoryURL: directory.appendingPathComponent("feedback.jsonl"),
            feedbackSummaryURL: directory.appendingPathComponent("feedback-summary.json"),
            feedbackMirrorURL: directory.appendingPathComponent("FEEDBACK.md"),
            lexicalJSONURL: directory.appendingPathComponent("lexical-profile.json"),
            lexicalMarkdownURL: directory.appendingPathComponent("LEXICAL_PROFILE.md")
        )
        XCTAssertThrowsError(try maintenance.clear(confirm: false))
        XCTAssertEqual(try Data(contentsOf: historyURL), history)
        XCTAssertEqual(try maintenance.clear(confirm: true).action, "cleared")
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyURL.path))
    }

    func testClearReadsLegacyMarkerAndRefusesUndecodablePendingEntries() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let originalHistory = try acceptedHistoryData(acceptedHistoryRecords(1))
        try originalHistory.write(to: historyURL, options: .atomic)
        let maintenance = AIAcceptedLearningMaintenance(
            historyURL: historyURL,
            summaryURL: directory.appendingPathComponent("accepted-ai-summary.json"),
            mirrorURL: directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md"),
            feedbackHistoryURL: directory.appendingPathComponent("feedback.jsonl"),
            feedbackSummaryURL: directory.appendingPathComponent("feedback-summary.json"),
            feedbackMirrorURL: directory.appendingPathComponent("FEEDBACK.md"),
            lexicalJSONURL: directory.appendingPathComponent("lexical-profile.json"),
            lexicalMarkdownURL: directory.appendingPathComponent("LEXICAL_PROFILE.md")
        )
        let invalidMarker = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "clearedAt": "2026-10-19T00:00:00Z",
            "pendingEvictedCommitEntries": 42
        ] as [String: Any])
        try invalidMarker.write(to: maintenance.clearMarkerURL, options: .atomic)
        XCTAssertThrowsError(try maintenance.clear(confirm: true))
        XCTAssertEqual(try Data(contentsOf: historyURL), originalHistory)
        XCTAssertEqual(try Data(contentsOf: maintenance.clearMarkerURL), invalidMarker)
        XCTAssertFalse(FileManager.default.fileExists(atPath: maintenance.evictedCommitsURL.path))

        let legacyMarker = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "clearedAt": "2026-10-19T00:00:00Z"
        ] as [String: Any])
        try legacyMarker.write(to: maintenance.clearMarkerURL, options: .atomic)
        XCTAssertEqual(try maintenance.clear(confirm: true).action, "cleared")
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyURL.path))
    }

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

    func testStoreRebuildsStaleSummaryInMemoryWithoutWritingOnLoad() throws {
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

        XCTAssertEqual(repairedSummary.acceptedCount, 2)
        XCTAssertEqual(savedSummary.acceptedCount, 1)
        XCTAssertEqual(savedSummary.historyHash, "stale")
        XCTAssertNotEqual(repairedSummary.historyHash, "stale")
        XCTAssertFalse(FileManager.default.fileExists(atPath: mirrorURL.path))
    }

    func testStoreInitDoesNotCreateAcceptedLearningFilesWhenHistoryIsMissing() {
        let directory = temporaryDirectory().appendingPathComponent("missing-ai", isDirectory: true)
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
        let lockURL = directory.appendingPathComponent("accepted-ai-learning.lock")
        defer {
            try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
        }

        let store = AIAcceptedLearningStore(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            summaryDelayNanoseconds: 0
        )

        XCTAssertTrue(store.allRecords().isEmpty)
        XCTAssertNil(store.snapshot())
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: lockURL.path))
    }

    func testMaintenanceStatusRebuildAndClearStayScopedToAcceptedLearningFiles() async throws {
        let directory = temporaryDirectory()
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
        let lexicalJSONURL = directory.appendingPathComponent("lexical-profile.json")
        let lexicalMarkdownURL = directory.appendingPathComponent("LEXICAL_PROFILE.md")
        let record = AIAcceptedLearningRecord(
            acceptedAt: Date(timeIntervalSince1970: 1),
            schemaID: "pinyin_simp",
            rawInput: "json",
            acceptedText: "JSON Schema 可以继续推进",
            provider: "ai-test",
            contextVersion: "test",
            candidateSource: "ai:ai-test"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try String(data: encoder.encode(record), encoding: .utf8)?
            .appending("\n")
            .write(to: historyURL, atomically: true, encoding: .utf8)
        let staleSummary = AIAcceptedLanguageSummary(
            historyHash: "stale",
            acceptedCount: 0,
            termProfile: [],
            styleProfile: ToneProfile(),
            recentAcceptedCommits: [],
            sourceSummary: ["accepted-ai-summary: terms=0 commits=0 history=stale"]
        )
        try encoder.encode(staleSummary).write(to: summaryURL, options: .atomic)
        try Data("{}".utf8).write(to: lexicalJSONURL)
        try Data("- accepted-ai-summary: terms=1 commits=1 history=old\n".utf8).write(to: lexicalMarkdownURL)

        let maintenance = AIAcceptedLearningMaintenance(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            lexicalJSONURL: lexicalJSONURL,
            lexicalMarkdownURL: lexicalMarkdownURL
        )

        let stale = maintenance.status()
        XCTAssertEqual(stale.history.recordCount, 1)
        XCTAssertFalse(stale.summary.isCurrentWithHistory)
        XCTAssertTrue(stale.warnings.contains("summary_stale"))

        let rebuilt = try maintenance.rebuild()
        XCTAssertEqual(rebuilt.action, "rebuilt")
        XCTAssertTrue(rebuilt.summary.isCurrentWithHistory)
        XCTAssertEqual(rebuilt.summary.acceptedCount, 1)
        XCTAssertGreaterThan(rebuilt.summary.termCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mirrorURL.path))

        XCTAssertThrowsError(try maintenance.clear(confirm: false)) { error in
            XCTAssertEqual(error as? AIAcceptedLearningMaintenance.Error, .clearRequiresConfirmation)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyURL.path))

        let cleared = try maintenance.clear(confirm: true)
        XCTAssertEqual(cleared.action, "cleared")
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: summaryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: mirrorURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lexicalJSONURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lexicalMarkdownURL.path))
    }

    func testMaintenanceClearPreventsRunningStoreFromRestoringOldRecords() async throws {
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
                rawInput: "json",
                acceptedText: "JSON Schema 可以继续推进",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        XCTAssertEqual(store.allRecords().count, 1)

        let maintenance = AIAcceptedLearningMaintenance(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            lexicalJSONURL: directory.appendingPathComponent("lexical-profile.json"),
            lexicalMarkdownURL: directory.appendingPathComponent("LEXICAL_PROFILE.md")
        )
        try maintenance.clear(confirm: true)

        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                schemaID: "pinyin_simp",
                rawInput: "api",
                acceptedText: "API 设计可以保持简洁",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )

        let records = store.allRecords()
        let summary = try XCTUnwrap(store.snapshot())
        let historyContent = try String(contentsOf: historyURL, encoding: .utf8)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.acceptedText, "API 设计可以保持简洁")
        XCTAssertEqual(summary.acceptedCount, 1)
        XCTAssertTrue(historyContent.contains("API 设计可以保持简洁"))
        XCTAssertFalse(historyContent.contains("JSON Schema 可以继续推进"))
    }

    func testMaintenanceClearInvalidatesRunningStoreSnapshots() async throws {
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
                rawInput: "json",
                acceptedText: "JSON Schema 可以继续推进",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        XCTAssertNotNil(store.snapshot())
        XCTAssertNotNil(store.snapshot(schemaID: "pinyin_simp"))

        let maintenance = AIAcceptedLearningMaintenance(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            lexicalJSONURL: directory.appendingPathComponent("lexical-profile.json"),
            lexicalMarkdownURL: directory.appendingPathComponent("LEXICAL_PROFILE.md")
        )
        try maintenance.clear(confirm: true)

        XCTAssertNil(store.snapshot())
        XCTAssertNil(store.snapshot(schemaID: "pinyin_simp"))
    }

    func testMaintenanceClearScrubsAcceptedAIFromPersistentLexicalProfile() throws {
        let directory = temporaryDirectory()
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
        let lexicalJSONURL = directory.appendingPathComponent("lexical-profile.json")
        let lexicalMarkdownURL = directory.appendingPathComponent("LEXICAL_PROFILE.md")
        let acceptedRecord = AIAcceptedLearningRecord(
            schemaID: "pinyin_simp",
            rawInput: "json",
            acceptedText: "JSON Schema 可以继续推进",
            provider: "ai-test",
            contextVersion: "test",
            candidateSource: "ai:ai-test"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try String(data: encoder.encode(acceptedRecord), encoding: .utf8)?
            .appending("\n")
            .write(to: historyURL, atomically: true, encoding: .utf8)
        let context = LexicalContextSnapshot(
            terms: [
                LexicalContextTerm(text: "JSON", score: 1, source: "accepted-ai"),
                LexicalContextTerm(text: "长期高频", score: 0.9, source: "rime-userdb")
            ],
            recentCommits: ["JSON Schema 可以继续推进", "普通提交保留"],
            toneProfile: ToneProfile(codeSwitchingRatio: 0.5),
            sourceSummary: [
                "accepted-ai-summary: terms=1 commits=1 history=abc123",
                "rime-userdb: 1"
            ]
        )
        let profile = PersistentLexicalProfile(
            schemaID: "pinyin_simp",
            rimeSnapshotPath: "/tmp/pinyin_simp.userdb.txt",
            rimeSnapshotModifiedAt: Date(timeIntervalSince1970: 1),
            lexicalContext: context
        )
        try encoder.encode(profile).write(to: lexicalJSONURL, options: .atomic)
        try Data(context.markdown.utf8).write(to: lexicalMarkdownURL)

        let maintenance = AIAcceptedLearningMaintenance(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            lexicalJSONURL: lexicalJSONURL,
            lexicalMarkdownURL: lexicalMarkdownURL
        )
        try maintenance.clear(confirm: true)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let scrubbed = try decoder.decode(PersistentLexicalProfile.self, from: Data(contentsOf: lexicalJSONURL))
        let markdown = try String(contentsOf: lexicalMarkdownURL, encoding: .utf8)
        XCTAssertFalse(scrubbed.lexicalContext.terms.contains { $0.source == "accepted-ai" })
        XCTAssertTrue(scrubbed.lexicalContext.terms.contains { $0.text == "长期高频" })
        XCTAssertEqual(scrubbed.lexicalContext.recentCommits, ["普通提交保留"])
        XCTAssertEqual(scrubbed.lexicalContext.toneProfile.codeSwitchingRatio, 0.5)
        XCTAssertFalse(scrubbed.lexicalContext.sourceSummary.contains { $0.hasPrefix("accepted-ai") })
        XCTAssertFalse(markdown.contains("accepted-ai"))
        XCTAssertFalse(markdown.contains("JSON Schema 可以继续推进"))
        XCTAssertTrue(markdown.contains("长期高频"))
        XCTAssertTrue(markdown.contains("普通提交保留"))
    }

    func testMaintenanceClearScrubsMarkdownOnlyAcceptedContext() throws {
        let directory = temporaryDirectory()
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
        let lexicalMarkdownURL = directory.appendingPathComponent("LEXICAL_PROFILE.md")
        let acceptedRecord = AIAcceptedLearningRecord(
            schemaID: "pinyin_simp",
            rawInput: "json",
            acceptedText: "JSON Schema 可以继续推进",
            provider: "ai-test",
            contextVersion: "test",
            candidateSource: "ai:ai-test"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try String(data: encoder.encode(acceptedRecord), encoding: .utf8)?
            .appending("\n")
            .write(to: historyURL, atomically: true, encoding: .utf8)
        try Data(
            """
            # LEXICAL_PROFILE.md

            ## Recent Terms
            - JSON [accepted-ai, 1.00]
            - 长期高频 [rime-userdb, 0.90]

            ## Recent Commits
            - JSON Schema 可以继续推进
            - 普通提交保留

            ## Sources
            - accepted-ai-summary: terms=1 commits=1 history=abc123
            - rime-userdb: 1
            """.utf8
        ).write(to: lexicalMarkdownURL)

        let maintenance = AIAcceptedLearningMaintenance(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            lexicalJSONURL: directory.appendingPathComponent("missing-lexical-profile.json"),
            lexicalMarkdownURL: lexicalMarkdownURL
        )
        try maintenance.clear(confirm: true)

        let markdown = try String(contentsOf: lexicalMarkdownURL, encoding: .utf8)
        XCTAssertFalse(markdown.contains("accepted-ai"))
        XCTAssertFalse(markdown.contains("JSON Schema 可以继续推进"))
        XCTAssertTrue(markdown.contains("长期高频"))
        XCTAssertTrue(markdown.contains("普通提交保留"))
    }

    func testMaintenanceClearMarkdownOnlyPreservesUnknownRecentCommitsWhenHistoryIsMissing() throws {
        let directory = temporaryDirectory()
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
        let lexicalMarkdownURL = directory.appendingPathComponent("LEXICAL_PROFILE.md")
        try Data(
            """
            # LEXICAL_PROFILE.md

            ## Recent Terms
            - JSON [accepted-ai, 1.00]
            - 长期高频 [rime-userdb, 0.90]

            ## Recent Commits
            - JSON Schema 可以继续推进
            - 普通提交保留

            ## Sources
            - accepted-ai-summary: terms=1 commits=1 history=abc123
            - rime-userdb: 1
            """.utf8
        ).write(to: lexicalMarkdownURL)

        let maintenance = AIAcceptedLearningMaintenance(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            lexicalJSONURL: directory.appendingPathComponent("missing-lexical-profile.json"),
            lexicalMarkdownURL: lexicalMarkdownURL
        )
        try maintenance.clear(confirm: true)

        let markdown = try String(contentsOf: lexicalMarkdownURL, encoding: .utf8)
        XCTAssertFalse(markdown.contains("accepted-ai"))
        XCTAssertTrue(markdown.contains("长期高频"))
        XCTAssertTrue(markdown.contains("JSON Schema 可以继续推进"))
        XCTAssertTrue(markdown.contains("普通提交保留"))
    }

    func testMaintenanceStatusTreatsUnreadableSummaryAsStale() throws {
        let directory = temporaryDirectory()
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        try Data("{not-json".utf8).write(to: summaryURL)
        let maintenance = AIAcceptedLearningMaintenance(
            historyURL: directory.appendingPathComponent("accepted-ai-learning.jsonl"),
            summaryURL: summaryURL,
            mirrorURL: directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md"),
            lexicalJSONURL: directory.appendingPathComponent("lexical-profile.json"),
            lexicalMarkdownURL: directory.appendingPathComponent("LEXICAL_PROFILE.md")
        )

        let status = maintenance.status()
        XCTAssertTrue(status.summary.exists)
        XCTAssertFalse(status.summary.isCurrentWithHistory)
        XCTAssertTrue(status.warnings.contains("summary_unreadable"))
    }

    func testMaintenanceStatusJSONDoesNotExposeAcceptedTextOrRawInput() throws {
        let directory = temporaryDirectory()
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
        let record = AIAcceptedLearningRecord(
            schemaID: "pinyin_simp",
            rawInput: "secret raw should not appear",
            acceptedText: "JSON Schema 可以继续推进",
            provider: "ai-test",
            contextVersion: "test",
            candidateSource: "ai:ai-test"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try String(data: encoder.encode(record), encoding: .utf8)?
            .appending("\n")
            .write(to: historyURL, atomically: true, encoding: .utf8)

        let maintenance = AIAcceptedLearningMaintenance(
            historyURL: historyURL,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            lexicalJSONURL: directory.appendingPathComponent("lexical-profile.json"),
            lexicalMarkdownURL: directory.appendingPathComponent("LEXICAL_PROFILE.md")
        )
        let status = maintenance.status()
        let statusJSON = try XCTUnwrap(String(data: JSONEncoder().encode(status), encoding: .utf8))

        XCTAssertFalse(statusJSON.contains("JSON Schema 可以继续推进"))
        XCTAssertFalse(statusJSON.contains("secret raw should not appear"))
        XCTAssertTrue(statusJSON.contains("\"recordCount\":1"))
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
        XCTAssertTrue(store.allRecords().first?.extractedTerms.isEmpty == true)
        XCTAssertEqual(summary.acceptedCount, 1)
        XCTAssertFalse(summary.recentAcceptedCommits.contains { $0.contains("example.com") })
        XCTAssertFalse(summary.termProfile.contains { $0.text.contains("example.com") })
        XCTAssertFalse(lexical?.markdown.contains("example.com") ?? false)
    }

    func testSnapshotCanFilterAcceptedSummaryBySchema() async throws {
        let store = AIAcceptedLearningStore.inMemory()

        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                schemaID: "pinyin_simp",
                rawInput: "json",
                acceptedText: "JSON Schema 可以继续推进",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                schemaID: "double_pinyin",
                rawInput: "api",
                acceptedText: "API 设计可以保持简洁",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )

        let full = try XCTUnwrap(store.snapshot())
        let pinyin = try XCTUnwrap(store.snapshot(schemaID: "pinyin_simp"))
        let doublePinyin = try XCTUnwrap(store.snapshot(schemaID: "double_pinyin"))
        let provider: AIAcceptedLearningSnapshotProviding = store
        let pinyinViaProtocol = try XCTUnwrap(provider.snapshot(schemaID: "pinyin_simp"))

        XCTAssertEqual(full.acceptedCount, 2)
        XCTAssertEqual(pinyin.acceptedCount, 1)
        XCTAssertEqual(pinyinViaProtocol.acceptedCount, 1)
        XCTAssertTrue(pinyin.termProfile.contains { $0.text == "JSON" })
        XCTAssertTrue(pinyinViaProtocol.termProfile.contains { $0.text == "JSON" })
        XCTAssertFalse(pinyinViaProtocol.termProfile.contains { $0.text == "API" })
        XCTAssertFalse(pinyin.termProfile.contains { $0.text == "API" })
        XCTAssertEqual(doublePinyin.acceptedCount, 1)
        XCTAssertTrue(doublePinyin.termProfile.contains { $0.text == "API" })
    }

    func testSchemaSnapshotUsesCachedSummaryUntilBackgroundRefresh() async throws {
        let store = AIAcceptedLearningStore(
            historyURL: nil,
            summaryURL: nil,
            mirrorURL: nil,
            summaryDelayNanoseconds: 2_000_000_000
        )

        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                schemaID: "pinyin_simp",
                rawInput: "json",
                acceptedText: "JSON Schema 可以继续推进",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )

        XCTAssertEqual(store.allRecords().count, 1)
        XCTAssertNil(store.snapshot(schemaID: "pinyin_simp"))
    }

    func testSummaryReadyObserverReceivesMetadataOnlyAfterRebuild() async throws {
        let recorder = SummaryReadyEventRecorder()
        let store = AIAcceptedLearningStore(
            historyURL: nil,
            summaryURL: nil,
            mirrorURL: nil,
            summaryDelayNanoseconds: 0
        )
        store.addSummaryReadyObserver { event in
            recorder.record(event)
        }

        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                schemaID: "pinyin_simp",
                rawInput: "json",
                acceptedText: "JSON Schema 可以继续推进",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )

        let event = try XCTUnwrap(recorder.events.first)
        let summary = try XCTUnwrap(store.snapshot(schemaID: "pinyin_simp"))
        XCTAssertEqual(event.schemaID, "pinyin_simp")
        XCTAssertEqual(event.historyHash, summary.historyHash)
        XCTAssertEqual(event.acceptedCount, 1)
        XCTAssertEqual(event.termCount, summary.termProfile.count)
        XCTAssertEqual(event.recentCommitCount, summary.recentAcceptedCommits.count)
    }

    func testSummaryReadyObserverOnlyEmitsChangedSchemas() async throws {
        let recorder = SummaryReadyEventRecorder()
        let store = AIAcceptedLearningStore(
            historyURL: nil,
            summaryURL: nil,
            mirrorURL: nil,
            summaryDelayNanoseconds: 0
        )
        store.addSummaryReadyObserver { event in
            recorder.record(event)
        }

        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                schemaID: "pinyin_simp",
                rawInput: "json",
                acceptedText: "JSON Schema 可以继续推进",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                schemaID: "double_pinyin",
                rawInput: "api",
                acceptedText: "API 设计可以保持简洁",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )

        XCTAssertEqual(recorder.events.map(\.schemaID), ["pinyin_simp", "double_pinyin"])
    }

    func testMultilineRecentAcceptedCommitIsFlattenedForPromptMarkdown() async throws {
        let store = AIAcceptedLearningStore.inMemory()

        await store.recordAcceptedAI(
            AIAcceptedLearningRecord(
                schemaID: "pinyin_simp",
                rawInput: "fangan",
                acceptedText: "第一行建议\n第二行继续",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )

        let summary = try XCTUnwrap(store.snapshot())
        XCTAssertEqual(summary.recentAcceptedCommits, ["第一行建议 第二行继续"])
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

    func testLexicalContextDoesNotDoubleCountPersistedAcceptedSummary() throws {
        let snapshot = try XCTUnwrap(
            LexicalContextBuilder().snapshot(
                acceptedAITerms: [
                    LexicalContextTerm(text: "JSON", score: 1, source: "accepted-ai")
                ],
                acceptedAIRecentCommits: ["JSON Schema 可以继续推进这个方案"],
                acceptedAISourceSummary: ["accepted-ai-summary: terms=1 commits=1 history=fresh"],
                persistentTerms: [
                    LexicalContextTerm(text: "JSON", score: 1, source: "accepted-ai"),
                    LexicalContextTerm(text: "长期高频", score: 1, source: "rime-userdb")
                ],
                persistentRecentCommits: [
                    "JSON Schema 可以继续推进这个方案",
                    "长期提交可以保留"
                ],
                persistentSourceSummary: [
                    "accepted-ai-summary: terms=1 commits=1 history=stale",
                    "rime-userdb-snapshot: abc"
                ]
            )
        )

        XCTAssertEqual(snapshot.terms.filter { $0.text == "JSON" }.count, 1)
        XCTAssertEqual(snapshot.recentCommits.filter { $0 == "JSON Schema 可以继续推进这个方案" }.count, 1)
        XCTAssertFalse(snapshot.sourceSummary.contains("accepted-ai-summary: terms=1 commits=1 history=stale"))
        XCTAssertTrue(snapshot.sourceSummary.contains("accepted-ai-summary: terms=1 commits=1 history=fresh"))
        XCTAssertTrue(snapshot.sourceSummary.contains("rime-userdb-snapshot: abc"))
    }

    func testLexicalContextDoesNotDoubleCountCurrentRecentAcceptedCommit() throws {
        let snapshot = try XCTUnwrap(
            LexicalContextBuilder().snapshot(
                recentCommits: [
                    "JSON Schema 可以继续推进这个方案",
                    "另外这个方向可以保留"
                ],
                acceptedAIRecentCommits: ["JSON Schema 可以继续推进这个方案"],
                acceptedAISourceSummary: ["accepted-ai-summary: terms=1 commits=1 history=fresh"]
            )
        )

        XCTAssertEqual(snapshot.recentCommits.filter { $0 == "JSON Schema 可以继续推进这个方案" }.count, 1)
        XCTAssertTrue(snapshot.recentCommits.contains("另外这个方向可以保留"))
        XCTAssertTrue(snapshot.sourceSummary.contains("recent-commits: 1"))
        XCTAssertTrue(snapshot.sourceSummary.contains("accepted-ai: terms=0 commits=1"))
    }
}

private func acceptedHistoryRecords(_ count: Int) -> [AIAcceptedLearningRecord] {
    (1...count).map { index in
        AIAcceptedLearningRecord(
            acceptedAt: Date(timeIntervalSince1970: TimeInterval(index)),
            schemaID: "pinyin_simp",
            acceptedText: "HistoryRecord\(index)",
            provider: "ai-test",
            contextVersion: "test",
            candidateSource: "ai:ai-test",
            extractedTerms: []
        )
    }
}

private func acceptedHistoryData(_ records: [AIAcceptedLearningRecord]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try records.reduce(into: Data()) { data, record in
        data.append(try encoder.encode(record))
        data.append(0x0A)
    }
}

private func undecodableHistoryRows() throws -> [Data] {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    var incompatible = try XCTUnwrap(
        JSONSerialization.jsonObject(with: encoder.encode(acceptedHistoryRecords(1)[0])) as? [String: Any]
    )
    incompatible["schemaVersion"] = 2
    incompatible["acceptedText"] = ["text": "Forward-compatible storage required"]
    return [
        try JSONSerialization.data(withJSONObject: incompatible, options: [.sortedKeys]),
        Data(#"{"acceptedText":}"#.utf8)
    ]
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

private final class SummaryReadyEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [AIAcceptedLearningSummaryReadyEvent] = []

    func record(_ event: AIAcceptedLearningSummaryReadyEvent) {
        lock.lock()
        recordedEvents.append(event)
        lock.unlock()
    }

    var events: [AIAcceptedLearningSummaryReadyEvent] {
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
