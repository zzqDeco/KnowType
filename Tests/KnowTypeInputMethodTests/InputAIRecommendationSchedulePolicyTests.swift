import KnowTypeAI
@testable import KnowTypeInputMethod
import XCTest

final class InputAIRecommendationSchedulePolicyTests: XCTestCase {
    func testEmptyRawInputSkipsAsIneligibleIdle() {
        XCTAssertEqual(
            decision(rawInput: ""),
            .skip(
                InputAIRecommendationScheduleSkip(
                    state: .idle,
                    diagnosticStage: .skippedIneligible,
                    reason: "no_stable_prefix"
                )
            )
        )
    }

    func testPartiallyResolvedCompositionSkipsAsUnstablePrefix() {
        XCTAssertEqual(
            decision(
                rawInput: "ni",
                hasResolvedSegments: true,
                isFullyResolved: false
            ),
            .skip(
                InputAIRecommendationScheduleSkip(
                    state: .idle,
                    diagnosticStage: .skippedIneligible,
                    reason: "no_stable_prefix"
                )
            )
        )
    }

    func testShortRawInputSkipsBeforeProviderScheduling() {
        XCTAssertEqual(
            decision(rawInput: "ni"),
            .skip(
                InputAIRecommendationScheduleSkip(
                    state: .idle,
                    diagnosticStage: .skippedPrefixTooShort,
                    reason: "raw_too_short"
                )
            )
        )
    }

    func testShortLockedPrefixSkipsBeforeProviderScheduling() {
        XCTAssertEqual(
            decision(rawInput: "wojue", lockedPrefix: "我"),
            .skip(
                InputAIRecommendationScheduleSkip(
                    state: .idle,
                    diagnosticStage: .skippedPrefixTooShort,
                    reason: "prefix_too_short"
                )
            )
        )
    }

    func testSecretRawInputSkipsWithDisabledAIState() {
        XCTAssertEqual(
            decision(rawInput: "sk-proj-abcdefghijklmnopqrstuvwxyz"),
            .skip(
                InputAIRecommendationScheduleSkip(
                    state: .ineligible(reason: "AI 已禁用"),
                    diagnosticStage: .skippedProtectedText,
                    reason: "secret_like_text"
                )
            )
        )
    }

    func testSecretLockedPrefixSkipsWithDisabledAIState() {
        XCTAssertEqual(
            decision(
                rawInput: "wojuede",
                lockedPrefix: "token = sk-proj-abcdefghijklmnopqrstuvwxyz"
            ),
            .skip(
                InputAIRecommendationScheduleSkip(
                    state: .ineligible(reason: "AI 已禁用"),
                    diagnosticStage: .skippedProtectedText,
                    reason: "secret_like_text"
                )
            )
        )
    }

    func testDisabledCloudContinuationSkipsWithClosedState() {
        XCTAssertEqual(
            decision(rawInput: "abc", cloudContinuationEnabled: false),
            .skip(
                InputAIRecommendationScheduleSkip(
                    state: .ineligible(reason: "AI 已关闭"),
                    diagnosticStage: .skippedDisabled,
                    reason: "cloud_continuation_disabled"
                )
            )
        )
    }

    func testNoConfiguredProviderSkipsIdle() {
        XCTAssertEqual(
            decision(
                rawInput: "abc",
                canRequestAIRecommendations: false,
                hasRecommendationProvider: false
            ),
            .skip(
                InputAIRecommendationScheduleSkip(
                    state: .idle,
                    diagnosticStage: .skippedNoProvider,
                    reason: "provider_not_configured"
                )
            )
        )
    }

    func testUnavailableProviderStateSkipsWithUnavailableStatus() {
        XCTAssertEqual(
            decision(
                rawInput: "abc",
                canRequestAIRecommendations: false,
                hasRecommendationProvider: true
            ),
            .skip(
                InputAIRecommendationScheduleSkip(
                    state: .unavailable(reason: "AI 未配置"),
                    diagnosticStage: .skippedNoProvider,
                    reason: "provider_not_configured"
                )
            )
        )
    }

    func testMissingRecommendationProviderSkipsIdle() {
        XCTAssertEqual(
            decision(
                rawInput: "abc",
                canRequestAIRecommendations: true,
                hasRecommendationProvider: false
            ),
            .skip(
                InputAIRecommendationScheduleSkip(
                    state: .idle,
                    diagnosticStage: .skippedNoProvider,
                    reason: "recommendation_provider_missing"
                )
            )
        )
    }

    func testEligibleRawInputSchedules() {
        XCTAssertEqual(decision(rawInput: "abc"), .schedule)
    }

    func testEligibleLockedPrefixSchedules() {
        XCTAssertEqual(
            decision(rawInput: "wojuede", lockedPrefix: "我觉得"),
            .schedule
        )
    }

    private func decision(
        rawInput: String,
        hasResolvedSegments: Bool = false,
        isFullyResolved: Bool = false,
        lockedPrefix: String? = nil,
        cloudContinuationEnabled: Bool = true,
        canRequestAIRecommendations: Bool = true,
        hasRecommendationProvider: Bool = true
    ) -> InputAIRecommendationScheduleDecision {
        InputAIRecommendationSchedulePolicy.default.decision(
            for: InputAIRecommendationScheduleContext(
                rawInput: rawInput,
                hasResolvedSegments: hasResolvedSegments,
                isFullyResolved: isFullyResolved,
                lockedPrefix: lockedPrefix,
                cloudContinuationEnabled: cloudContinuationEnabled,
                canRequestAIRecommendations: canRequestAIRecommendations,
                hasRecommendationProvider: hasRecommendationProvider
            )
        )
    }
}
