import XCTest
import KnowTypeCore
@testable import KnowTypeInputMethod

final class InputCandidateListBuilderTests: XCTestCase {
    func testReturnsRawInputWhenSuggestionIsUnavailable() {
        let builder = InputCandidateListBuilder()

        XCTAssertEqual(builder.candidates(rawInput: "wo jue", suggestion: nil), ["wo jue"])
        XCTAssertEqual(builder.candidates(rawInput: "", suggestion: nil), [])
    }

    func testNativeCandidateListIncludesPrefixAndContinuationRows() {
        let suggestion = SuggestionResponse(
            prefixCandidates: [
                CorrectionCandidate(
                    text: "我觉得这个方案",
                    source: "test",
                    confidence: 1.0,
                    correctionLevel: .contextual
                ),
                CorrectionCandidate(
                    text: "我觉得这个方法",
                    source: "test",
                    confidence: 0.8,
                    correctionLevel: .contextual
                )
            ],
            lockedPrefix: LockedPrefix(
                text: "我觉得这个方案",
                rawInput: "wo jue de zhege fagnan",
                candidateID: "test"
            ),
            continuationCandidates: [
                ContinuationCandidate(
                    text: "还有进一步优化空间",
                    lengthLevel: .medium,
                    confidence: 0.9,
                    provider: "test"
                )
            ],
            latencyMs: 1
        )

        let candidates = InputCandidateListBuilder().candidates(
            rawInput: "wo jue de zhege fagnan",
            suggestion: suggestion
        )

        XCTAssertEqual(candidates, ["我觉得这个方案", "我觉得这个方法", "还有进一步优化空间"])
        XCTAssertFalse(candidates.contains("wo jue de zhege fagnan"))
    }

    func testNativeCandidateSelectionsKeepSelectablePrefixAndContinuationIndexes() {
        let suggestion = SuggestionResponse(
            prefixCandidates: [
                CorrectionCandidate(
                    text: "我觉得这个方案",
                    source: "test",
                    confidence: 1.0,
                    correctionLevel: .contextual
                ),
                CorrectionCandidate(
                    text: "我觉得这个方法",
                    source: "test",
                    confidence: 0.8,
                    correctionLevel: .contextual
                )
            ],
            lockedPrefix: LockedPrefix(
                text: "我觉得这个方案",
                rawInput: "wo jue de zhege fagnan",
                candidateID: "test"
            ),
            continuationCandidates: [
                ContinuationCandidate(
                    text: "还有进一步优化空间",
                    lengthLevel: .medium,
                    confidence: 0.9,
                    provider: "test"
                )
            ],
            latencyMs: 1
        )

        let selections = InputCandidateListBuilder().candidateSelections(
            rawInput: "wo jue de zhege fagnan",
            suggestion: suggestion
        )

        XCTAssertEqual(
            selections,
            [
                InputCandidateSelection(text: "我觉得这个方案", kind: .prefixCandidate(index: 0)),
                InputCandidateSelection(text: "我觉得这个方法", kind: .prefixCandidate(index: 1)),
                InputCandidateSelection(text: "还有进一步优化空间", kind: .continuationCandidate(index: 0))
            ]
        )
    }

    func testDoesNotDuplicateRawInputWhenItMatchesPrefixCandidate() {
        let suggestion = SuggestionResponse(
            prefixCandidates: [
                CorrectionCandidate(
                    text: "I think this approach",
                    source: "test",
                    confidence: 1.0,
                    correctionLevel: .light
                )
            ],
            lockedPrefix: LockedPrefix(
                text: "I think this approach",
                rawInput: "I think this approach",
                candidateID: "test"
            ),
            continuationCandidates: [],
            latencyMs: 1
        )

        XCTAssertEqual(
            InputCandidateListBuilder().candidates(
                rawInput: "I think this approach",
                suggestion: suggestion
            ),
            ["I think this approach"]
        )
    }
}
