import XCTest
@testable import KnowTypeInputMethod

final class SuggestionRefreshPolicyTests: XCTestCase {
    func testEmptyRawInputDoesNotRefreshSuggestions() {
        XCTAssertFalse(SuggestionRefreshPolicy.shouldRefresh(rawInput: ""))
    }

    func testNonEmptyRawInputRefreshesSuggestions() {
        XCTAssertTrue(SuggestionRefreshPolicy.shouldRefresh(rawInput: "w"))
    }
}
