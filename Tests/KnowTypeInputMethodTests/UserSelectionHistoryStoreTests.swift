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

    func testPersistenceRecordAppendsToLatestDiskHistoryBeforeSaving() throws {
        let fileURL = temporaryHistoryURL()
        let store = FileUserSelectionHistoryStore(fileURL: fileURL)
        let persistence = UserSelectionHistoryPersistence(store: store)
        try store.saveHistory(["方案"], maxEntries: 64)
        let currentHistory = persistence.loadHistory(maxEntries: 64) + ["方法"]
        try store.saveHistory(["方案", "方向"], maxEntries: 64)

        let merged = persistence.recordSelection("思路", currentHistory: currentHistory, maxEntries: 64)
        persistence.flushHistory(merged, maxEntries: 64)

        XCTAssertEqual(merged, ["方案", "方法", "思路"])
        XCTAssertEqual(try store.loadHistory(maxEntries: 64), ["方案", "方向", "思路"])
    }

    func testPersistenceFlushWaitsForPendingSelectionWrites() throws {
        let fileURL = temporaryHistoryURL()
        let store = FileUserSelectionHistoryStore(fileURL: fileURL)
        let persistence = UserSelectionHistoryPersistence(store: store)
        try store.saveHistory(["方案", "方向"], maxEntries: 64)

        let merged = persistence.recordSelection("方法", currentHistory: ["方案"], maxEntries: 64)
        persistence.flushHistory(merged, maxEntries: 64)

        XCTAssertEqual(try store.loadHistory(maxEntries: 64), ["方案", "方向", "方法"])
    }

    func testPersistenceRecordsDuplicateSelectionsInOrder() throws {
        let fileURL = temporaryHistoryURL()
        let store = FileUserSelectionHistoryStore(fileURL: fileURL)
        let persistence = UserSelectionHistoryPersistence(store: store)
        try store.saveHistory(["方案", "方法"], maxEntries: 64)

        let first = persistence.recordSelection("方法", currentHistory: ["方案", "方法"], maxEntries: 64)
        let second = persistence.recordSelection("方案", currentHistory: first, maxEntries: 64)
        persistence.flushHistory(second, maxEntries: 64)

        XCTAssertEqual(try store.loadHistory(maxEntries: 64), ["方案", "方法", "方法", "方案"])
    }

    func testPersistencePreservesDiskRecencyOverStaleControllerSnapshot() throws {
        let fileURL = temporaryHistoryURL()
        let store = FileUserSelectionHistoryStore(fileURL: fileURL)
        let persistence = UserSelectionHistoryPersistence(store: store)
        let staleCurrentHistory = (0..<64).map { "stale-\($0)" }
        try store.saveHistory((0..<64).map { "new-\($0)" }, maxEntries: 64)

        let merged = persistence.recordSelection("current", currentHistory: staleCurrentHistory, maxEntries: 64)
        persistence.flushHistory(merged, maxEntries: 64)
        let diskHistory = try store.loadHistory(maxEntries: 64)

        XCTAssertFalse(diskHistory.contains("stale-63"))
        XCTAssertTrue(diskHistory.contains("new-1"))
        XCTAssertEqual(diskHistory.last, "current")
    }

    private func temporaryHistoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("user-selection-history.json")
    }
}
