import XCTest
import KnowTypeCore
@testable import KnowTypeInputMethod

final class InputCompositionControllerTests: XCTestCase {
    private let prefix = [
        CorrectionCandidate(
            text: "我觉得这个方案",
            source: "test",
            confidence: 1.0,
            correctionLevel: .contextual
        )
    ]
    private let continuations = [
        ContinuationCandidate(
            text: "还有进一步优化空间",
            lengthLevel: .medium,
            confidence: 0.9,
            provider: "test"
        ),
        ContinuationCandidate(
            text: "在落地成本上可能偏高",
            lengthLevel: .medium,
            confidence: 0.8,
            provider: "test"
        )
    ]

    func testSpaceCommitsPrefixOnly() {
        let controller = InputCompositionController()
        let result = controller.handle(
            action: .space,
            prefixCandidates: prefix,
            continuationCandidates: continuations,
            originalText: "wo jue de zhege fagnan"
        )

        XCTAssertEqual(result, .commit("我觉得这个方案"))
    }

    func testTabCommitsPrefixPlusFirstContinuation() {
        let controller = InputCompositionController()
        let result = controller.handle(
            action: .tab,
            prefixCandidates: prefix,
            continuationCandidates: continuations,
            originalText: "wo jue de zhege fagnan"
        )

        XCTAssertEqual(result, .commit("我觉得这个方案还有进一步优化空间"))
    }

    func testOptionNumberCommitsSelectedContinuation() {
        let controller = InputCompositionController()
        let result = controller.handle(
            action: .optionNumber(2),
            prefixCandidates: prefix,
            continuationCandidates: continuations,
            originalText: "wo jue de zhege fagnan"
        )

        XCTAssertEqual(result, .commit("我觉得这个方案在落地成本上可能偏高"))
    }

    func testOptionRRequestsPolish() {
        let controller = InputCompositionController()
        let result = controller.handle(
            action: .optionR,
            prefixCandidates: prefix,
            continuationCandidates: continuations,
            originalText: "我觉得这个接口慢"
        )

        XCTAssertEqual(result, .polishRequested("我觉得这个接口慢"))
    }
}
