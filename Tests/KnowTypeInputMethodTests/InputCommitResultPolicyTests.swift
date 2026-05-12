import XCTest
@testable import KnowTypeInputMethod

final class InputCommitResultPolicyTests: XCTestCase {
    func testCommitsInsertAndReset() {
        XCTAssertEqual(
            InputCommitResultPolicy.directive(for: .commit("我觉得这个方案")),
            .insertAndReset("我觉得这个方案")
        )
    }

    func testPolishRequestsKeepComposition() {
        XCTAssertEqual(
            InputCommitResultPolicy.directive(for: .polishRequested("我觉得这个接口慢")),
            .keepComposition
        )
    }

    func testNoActionDoesNotCommitRawText() {
        XCTAssertEqual(
            InputCommitResultPolicy.directive(for: .noAction),
            .noAction
        )
    }
}
