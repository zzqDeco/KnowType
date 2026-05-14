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

    func testInsertionPointFallbackUsesSelectedRangeEnd() {
        XCTAssertEqual(
            CandidateAnchorPolicy.insertionPointFallbackRange(
                selectedRange: NSRange(location: 42, length: 8),
                markedRange: nil
            ),
            NSRange(location: 50, length: 0)
        )
    }

    func testInsertionPointFallbackSkipsUnknownLocation() {
        XCTAssertNil(
            CandidateAnchorPolicy.insertionPointFallbackRange(
                selectedRange: NSRange(location: NSNotFound, length: NSNotFound),
                markedRange: nil
            )
        )
    }

    func testLineHeightIndexesUseInlineMarkedTextOffsets() {
        XCTAssertEqual(
            CandidateAnchorPolicy.lineHeightCharacterIndexes(
                selectedRange: NSRange(location: 5, length: 0),
                markedRange: NSRange(location: 4, length: 2),
                maximumBacktrack: 2
            ),
            [2, 1, 0]
        )
    }

    func testLineHeightIndexesUseCurrentSelectionWhenNoMarkedTextExists() {
        XCTAssertEqual(
            CandidateAnchorPolicy.lineHeightCharacterIndexes(
                selectedRange: NSRange(location: 120, length: 0),
                markedRange: nil,
                maximumBacktrack: 2
            ),
            [0]
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
