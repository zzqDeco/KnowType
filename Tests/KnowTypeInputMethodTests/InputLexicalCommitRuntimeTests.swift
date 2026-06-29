import KnowTypeAI
@testable import KnowTypeInputMethod
import XCTest

final class InputLexicalCommitRuntimeTests: XCTestCase {
    func testCommitWhitespaceDoesNotRecordEventOrRefresh() {
        let profileManager = RecordingLexicalProfileManager()
        let runtime = makeRuntime(profileManager: profileManager)

        let event = runtime.recordCommit(
            context: InputLexicalCommitContext(
                text: " \n\t ",
                schemaID: "luna_pinyin",
                compositionID: 7
            )
        )

        XCTAssertNil(event)
        XCTAssertTrue(profileManager.scheduledRefreshes.isEmpty)
    }

    func testCommitRecordsEventAndCapsRecentCommitBuffer() {
        let profileManager = RecordingLexicalProfileManager()
        let runtime = makeRuntime(
            profileManager: profileManager,
            maxRecentCommits: 2
        )

        _ = runtime.recordCommit(
            context: InputLexicalCommitContext(
                text: " 第一 ",
                schemaID: "luna_pinyin",
                compositionID: 1
            )
        )
        _ = runtime.recordCommit(
            context: InputLexicalCommitContext(
                text: "第二",
                schemaID: "luna_pinyin",
                compositionID: 2
            )
        )
        let event = runtime.recordCommit(
            context: InputLexicalCommitContext(
                text: "第三",
                schemaID: "luna_pinyin",
                compositionID: 3
            )
        )

        XCTAssertEqual(
            event,
            .compositionCommitted(text: "第三", schemaID: "luna_pinyin", compositionID: 3)
        )
        XCTAssertEqual(profileManager.scheduledRefreshes.last?.reason, "commit")
        XCTAssertEqual(profileManager.scheduledRefreshes.last?.schemaID, "luna_pinyin")
        XCTAssertEqual(profileManager.scheduledRefreshes.last?.recentCommits, ["第二", "第三"])
    }

    func testSelectionRecordsEventAndSchedulesRefreshWithSelectionHistory() {
        let profileManager = RecordingLexicalProfileManager()
        let runtime = makeRuntime(profileManager: profileManager)

        let event = runtime.recordSelection(
            context: InputLexicalSelectionContext(
                text: " 方法 ",
                rawInput: "fang fa",
                appBundleID: "com.example.Editor",
                schemaID: "luna_pinyin",
                compositionID: 42
            )
        )

        XCTAssertEqual(
            event,
            .candidateSelected(text: "方法", schemaID: "luna_pinyin", compositionID: 42)
        )
        XCTAssertEqual(profileManager.scheduledRefreshes.last?.reason, "selection")
        XCTAssertEqual(profileManager.scheduledRefreshes.last?.selectionHistory, ["方法"])
    }

    func testProtectedSelectionOrRawInputSkipsEventAndRefresh() {
        let profileManager = RecordingLexicalProfileManager()
        let runtime = makeRuntime(profileManager: profileManager)

        XCTAssertNil(
            runtime.recordSelection(
                context: InputLexicalSelectionContext(
                    text: "https://example.com",
                    rawInput: "wang zhan",
                    appBundleID: "com.example.Editor",
                    schemaID: "luna_pinyin",
                    compositionID: 1
                )
            )
        )
        XCTAssertNil(
            runtime.recordSelection(
                context: InputLexicalSelectionContext(
                    text: "候选",
                    rawInput: "git status",
                    appBundleID: "com.example.Editor",
                    schemaID: "luna_pinyin",
                    compositionID: 2
                )
            )
        )

        XCTAssertTrue(profileManager.scheduledRefreshes.isEmpty)
    }

