import Foundation
import KnowTypeAI

enum InputTurnKind: String, Sendable, Equatable {
    case commitResult = "commit_result"
    case nativeCommit = "native_commit"
    case nativeHandled = "native_handled"
    case lifecycleFinish = "lifecycle_finish"
    case directPassthrough = "direct_passthrough"
}

struct InputTurnToken: Sendable, Equatable {
    var turnID: Int
    var kind: InputTurnKind
    var compositionSnapshot: InputCompositionStateSnapshot

    var compositionID: Int {
        compositionSnapshot.compositionID
    }

    var rawRevision: Int {
        compositionSnapshot.rawRevision
    }

    var rawLength: Int {
        compositionSnapshot.rawInput.count
    }
}

enum InputTurnClientScope: Sendable, Equatable {
    case provided
    case effective
}

enum InputTurnEffect: Sendable, Equatable {
    case prepareAcceptedFeedback(text: String, acceptedAIRecommendation: AIRecommendationCandidate?)
    case recordCommitSideEffects(
        text: String,
        acceptedAIRecommendation: AIRecommendationCandidate?,
        clientScope: InputTurnClientScope
    )
    case insertCommittedText(String, clientScope: InputTurnClientScope)
    case schedulePostInsertCaretVerification
    case requestPolish(String)
    case refreshComposition
    case hideCandidatePanel(CandidatePanelVisibilityReason)
    case clearOwnedMarkedText
    case resetConversionEngine
    case resetCompositionStateAfterLifecycleFinish
    case resetAnchorState
    case invalidateSuggestion
    case finishWriterLifecycle(shouldClearOwnedMarkedTextWhenEndingWithoutCommit: Bool)
    case publishCompositionEnded(reason: CandidatePanelVisibilityReason, compositionID: Int)
    case cancelAIFeedback(reason: String)
    case insertDirectPassthroughText(String)
    case syncRawInputFromNativeSnapshot(ConversionEngineSnapshot)
    case publishLocalSuggestion
}

struct InputTurnEffectSequence: Sendable, Equatable {
    var token: InputTurnToken
    var effects: [InputTurnEffect]
    var handled: Bool
}

final class InputTurnSequencingRuntime: @unchecked Sendable {
    private var nextTurnID = 0

    func beginTurn(kind: InputTurnKind, snapshot: InputCompositionStateSnapshot) -> InputTurnToken {
        nextTurnID += 1
        return InputTurnToken(turnID: nextTurnID, kind: kind, compositionSnapshot: snapshot)
    }

    func commitSequence(
        token: InputTurnToken,
        applicationPlan: InputCommitApplicationPlan,
        acceptedAIRecommendation: AIRecommendationCandidate?,
        resetPlan: InputCompositionLifecycleFinishPlan?
    ) -> InputTurnEffectSequence {
        switch applicationPlan {
        case .insertAndReset(let text):
            var effects: [InputTurnEffect] = [
                .prepareAcceptedFeedback(text: text, acceptedAIRecommendation: acceptedAIRecommendation),
                .recordCommitSideEffects(
                    text: text,
                    acceptedAIRecommendation: acceptedAIRecommendation,
                    clientScope: .provided
                ),
                .insertCommittedText(text, clientScope: .provided)
            ]
            if acceptedAIRecommendation != nil {
                effects.append(.schedulePostInsertCaretVerification)
            }
            if let resetPlan {
                effects.append(contentsOf: lifecycleEffects(for: resetPlan))
            }
            return InputTurnEffectSequence(token: token, effects: effects, handled: true)
        case .requestPolishAndKeepComposition(let text):
            return InputTurnEffectSequence(
                token: token,
                effects: [
                    .requestPolish(text),
                    .refreshComposition
                ],
                handled: true
            )
        case .keepComposition:
            return InputTurnEffectSequence(
                token: token,
                effects: [.refreshComposition],
                handled: true
            )
        case .noAction(let consume):
            return InputTurnEffectSequence(token: token, effects: [], handled: consume)
        }
    }

    func nativeCommitSequence(
        token: InputTurnToken,
        text: String,
        snapshot: ConversionEngineSnapshot
    ) -> InputTurnEffectSequence {
        InputTurnEffectSequence(
            token: token,
            effects: [
                .recordCommitSideEffects(
                    text: text,
                    acceptedAIRecommendation: nil,
                    clientScope: .provided
                ),
                .insertCommittedText(text, clientScope: .provided),
                .syncRawInputFromNativeSnapshot(snapshot),
                .publishLocalSuggestion
            ],
            handled: true
        )
    }

    func nativeHandledSequence(
        token: InputTurnToken,
        snapshot: ConversionEngineSnapshot
    ) -> InputTurnEffectSequence {
        InputTurnEffectSequence(
            token: token,
            effects: [
                .syncRawInputFromNativeSnapshot(snapshot),
                .publishLocalSuggestion
            ],
            handled: true
        )
    }

    func lifecycleFinishSequence(
        token: InputTurnToken,
        finishPlan: InputCompositionLifecycleFinishPlan
    ) -> InputTurnEffectSequence {
        InputTurnEffectSequence(
            token: token,
            effects: lifecycleEffects(for: finishPlan),
            handled: finishPlan.commitText?.isEmpty == false
        )
    }

    func directPassthroughSequence(
        token: InputTurnToken,
        text: String,
        resetPlan: InputCompositionLifecycleFinishPlan
    ) -> InputTurnEffectSequence {
        InputTurnEffectSequence(
            token: token,
            effects: [.cancelAIFeedback(reason: "idle_passthrough")]
                + lifecycleEffects(for: resetPlan)
                + [.insertDirectPassthroughText(text)],
            handled: true
        )
    }

    private func lifecycleEffects(
        for finishPlan: InputCompositionLifecycleFinishPlan
    ) -> [InputTurnEffect] {
        var effects: [InputTurnEffect] = [
            .hideCandidatePanel(finishPlan.panelVisibilityReason)
        ]
        if let commitText = finishPlan.commitText,
           !commitText.isEmpty {
            effects.append(
                .recordCommitSideEffects(
                    text: commitText,
                    acceptedAIRecommendation: nil,
                    clientScope: .effective
                )
            )
            effects.append(.insertCommittedText(commitText, clientScope: .effective))
        } else if finishPlan.shouldClearOwnedMarkedText {
            effects.append(.clearOwnedMarkedText)
        }
        effects.append(contentsOf: [
            .resetConversionEngine,
            .resetCompositionStateAfterLifecycleFinish,
            .resetAnchorState,
            .invalidateSuggestion,
            .finishWriterLifecycle(
                shouldClearOwnedMarkedTextWhenEndingWithoutCommit: finishPlan.shouldClearOwnedMarkedText
            )
        ])
        if finishPlan.shouldPublishCompositionEnded {
            effects.append(
                .publishCompositionEnded(
                    reason: finishPlan.panelVisibilityReason,
                    compositionID: finishPlan.finishedCompositionID
                )
            )
        }
        return effects
    }
}
