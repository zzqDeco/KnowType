import XCTest
@testable import KnowTypeInputMethod

final class UserSelectionHistoryStoreTests: XCTestCase {
    func testMissingHistoryFileLoadsEmptyHistory() throws {
        let store = FileUserSelectionHistoryStore(fileURL: temporaryHistoryURL())

        XCTAssertEqual(try store.loadHistory(maxEntries: 64), [])
    }

    func testHistoryRoundTripsThroughJSONFile() throws {
        let store = FileUserSelectionHistoryStore(fileURL: temporaryHistoryURL())

        try store.saveHistory(["方案", "方法", "方案"], maxEntries: 64)

        XCTAssertEqual(try store.loadHistory(maxEntries: 64), ["方案", "方法", "方案"])
    }

    func testHistoryIsTrimmedAndCappedOnSaveAndLoad() throws {
        let store = FileUserSelectionHistoryStore(fileURL: temporaryHistoryURL())

        try store.saveHistory(["  ", "  方案", "方法\n", "方向", "思路"], maxEntries: 3)

        XCTAssertEqual(try store.loadHistory(maxEntries: 64), ["方法", "方向", "思路"])
    }

    func testLegacyArrayFileCanBeLoaded() throws {
        let fileURL = temporaryHistoryURL()
        let data = try JSONEncoder().encode(["方案", "方法"])
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL)
        let store = FileUserSelectionHistoryStore(fileURL: fileURL)

        XCTAssertEqual(try store.loadHistory(maxEntries: 64), ["方案", "方法"])
    }

    func testZeroMaxEntriesDropsPersistedHistory() throws {
        let store = FileUserSelectionHistoryStore(fileURL: temporaryHistoryURL())

        try store.saveHistory(["方案", "方法"], maxEntries: 0)

        XCTAssertEqual(try store.loadHistory(maxEntries: 64), [])
    }

    private func temporaryHistoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("user-selection-history.json")
    }
}