    func testLexicalContextSnapshotUsesRecentCommitsAndSelectionHistory() {
        let profileManager = RecordingLexicalProfileManager()
        let runtime = makeRuntime(profileManager: profileManager)

        _ = runtime.recordCommit(
            context: InputLexicalCommitContext(
                text: "你好",
                schemaID: "luna_pinyin",
                compositionID: 1
            )
        )
        _ = runtime.recordSelection(
            context: InputLexicalSelectionContext(
                text: "世界",
                rawInput: "shi jie",
                appBundleID: "com.example.Editor",
                schemaID: "luna_pinyin",
                compositionID: 2
            )
        )

        _ = runtime.lexicalContextSnapshot(schemaID: "luna_pinyin")

        XCTAssertEqual(profileManager.snapshotRequests.last?.schemaID, "luna_pinyin")
        XCTAssertEqual(profileManager.snapshotRequests.last?.recentCommits, ["你好"])
        XCTAssertEqual(profileManager.snapshotRequests.last?.selectionHistory, ["世界"])
    }

    func testCancelRefreshAndFlushSelectionHistoryForwardToDependencies() {
        let persistence = LexicalRuntimeSelectionHistoryPersistence(loadedHistory: ["旧"])
        let profileManager = RecordingLexicalProfileManager()
        let runtime = makeRuntime(
            persistence: persistence,
            profileManager: profileManager
        )

        _ = runtime.recordSelection(
            context: InputLexicalSelectionContext(
                text: "新",
                rawInput: "xin",
                appBundleID: "com.example.Editor",
                schemaID: "luna_pinyin",
                compositionID: 1
            )
        )
        runtime.flushSelectionHistory()
        runtime.cancelRefresh()

        XCTAssertEqual(persistence.flushCalls, [["旧", "新"]])
        XCTAssertEqual(profileManager.cancelCount, 1)
    }

    private func makeRuntime(
        persistence: (any InputControllerUserSelectionHistoryPersisting)? = nil,
        profileManager: RecordingLexicalProfileManager,
        maxRecentCommits: Int = InputLexicalCommitRuntime.defaultMaxRecentCommits
    ) -> InputLexicalCommitRuntime {
        InputLexicalCommitRuntime(
            selectionHistoryRuntime: InputSelectionHistoryRuntime(
                persistence: persistence,
                maxEntries: 4
            ),
            lexicalProfileRuntime: profileManager,
            maxRecentCommits: maxRecentCommits
        )
    }
}

private struct LexicalProfileRefreshRecord: Equatable {
    var reason: String
    var schemaID: String
    var recentCommits: [String]
    var selectionHistory: [String]
}

private struct LexicalContextSnapshotRequest: Equatable {
    var schemaID: String
    var recentCommits: [String]
    var selectionHistory: [String]
}

private final class RecordingLexicalProfileManager: InputLexicalProfileManaging, @unchecked Sendable {
    private(set) var scheduledRefreshes: [LexicalProfileRefreshRecord] = []
    private(set) var snapshotRequests: [LexicalContextSnapshotRequest] = []
    private(set) var cancelCount = 0

    func lexicalContextSnapshot(
        schemaID: String,
        recentCommits: [String],
        selectionHistory: [String]
    ) -> LexicalContextSnapshot? {
        snapshotRequests.append(
            LexicalContextSnapshotRequest(
                schemaID: schemaID,
                recentCommits: recentCommits,
                selectionHistory: selectionHistory
            )
        )
        return nil
    }

    func scheduleRefresh(
        reason: String,
        schemaID: String,
        recentCommits: [String],
        selectionHistory: [String]
    ) {
        scheduledRefreshes.append(
            LexicalProfileRefreshRecord(
                reason: reason,
                schemaID: schemaID,
                recentCommits: recentCommits,
                selectionHistory: selectionHistory
            )
        )
    }

    func cancelRefresh() {
        cancelCount += 1
    }
}

private final class LexicalRuntimeSelectionHistoryPersistence: InputControllerUserSelectionHistoryPersisting, @unchecked Sendable {
    private let loadedHistory: [String]
    private(set) var flushCalls: [[String]] = []

    init(loadedHistory: [String] = []) {
        self.loadedHistory = loadedHistory
    }

    func loadHistory(maxEntries: Int) -> [String] {
        Array(loadedHistory.suffix(maxEntries))
    }

    func recordSelection(
        _ text: String,
        currentHistory: [String],
        maxEntries: Int
    ) -> [String] {
        Array((currentHistory + [text]).suffix(maxEntries))
    }

    func flushHistory(_ currentHistory: [String], maxEntries: Int) {
        flushCalls.append(Array(currentHistory.suffix(maxEntries)))
    }
}
