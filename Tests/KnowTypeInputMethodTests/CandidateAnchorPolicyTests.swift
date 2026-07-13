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

    func testFirstRectRequestsHaveFixedCeiling() {
        let requests = CandidateAnchorPolicy.characterRangeRequests(
            selectedRange: NSRange(location: 42, length: 8),
            markedRange: NSRange(location: 10, length: 4)
        )

        XCTAssertEqual(CandidateAnchorPolicy.maximumFirstRectProbes, 4)
        XCTAssertEqual(requests.count, 4)
    }

    func testLineHeightIndexesUseDeduplicatedStrategicInlinePositions() {
        XCTAssertEqual(
            CandidateAnchorPolicy.lineHeightCharacterIndexes(
                selectedRange: NSRange(location: 6, length: 0),
                markedRange: NSRange(location: 4, length: 5)
            ),
            [4, 2, 0]
        )
    }

    func testLineHeightIndexesClampEndsWithoutPerCharacterBacktracking() {
        XCTAssertEqual(
            CandidateAnchorPolicy.lineHeightCharacterIndexes(
                selectedRange: NSRange(location: 9, length: 0),
                markedRange: NSRange(location: 4, length: 5)
            ),
            [4, 0]
        )
        XCTAssertEqual(CandidateAnchorPolicy.maximumLineHeightProbes, 4)
    }

    func testLineHeightIndexesUseCurrentSelectionWhenNoMarkedTextExists() {
        XCTAssertEqual(
            CandidateAnchorPolicy.lineHeightCharacterIndexes(
                selectedRange: NSRange(location: 120, length: 0),
                markedRange: nil
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
