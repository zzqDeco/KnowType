import XCTest
import KnowTypeAI
@testable import KnowTypeInputMethod

final class InputCommitResultPolicyTests: XCTestCase {
    private let readyAI = AIRecommendationState.ready(
        AIRecommendationCandidate(
            prefixText: "我觉得",
            continuationText: "可以继续",
            displayText: "我觉得可以继续",
            confidence: 0.9,
            provider: "test",
            contextVersion: "test"
        )
    )

    func testCommitsInsertAndReset() {
        XCTAssertEqual(
            InputCommitResultPolicy.directive(for: .commit("我觉得这个方案")),
            .insertAndReset("我觉得这个方案")
        )
    }

    func testPolishRequestsKeepComposition() {
        XCTAssertEqual(
            InputCommitResultPolicy.directive(for: .polishRequested("我觉得这个接口慢")),
            .requestPolishAndKeepComposition("我觉得这个接口慢")
        )
    }

    func testNoActionDoesNotCommitRawText() {
        XCTAssertEqual(
            InputCommitResultPolicy.directive(for: .noAction),
            .noAction
        )
    }

    func testNoActionConsumesOnlyWhenCompositionIsActive() {
        XCTAssertFalse(InputCommitResultPolicy.shouldConsumeNoAction(hasComposition: false))
        XCTAssertTrue(InputCommitResultPolicy.shouldConsumeNoAction(hasComposition: true))
    }

    func testAIShortcutPolicyCommitsReadyRecommendation() {
        XCTAssertEqual(
            InputCommitResultPolicy.aiShortcutResult(for: .tab, aiRecommendationState: readyAI),
            .commit("我觉得可以继续")
        )
        XCTAssertEqual(
            InputCommitResultPolicy.aiShortcutResult(for: .optionNumber(1), aiRecommendationState: readyAI),
            .commit("我觉得可以继续")
        )
    }

    func testAIShortcutPolicyReservesOptionOneWhenRecommendationIsNotReady() {
        let nonReadyStates: [AIRecommendationState] = [
            .idle,
            .pending(requestID: UUID()),
            .ineligible(reason: "AI 已关闭"),
            .unavailable(reason: "AI 未配置")
        ]

        for state in nonReadyStates {
            XCTAssertEqual(
                InputCommitResultPolicy.aiShortcutResult(for: .optionNumber(1), aiRecommendationState: state),
                .noAction
            )
        }
    }

    func testAIShortcutPolicyConsumesTabOnlyForVisibleNonReadyAIStatus() {
        XCTAssertNil(InputCommitResultPolicy.aiShortcutResult(for: .tab, aiRecommendationState: .idle))
        XCTAssertNil(InputCommitResultPolicy.aiShortcutResult(for: .tab, aiRecommendationState: .pending(requestID: UUID())))
        XCTAssertEqual(
            InputCommitResultPolicy.aiShortcutResult(for: .tab, aiRecommendationState: .ineligible(reason: "AI 已关闭")),
            .noAction
        )
        XCTAssertEqual(
            InputCommitResultPolicy.aiShortcutResult(for: .tab, aiRecommendationState: .unavailable(reason: "AI 未配置")),
            .noAction
        )
    }

    func testAIShortcutPolicyLeavesOtherOptionNumbersForLegacyContinuations() {
        XCTAssertNil(InputCommitResultPolicy.aiShortcutResult(for: .optionNumber(2), aiRecommendationState: readyAI))
    }
}
