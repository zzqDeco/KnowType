import Foundation
import KnowTypeAI

public enum InputCommitDirective: Sendable, Equatable {
    case insertAndReset(String)
    case keepComposition
    case noAction
}

public enum InputCommitResultPolicy {
    public static func aiShortcutResult(
        for action: InputAction,
        aiRecommendationState: AIRecommendationState
    ) -> InputCommitResult? {
        if action == .tab,
           aiRecommendationState.isSelectableRecommendation {
            return aiRecommendationCommitResult(for: aiRecommendationState)
        }
        if action == .tab,
           aiRecommendationState.isPendingRecommendation {
            return nil
        }
        if case .optionNumber(1) = action {
            return aiRecommendationState.isSelectableRecommendation
                ? aiRecommendationCommitResult(for: aiRecommendationState)
                : .noAction
        }
        if action == .tab,
           aiRecommendationState.displayText != nil {
            return .noAction
        }
        return nil
    }

    public static func directive(for result: InputCommitResult) -> InputCommitDirective {
        switch result {
        case .commit(let text):
            return .insertAndReset(text)
        case .noAction:
            return .noAction
        }
    }

    public static func shouldConsumeNoAction(hasComposition: Bool) -> Bool {
        hasComposition
    }

    private static func aiRecommendationCommitResult(for state: AIRecommendationState) -> InputCommitResult {
        guard case .ready(let candidate) = state else {
            return .noAction
        }
        return candidate.displayText.isEmpty ? .noAction : .commit(candidate.displayText)
    }
}
