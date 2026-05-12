import XCTest
@testable import KnowTypeInputMethod

final class SuggestionPublicationGuardTests: XCTestCase {
    func testPublishesOnlyCurrentUncancelledSuggestion() {
        XCTAssertTrue(
            SuggestionPublicationGuard.shouldPublish(
                requestedRawInput: "wo",
                currentRawInput: "wo",
                isCancelled: false
            )
        )
        XCTAssertFalse(
            SuggestionPublicationGuard.shouldPublish(
                requestedRawInput: "w",
                currentRawInput: "wo",
                isCancelled: false
            )
        )
        XCTAssertFalse(
            SuggestionPublicationGuard.shouldPublish(
                requestedRawInput: "wo",
                currentRawInput: "wo",
                isCancelled: true
            )
        )
    }
}
