import Foundation

struct InputCompositionLifecycleBeginPlan: Sendable, Equatable {
    var shouldBegin: Bool
    var shouldTraceFirstCompositionBegin: Bool
    var feedbackCancellationReason: String?
    var shouldReloadPreferences: Bool
    var shouldReloadRuntimeLexicon: Bool
    var shouldPublishCompositionStarted: Bool
    var shouldResetAnchor: Bool
}

struct InputCompositionLifecycleFinishPlan: Sendable, Equatable {
    var reason: CompositionLifecycleFinishReason
    var panelVisibilityReason: CandidatePanelVisibilityReason
    var finishedCompositionID: Int
    var commitText: String?
    var shouldClearOwnedMarkedText: Bool
    var shouldPublishCompositionEnded: Bool
}

enum CompositionLifecycleFinishReason: String, Sendable, Equatable {
    case commit
    case deactivate
    case close
    case reset
    case nativeEnded = "native_ended"

    var shouldClearMarkedTextWhenEndingWithoutCommit: Bool {
        true
    }

    var panelVisibilityReason: CandidatePanelVisibilityReason {
        switch self {
        case .commit:
            return .compositionEnded
        case .deactivate:
            return .deactivate
        case .close:
            return .close
        case .reset:
            return .reset
        case .nativeEnded:
            return .nativeEnded
        }
    }
}

final class InputCompositionLifecycleRuntime: @unchecked Sendable {
    private var didTraceFirstCompositionBegin = false

    func beginPlan(compositionSnapshot: InputCompositionStateSnapshot) -> InputCompositionLifecycleBeginPlan {
        guard !compositionSnapshot.hasActiveTextComposition else {
            return InputCompositionLifecycleBeginPlan(
                shouldBegin: false,
                shouldTraceFirstCompositionBegin: false,
                feedbackCancellationReason: nil,
                shouldReloadPreferences: false,
                shouldReloadRuntimeLexicon: false,
                shouldPublishCompositionStarted: false,
                shouldResetAnchor: false
            )
        }

        let shouldTrace = !didTraceFirstCompositionBegin
        didTraceFirstCompositionBegin = true
        return InputCompositionLifecycleBeginPlan(
            shouldBegin: true,
            shouldTraceFirstCompositionBegin: shouldTrace,
            feedbackCancellationReason: "new_composition",
            shouldReloadPreferences: true,
            shouldReloadRuntimeLexicon: true,
            shouldPublishCompositionStarted: true,
            shouldResetAnchor: true
        )
    }

    func finishPlan(
        reason: CompositionLifecycleFinishReason,
        compositionSnapshot: InputCompositionStateSnapshot,
        hasNativeComposition: Bool,
        commitText: String?
    ) -> InputCompositionLifecycleFinishPlan {
        InputCompositionLifecycleFinishPlan(
            reason: reason,
            panelVisibilityReason: reason.panelVisibilityReason,
            finishedCompositionID: compositionSnapshot.compositionID,
            commitText: commitText,
            shouldClearOwnedMarkedText: reason.shouldClearMarkedTextWhenEndingWithoutCommit
                && (compositionSnapshot.hasActiveTextComposition || hasNativeComposition),
            shouldPublishCompositionEnded: true
        )
    }
}
