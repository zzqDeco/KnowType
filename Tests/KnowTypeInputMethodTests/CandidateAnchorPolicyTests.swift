import Foundation
import XCTest
@testable import KnowTypeInputMethod

final class CandidateAnchorPolicyTests: XCTestCase {
    func testCharacterRangeUsesSelectedRangeLocation() {
        XCTAssertEqual(
            CandidateAnchorPolicy.characterRange(for: NSRange(location: 42, length: 8)),
            NSRange(location: 42, length: 0)
        )
    }

    func testCharacterRangeReturnsNilWhenSelectionLocationIsUnknown() {
        XCTAssertNil(CandidateAnchorPolicy.characterRange(for: NSRange(location: NSNotFound, length: 0)))
    }

    func testCharacterRangeFallsBackToMarkedRangeEnd() {
        XCTAssertEqual(
            CandidateAnchorPolicy.characterRange(
                selectedRange: NSRange(location: NSNotFound, length: NSNotFound),
                markedRange: NSRange(location: 10, length: 4)
            ),
            NSRange(location: 14, length: 0)
        )
    }

    func testCharacterRangeUsesDocumentStartWhenClientRangeIsUnknown() {
        XCTAssertEqual(
            CandidateAnchorPolicy.characterRange(
                selectedRange: NSRange(location: NSNotFound, length: NSNotFound),
                markedRange: NSRange(location: NSNotFound, length: NSNotFound)
            ),
            NSRange(location: 0, length: 0)
        )
    }
}
