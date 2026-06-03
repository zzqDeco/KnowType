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

    func testMaintenanceClearScrubsAcceptedAIFromPersistentLexicalProfile() throws {
        let directory = temporaryDirectory()
        let historyURL = directory.appendingPathComponent("accepted-ai-learning.jsonl")
        let summaryURL = directory.appendingPathComponent("accepted-ai-summary.json")
        let mirrorURL = directory.appendingPathComponent("ACCEPTED_AI_LEARNING.md")
        let lexicalJSONURL = directory.appendingPathComponent("lexical-profile.json")
        let lexicalMarkdownURL = directory.appendingPathComponent("LEXICAL_PROFILE.md")
        let context = LexicalContextSnapshot(
            terms: [
                LexicalContextTerm(text: "JSON", score: 1, source: "accepted-ai"),
                LexicalContextTerm(text: "长期高频", score: 0.9, source: "rime-userdb")
            ],
            recentCommits: ["JSON Schema 可以继续推进"],
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
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
        XCTAssertTrue(scrubbed.lexicalContext.recentCommits.isEmpty)
        XCTAssertFalse(scrubbed.lexicalContext.sourceSummary.contains { $0.hasPrefix("accepted-ai") })
        XCTAssertFalse(markdown.contains("accepted-ai"))
        XCTAssertTrue(markdown.contains("长期高频"))
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
