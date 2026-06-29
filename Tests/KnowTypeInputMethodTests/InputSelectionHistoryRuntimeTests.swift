@testable import KnowTypeInputMethod
import XCTest

final class InputSelectionHistoryRuntimeTests: XCTestCase {
    func testRecordSelectionPublishesTrimmedEventAndPersistsSelection() {
        let persistence = RuntimeSelectionHistoryPersistence(loadedHistory: ["方案"])
        let runtime = InputSelectionHistoryRuntime(
            persistence: persistence,
            maxEntries: 3
        )

        let event = runtime.recordSelection(
            "  方法  ",
            rawInput: "fang fa",
            appBundleID: "com.example.Editor",
            schemaID: "luna_pinyin",
            compositionID: 42
        )

        XCTAssertEqual(
            event,
            .candidateSelected(text: "方法", schemaID: "luna_pinyin", compositionID: 42)
        )
        XCTAssertEqual(runtime.recentSelectionHistory, ["方法"])
        XCTAssertEqual(persistence.recordedSelections, ["方法"])

        runtime.flush()

        XCTAssertEqual(persistence.flushCalls, [["方案", "方法"]])
    }

    func testProtectedSelectionAndRawInputAreSkipped() {
        let persistence = RuntimeSelectionHistoryPersistence()
        let runtime = InputSelectionHistoryRuntime(
            persistence: persistence,
            maxEntries: 3
        )

        XCTAssertNil(
            runtime.recordSelection(
                "https://example.com",
                rawInput: "wang zhan",
                appBundleID: "com.example.Editor",
                schemaID: "luna_pinyin",
                compositionID: 1
            )
        )
        XCTAssertNil(
            runtime.recordSelection(
                "候选",
                rawInput: "git status",
                appBundleID: "com.example.Editor",
                schemaID: "luna_pinyin",
                compositionID: 2
            )
        )

        XCTAssertTrue(runtime.recentSelectionHistory.isEmpty)
        XCTAssertTrue(persistence.recordedSelections.isEmpty)
    }

    func testRecentSelectionHistoryIsBoundedAndDoesNotStartFromPersistedHistory() {
        let persistence = RuntimeSelectionHistoryPersistence(loadedHistory: ["旧一", "旧二"])
        let runtime = InputSelectionHistoryRuntime(
            persistence: persistence,
            maxEntries: 2
        )

        XCTAssertTrue(runtime.recentSelectionHistory.isEmpty)

        _ = runtime.recordSelection(
            "一",
            rawInput: "yi",
            appBundleID: "com.example.Editor",
            schemaID: "luna_pinyin",
            compositionID: 1
        )
        _ = runtime.recordSelection(
            "二",
            rawInput: "er",
            appBundleID: "com.example.Editor",
            schemaID: "luna_pinyin",
            compositionID: 2
        )
        _ = runtime.recordSelection(
            "三",
            rawInput: "san",
            appBundleID: "com.example.Editor",
            schemaID: "luna_pinyin",
            compositionID: 3
        )

        XCTAssertEqual(runtime.recentSelectionHistory, ["二", "三"])

        runtime.flush()

        XCTAssertEqual(persistence.flushCalls, [["二", "三"]])
    }

    func testZeroMaxEntriesDropsPersistedAndRecentHistory() {
        let persistence = RuntimeSelectionHistoryPersistence(loadedHistory: ["旧"])
        let runtime = InputSelectionHistoryRuntime(
            persistence: persistence,
            maxEntries: 0
        )

        _ = runtime.recordSelection(
            "新",
            rawInput: "xin",
            appBundleID: "com.example.Editor",
            schemaID: "luna_pinyin",
            compositionID: 1
        )

        XCTAssertTrue(runtime.recentSelectionHistory.isEmpty)

        runtime.flush()

        XCTAssertEqual(persistence.loadedMaxEntries, [0])
        XCTAssertEqual(persistence.flushCalls, [[]])
    }
}

private final class RuntimeSelectionHistoryPersistence: InputControllerUserSelectionHistoryPersisting, @unchecked Sendable {
    private let loadedHistory: [String]
    private(set) var loadedMaxEntries: [Int] = []
    private(set) var recordedSelections: [String] = []
    private(set) var flushCalls: [[String]] = []

    init(loadedHistory: [String] = []) {
        self.loadedHistory = loadedHistory
    }

    func loadHistory(maxEntries: Int) -> [String] {
        loadedMaxEntries.append(maxEntries)
        return Array(loadedHistory.suffix(maxEntries))
    }

    func recordSelection(
        _ text: String,
        currentHistory: [String],
        maxEntries: Int
    ) -> [String] {
        recordedSelections.append(text)
        return Array((currentHistory + [text]).suffix(maxEntries))
    }

    func flushHistory(_ currentHistory: [String], maxEntries: Int) {
        flushCalls.append(Array(currentHistory.suffix(maxEntries)))
    }
}
