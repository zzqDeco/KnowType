import XCTest
@testable import KnowTypeInputMethod
import KnowTypeCore

final class CompositionBufferTests: XCTestCase {
    func testDisplayUsesRawInputUntilSegmentIsApplied() {
        var buffer = CompositionBuffer(rawInput: "nishishei")
        XCTAssertEqual(buffer.displayText, "nishishei")

        XCTAssertTrue(buffer.apply(candidate(text: "你", start: 0, length: 2, reading: "ni")))

        XCTAssertEqual(buffer.displayText, "你shishei")
        XCTAssertEqual(buffer.activeRange, KnowTypeCore.TextRange(start: 2, length: 7))
        XCTAssertFalse(buffer.isFullyResolved)
    }

    func testAppliesNonOverlappingSegmentsAndCommitsDisplayText() {
        var buffer = CompositionBuffer(rawInput: "nishishei")

        XCTAssertTrue(buffer.apply(candidate(text: "你", start: 0, length: 2, reading: "ni")))
        XCTAssertTrue(buffer.apply(candidate(text: "是谁", start: 2, length: 7, reading: "shi shei")))

        XCTAssertEqual(buffer.displayText, "你是谁")
        XCTAssertEqual(buffer.commitText, "你是谁")
        XCTAssertTrue(buffer.isFullyResolved)
        XCTAssertNil(buffer.activeRange)
    }

    func testRejectsOverlappingOrOutOfBoundsSegments() {
        var buffer = CompositionBuffer(rawInput: "nishishei")

        XCTAssertTrue(buffer.apply(candidate(text: "你", start: 0, length: 2, reading: "ni")))
        XCTAssertFalse(buffer.apply(candidate(text: "你是", start: 0, length: 5, reading: "ni shi")))
        XCTAssertFalse(buffer.apply(candidate(text: "谁", start: 8, length: 4, reading: "shei")))
        XCTAssertEqual(buffer.displayText, "你shishei")
    }

    func testUndoRestoresLatestRawSegment() {
        var buffer = CompositionBuffer(rawInput: "nishishei")
        XCTAssertTrue(buffer.apply(candidate(text: "你", start: 0, length: 2, reading: "ni")))
        XCTAssertTrue(buffer.apply(candidate(text: "是", start: 2, length: 3, reading: "shi")))

        XCTAssertTrue(buffer.undoLastResolvedSegment())

        XCTAssertEqual(buffer.displayText, "你shishei")
        XCTAssertEqual(buffer.activeRange, KnowTypeCore.TextRange(start: 2, length: 7))
    }

    func testFullyResolvedCommitDropsWhitespaceSeparators() {
        var buffer = CompositionBuffer(rawInput: "ni shi shei")

        XCTAssertTrue(buffer.apply(candidate(text: "你", start: 0, length: 2, reading: "ni")))
        XCTAssertTrue(buffer.apply(candidate(text: "是谁", start: 3, length: 8, reading: "shi shei")))

        XCTAssertEqual(buffer.displayText, "你 是谁")
        XCTAssertTrue(buffer.isFullyResolved)
        XCTAssertEqual(buffer.commitText, "你是谁")
    }

    private func candidate(
        text: String,
        start: Int,
        length: Int,
        reading: String
    ) -> CorrectionCandidate {
        let rawRange = KnowTypeCore.TextRange(start: start, length: length)
        return CorrectionCandidate(
            text: text,
            source: "test",
            confidence: 1.0,
            correctionLevel: .light,
            rawRange: rawRange,
            segments: [
                CandidateSegment(
                    rawRange: rawRange,
                    tokenRange: KnowTypeCore.TextRange(start: 0, length: 1),
                    reading: reading,
                    text: text
                )
            ]
        )
    }
}
