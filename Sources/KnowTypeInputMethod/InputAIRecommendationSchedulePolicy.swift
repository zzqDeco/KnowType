import Foundation
import KnowTypeAI
import KnowTypeCore

struct InputAIRecommendationScheduleContext: Sendable, Equatable {
    var rawInput: String
    var hasResolvedSegments: Bool
    var isFullyResolved: Bool
    var lockedPrefix: String?
    var cloudContinuationEnabled: Bool
    var canRequestAIRecommendations: Bool
    var hasRecommendationProvider: Bool
}

struct InputAIRecommendationScheduleSkip: Sendable, Equatable {
    var state: AIRecommendationState
    var diagnosticStage: AIRecommendationDiagnosticStage
    var reason: String
}

enum InputAIRecommendationScheduleDecision: Sendable, Equatable {
    case schedule
    case skip(InputAIRecommendationScheduleSkip)
}

struct InputAIRecommendationSchedulePolicy: Sendable, Equatable {
    var triggerPolicy: AIRecommendationTriggerPolicy

    init(triggerPolicy: AIRecommendationTriggerPolicy = .default) {
        self.triggerPolicy = triggerPolicy
    }

    static let `default` = InputAIRecommendationSchedulePolicy()

    func decision(
        for context: InputAIRecommendationScheduleContext
    ) -> InputAIRecommendationScheduleDecision {
        guard !context.rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !context.hasResolvedSegments || context.isFullyResolved else {
            return .skip(
                InputAIRecommendationScheduleSkip(
                    state: .idle,
                    diagnosticStage: .skippedIneligible,
                    reason: "no_stable_prefix"
                )
            )
        }

        let triggerDecision = triggerPolicy.decision(
            rawInput: context.rawInput,
            lockedPrefix: context.lockedPrefix
        )
        guard triggerDecision.isEligible else {
            return .skip(
                InputAIRecommendationScheduleSkip(
                    state: .idle,
                    diagnosticStage: .skippedPrefixTooShort,
                    reason: triggerDecision.rejectionReason?.rawValue ?? "prefix_too_short"
                )
            )
        }

        guard !TextProtection.containsSecretLikeContent(context.rawInput),
              context.lockedPrefix.map({
                  !TextProtection.containsSecretLikeContent($0)
              }) ?? true else {
            return .skip(
                InputAIRecommendationScheduleSkip(
                    state: .ineligible(reason: "AI 已禁用"),
                    diagnosticStage: .skippedProtectedText,
                    reason: "secret_like_text"
                )
            )
        }

        guard context.cloudContinuationEnabled else {
            return .skip(
                InputAIRecommendationScheduleSkip(
                    state: .ineligible(reason: "AI 已关闭"),
                    diagnosticStage: .skippedDisabled,
                    reason: "cloud_continuation_disabled"
                )
            )
        }

        guard context.canRequestAIRecommendations else {
            return .skip(
                InputAIRecommendationScheduleSkip(
                    state: context.hasRecommendationProvider
                        ? .unavailable(reason: "AI 未配置")
                        : .idle,
                    diagnosticStage: .skippedNoProvider,
                    reason: "provider_not_configured"
                )
            )
        }

        guard context.hasRecommendationProvider else {
            return .skip(
                InputAIRecommendationScheduleSkip(
                    state: .idle,
                    diagnosticStage: .skippedNoProvider,
                    reason: "recommendation_provider_missing"
                )
            )
        }

        return .schedule
    }
}
