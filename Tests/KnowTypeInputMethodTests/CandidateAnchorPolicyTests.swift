import Foundation
import XCTest
@testable import KnowTypeInputMethod

final class CandidateAnchorPolicyTests: XCTestCase {
    func testCharacterRangeUsesSelectedRangeLocation() {
        XCTAssertEqual(
            CandidateAnchorPolicy.characterRange(for: NSRange(location: 42, length: 8)),
            NSRange(location: 50, length: 0)
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

    func testCharacterRangesPreferMarkedRangeEndThenSelectedRange() {
        XCTAssertEqual(
            CandidateAnchorPolicy.characterRanges(
                selectedRange: NSRange(location: 42, length: 0),
                markedRange: NSRange(location: 10, length: 4)
            ),
            [
                NSRange(location: 14, length: 0),
                NSRange(location: 42, length: 0),
                NSRange(location: 10, length: 0)
            ]
        )
    }

    func testCharacterRangesIncludeSelectedRangeStartAndEndForFallbacks() {
        XCTAssertEqual(
            CandidateAnchorPolicy.characterRanges(
                selectedRange: NSRange(location: 42, length: 8),
                markedRange: nil
            ),
            [
                NSRange(location: 50, length: 0),
                NSRange(location: 42, length: 0)
            ]
        )
    }

    func testCurrentInsertionPointFallbackUsesIMKUnknownLocation() {
        XCTAssertEqual(
            CandidateAnchorPolicy.currentInsertionPointFallbackRange,
            NSRange(location: NSNotFound, length: 0)
        )
    }

    func testLineHeightIndexesBacktrackFromCandidateRanges() {
        XCTAssertEqual(
            CandidateAnchorPolicy.lineHeightCharacterIndexes(
                selectedRange: NSRange(location: 8, length: 0),
                markedRange: NSRange(location: 4, length: 2),
                maximumBacktrack: 2
            ),
            [6, 5, 4, 8, 7, 3, 2, 0]
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
