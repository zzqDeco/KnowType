import Foundation
import XCTest
import KnowTypeAI
import KnowTypeCore
@testable import KnowTypeInputMethod

final class LexicalProfileRuntimeTests: XCTestCase {
    func testScheduledRefreshPersistsAcceptedAISummary() async throws {
        let directory = temporaryDirectory()
        let markdownURL = directory.appendingPathComponent("LEXICAL_PROFILE.md")
        let store = LexicalProfileStore(
            jsonURL: directory.appendingPathComponent("lexical-profile.json"),
            markdownURL: markdownURL
        )
        let acceptedLearning = AIAcceptedLearningStore.inMemory()
        await acceptedLearning.recordAcceptedAI(
            AIAcceptedLearningRecord(
                schemaID: "pinyin_simp",
                rawInput: "json",
                acceptedText: "JSON Schema 可以继续推进",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        let runtime = LexicalProfileRuntime(
            store: store,
            rimeMaintenanceService: StaticRimeUserDBTextSnapshotProvider(),
            acceptedLearningProvider: acceptedLearning,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            refreshGate: LexicalProfileRefreshGate()
        )

        runtime.scheduleRefresh(
            reason: "commit",
            schemaID: "pinyin_simp",
            recentCommits: [],
            selectionHistory: []
        )

        let updated = await waitUntil {
            (try? String(contentsOf: markdownURL, encoding: .utf8).contains("accepted-ai-summary: terms=")) == true
        }
        XCTAssertTrue(updated)
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("accepted-ai: terms="))
        XCTAssertTrue(markdown.contains("commits=1"))
        XCTAssertTrue(markdown.contains("JSON"))
    }

    func testAcceptedSummaryReadySchedulesSecondRefreshAfterInitialRace() async throws {
        let directory = temporaryDirectory()
        let markdownURL = directory.appendingPathComponent("LEXICAL_PROFILE.md")
        let store = LexicalProfileStore(
            jsonURL: directory.appendingPathComponent("lexical-profile.json"),
            markdownURL: markdownURL
        )
        let acceptedLearning = AIAcceptedLearningStore(
            historyURL: nil,
            summaryURL: nil,
            mirrorURL: nil,
            summaryDelayNanoseconds: 1_200_000_000
        )
        let rimeProvider = StaticRimeUserDBTextSnapshotProvider()
        let runtime = LexicalProfileRuntime(
            store: store,
            rimeMaintenanceService: rimeProvider,
            acceptedLearningProvider: acceptedLearning,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            refreshGate: LexicalProfileRefreshGate()
        )

        await acceptedLearning.recordAcceptedAI(
            AIAcceptedLearningRecord(
                schemaID: "pinyin_simp",
                rawInput: "json",
                acceptedText: "JSON Schema 可以继续推进",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )
        runtime.scheduleRefresh(
            reason: "commit",
            schemaID: "pinyin_simp",
            recentCommits: ["JSON Schema 可以继续推进"],
            selectionHistory: []
        )

        let initialRefresh = await waitUntil {
            guard let markdown = try? String(contentsOf: markdownURL, encoding: .utf8) else {
                return false
            }
            return markdown.contains("accepted-ai: terms=0 commits=0")
                && !markdown.contains("accepted-ai-summary:")
        }
        XCTAssertTrue(initialRefresh)

        let acceptedRefresh = await waitUntil(timeoutNanoseconds: 3_000_000_000) {
            (try? String(contentsOf: markdownURL, encoding: .utf8).contains("accepted-ai-summary: terms=")) == true
        }
        XCTAssertTrue(acceptedRefresh)
        let requestCount = await rimeProvider.requestCount
        XCTAssertGreaterThanOrEqual(requestCount, 2)
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("accepted-ai: terms="))
        XCTAssertTrue(markdown.contains("commits=1"))
        XCTAssertEqual(markdown.components(separatedBy: "- JSON Schema 可以继续推进\n").count - 1, 1)
    }

    func testSummaryReadyRefreshUsesMostRecentlyScheduledRuntimeContext() async throws {
        let directory = temporaryDirectory()
        let markdownURL = directory.appendingPathComponent("LEXICAL_PROFILE.md")
        let store = LexicalProfileStore(
            jsonURL: directory.appendingPathComponent("lexical-profile.json"),
            markdownURL: markdownURL
        )
        let acceptedLearning = AIAcceptedLearningStore(
            historyURL: nil,
            summaryURL: nil,
            mirrorURL: nil,
            summaryDelayNanoseconds: 0
        )
        let sharedGate = LexicalProfileRefreshGate()
        let rimeProvider = StaticRimeUserDBTextSnapshotProvider()
        let staleRuntime = LexicalProfileRuntime(
            store: store,
            rimeMaintenanceService: rimeProvider,
            acceptedLearningProvider: acceptedLearning,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            refreshGate: sharedGate
        )
        let currentRuntime = LexicalProfileRuntime(
            store: store,
            rimeMaintenanceService: rimeProvider,
            acceptedLearningProvider: acceptedLearning,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            refreshGate: sharedGate
        )

        staleRuntime.scheduleRefresh(
            reason: "commit",
            schemaID: "pinyin_simp",
            recentCommits: ["旧提交不应出现"],
            selectionHistory: ["旧选择不应出现"]
        )
        currentRuntime.scheduleRefresh(
            reason: "commit",
            schemaID: "pinyin_simp",
            recentCommits: ["最新提交应该保留"],
            selectionHistory: ["最新选择应该保留"]
        )
        await acceptedLearning.recordAcceptedAI(
            AIAcceptedLearningRecord(
                schemaID: "pinyin_simp",
                rawInput: "json",
                acceptedText: "JSON Schema 可以继续推进",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )

        let acceptedRefresh = await waitUntil(timeoutNanoseconds: 3_000_000_000) {
            guard let markdown = try? String(contentsOf: markdownURL, encoding: .utf8) else {
                return false
            }
            return markdown.contains("accepted-ai-summary: terms=")
                && markdown.contains("最新提交应该保留")
                && markdown.contains("最新选择应该保留")
        }
        XCTAssertTrue(acceptedRefresh)
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertFalse(markdown.contains("旧提交不应出现"))
        XCTAssertFalse(markdown.contains("旧选择不应出现"))
    }

    func testLexicalContextReloadsScrubbedProfileAfterAcceptedLearningClear() throws {
        let directory = temporaryDirectory()
        let jsonURL = directory.appendingPathComponent("lexical-profile.json")
        let markdownURL = directory.appendingPathComponent("LEXICAL_PROFILE.md")
        let store = LexicalProfileStore(jsonURL: jsonURL, markdownURL: markdownURL)
        let staleAcceptedContext = LexicalContextSnapshot(
            terms: [
                LexicalContextTerm(text: "JSON", score: 1, source: "accepted-ai"),
                LexicalContextTerm(text: "长期高频", score: 0.9, source: "rime-userdb")
            ],
            recentCommits: ["JSON Schema 可以继续推进", "普通提交保留"],
            toneProfile: ToneProfile(),
            sourceSummary: [
                "accepted-ai-summary: terms=1 commits=1 history=abc123",
                "rime-userdb: 1"
            ]
        )
        try store.save(
            snapshot: staleAcceptedContext,
            schemaID: "pinyin_simp",
            rimeSnapshotURL: nil,
            rimeSnapshotModifiedAt: nil
        )
        let scrubbedContext = LexicalContextSnapshot(
            terms: [LexicalContextTerm(text: "长期高频", score: 0.9, source: "rime-userdb")],
            recentCommits: ["普通提交保留"],
            toneProfile: ToneProfile(),
            sourceSummary: ["rime-userdb: 1"]
        )
        let scrubbedProfile = PersistentLexicalProfile(
            schemaID: "pinyin_simp",
            rimeSnapshotPath: nil,
            rimeSnapshotModifiedAt: nil,
            lexicalContext: scrubbedContext
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(scrubbedProfile).write(to: jsonURL, options: .atomic)
        try Data(scrubbedContext.markdown.utf8).write(to: markdownURL)
        let runtime = LexicalProfileRuntime(
            store: store,
            rimeMaintenanceService: nil,
            acceptedLearningProvider: AIAcceptedLearningStore.inMemory(),
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            refreshGate: LexicalProfileRefreshGate()
        )

        let lexical = try XCTUnwrap(runtime.lexicalContextSnapshot(
            schemaID: "pinyin_simp",
            recentCommits: [],
            selectionHistory: []
        ))

        XCTAssertFalse(lexical.terms.contains { $0.source == "accepted-ai" })
        XCTAssertFalse(lexical.sourceSummary.contains { $0.hasPrefix("accepted-ai-summary:") })
        XCTAssertFalse(lexical.recentCommits.contains("JSON Schema 可以继续推进"))
        XCTAssertTrue(lexical.recentCommits.contains("普通提交保留"))
        XCTAssertTrue(lexical.terms.contains { $0.text == "长期高频" })
    }

    func testCancelRefreshClearsSummaryReadyContext() async throws {
        let directory = temporaryDirectory()
        let markdownURL = directory.appendingPathComponent("LEXICAL_PROFILE.md")
        let store = LexicalProfileStore(
            jsonURL: directory.appendingPathComponent("lexical-profile.json"),
            markdownURL: markdownURL
        )
        let acceptedLearning = AIAcceptedLearningStore(
            historyURL: nil,
            summaryURL: nil,
            mirrorURL: nil,
            summaryDelayNanoseconds: 0
        )
        let rimeProvider = StaticRimeUserDBTextSnapshotProvider()
        let runtime = LexicalProfileRuntime(
            store: store,
            rimeMaintenanceService: rimeProvider,
            acceptedLearningProvider: acceptedLearning,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            refreshGate: LexicalProfileRefreshGate()
        )

        runtime.scheduleRefresh(
            reason: "commit",
            schemaID: "pinyin_simp",
            recentCommits: ["关闭后的提交不应写入"],
            selectionHistory: []
        )
        runtime.cancelRefresh()
        await acceptedLearning.recordAcceptedAI(
            AIAcceptedLearningRecord(
                schemaID: "pinyin_simp",
                rawInput: "json",
                acceptedText: "JSON Schema 可以继续推进",
                provider: "ai-test",
                contextVersion: "test",
                candidateSource: "ai:ai-test"
            )
        )

        try await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markdownURL.path))
        let requestCount = await rimeProvider.requestCount
        XCTAssertEqual(requestCount, 0)
    }
}

private actor StaticRimeUserDBTextSnapshotProvider: RimeUserDBTextSnapshotProviding {
    private var count = 0

    func userDBTextSnapshot(schemaID: String) async throws -> RimeUserDBTextSnapshot {
        count += 1
        return RimeUserDBTextSnapshot(
            schemaID: schemaID,
            fileURL: URL(fileURLWithPath: "/tmp/\(schemaID).userdb.txt"),
            content: "长期高频\tchang qi gao pin\t5\n"
        )
    }

    var requestCount: Int {
        count
    }
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    predicate: () -> Bool
) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if predicate() {
            return true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return predicate()
}

private func temporaryDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("KnowTypeLexicalProfileRuntimeTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
