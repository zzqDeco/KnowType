import Foundation
import KnowTypeAI

enum InputCommitApplicationPlan: Sendable, Equatable {
    case insertAndReset(String)
    case requestPolishAndKeepComposition(String)
    case keepComposition
    case noAction(consume: Bool)
}

struct InputCommitApplicationSideEffectContexts {
    var aiAcceptance: InputAIAcceptanceCommitContext
    var lexicalCommit: InputLexicalCommitContext
}

final class InputCommitApplicationRuntime: @unchecked Sendable {
    func plan(for result: InputCommitResult, hasComposition: Bool) -> InputCommitApplicationPlan {
        switch InputCommitResultPolicy.directive(for: result) {
        case .insertAndReset(let text):
            return .insertAndReset(text)
        case .requestPolishAndKeepComposition(let text):
            return .requestPolishAndKeepComposition(text)
        case .keepComposition:
            return .keepComposition
        case .noAction:
            return .noAction(consume: InputCommitResultPolicy.shouldConsumeNoAction(hasComposition: hasComposition))
        }
    }

    func acceptedFeedbackContext(
        text: String,
        schemaID: String,
        appBundleID: String?,
        acceptedAIRecommendation: AIRecommendationCandidate?,
        client: InputControllerClient?
    ) -> InputAIAcceptanceFeedbackContext {
        InputAIAcceptanceFeedbackContext(
            text: text,
            schemaID: schemaID,
            appBundleID: appBundleID,
            acceptedAIRecommendation: acceptedAIRecommendation,
            client: client
        )
    }

    func sideEffectContexts(
        text: String,
        schemaID: String,
        appBundleID: String?,
        acceptedAIRecommendation: AIRecommendationCandidate?,
        acceptID: UUID?,
        selectedNativeCandidateSource: String?,
        prefixCandidateSource: String?,
        compositionSnapshot: InputCompositionStateSnapshot,
        client: InputControllerClient?
    ) -> InputCommitApplicationSideEffectContexts {
        InputCommitApplicationSideEffectContexts(
            aiAcceptance: InputAIAcceptanceCommitContext(
                text: text,
                rawInput: compositionSnapshot.rawInput,
                schemaID: schemaID,
                appBundleID: appBundleID,
                acceptedAIRecommendation: acceptedAIRecommendation,
                acceptID: acceptID,
                selectedNativeCandidateSource: selectedNativeCandidateSource,
                prefixCandidateSource: prefixCandidateSource,
                deleteCountBeforeCommit: compositionSnapshot.deleteCountBeforeCommit,
                client: client
            ),
            lexicalCommit: InputLexicalCommitContext(
                text: text,
                schemaID: schemaID,
                compositionID: compositionSnapshot.compositionID
            )
        )
    }

}
