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

    func testCommitsOnlySuggestionForCurrentRawInput() {
        XCTAssertTrue(
            SuggestionPublicationGuard.hasCurrentSuggestion(
                suggestionRawInput: "wojuede",
                currentRawInput: "wojuede"
            )
        )
        XCTAssertFalse(
            SuggestionPublicationGuard.hasCurrentSuggestion(
                suggestionRawInput: "wo",
                currentRawInput: "wojuede"
            )
        )
        XCTAssertFalse(
            SuggestionPublicationGuard.hasCurrentSuggestion(
                suggestionRawInput: nil,
                currentRawInput: "wojuede"
            )
        )
    }
}
