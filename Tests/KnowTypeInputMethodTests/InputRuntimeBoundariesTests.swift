import XCTest
@testable import KnowTypeInputMethod

final class InputRuntimeBoundariesTests: XCTestCase {
    func testInputEventBusKeepsBoundedRecentHistory() async {
        let bus = InputEventBus(maxRecordedEvents: 4)

        for compositionID in 0..<10 {
            await bus.publish(.compositionStarted(compositionID: compositionID, rawRevision: compositionID))
        }

        let events = await bus.events()
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(
            events,
            [
                .compositionStarted(compositionID: 6, rawRevision: 6),
                .compositionStarted(compositionID: 7, rawRevision: 7),
                .compositionStarted(compositionID: 8, rawRevision: 8),
                .compositionStarted(compositionID: 9, rawRevision: 9)
            ]
        )
    }

    func testInputEventBusCanDisableRetention() async {
        let bus = InputEventBus(maxRecordedEvents: 0)

        await bus.publish(.compositionStarted(compositionID: 1, rawRevision: 1))

        let events = await bus.events()
        XCTAssertTrue(events.isEmpty)
    }
}
