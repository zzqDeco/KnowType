import AppKit
import XCTest
@testable import KnowTypeInputMethod

final class InputControllerRecognizedEventPolicyTests: XCTestCase {
    func testRecognizedEventsMaskIsExactlyKeyDown() {
        XCTAssertEqual(
            InputControllerRecognizedEventPolicy.recognizedEvents,
            Int(NSEvent.EventTypeMask.keyDown.rawValue)
        )
    }
}
