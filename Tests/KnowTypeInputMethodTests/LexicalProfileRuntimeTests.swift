import Foundation
import XCTest
import KnowTypeAI
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
