import XCTest
import KnowTypeCore
@testable import KnowTypeInputMethod

final class InputCandidateListBuilderTests: XCTestCase {
    func testReturnsRawInputWhenSuggestionIsUnavailable() {
        let builder = InputCandidateListBuilder()

        XCTAssertEqual(builder.candidates(rawInput: "wo jue", suggestion: nil), ["wo jue"])
        XCTAssertEqual(builder.candidates(rawInput: "", suggestion: nil), [])
    }

    func testNativeCandidateListExcludesContinuationOnlyRows() {
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

        XCTAssertEqual(candidates, ["我觉得这个方案", "我觉得这个方法"])
        XCTAssertFalse(candidates.contains("还有进一步优化空间"))
    }
}
