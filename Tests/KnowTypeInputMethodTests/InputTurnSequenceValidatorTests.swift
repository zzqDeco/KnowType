@testable import KnowTypeInputMethod
import XCTest

final class InputTurnSequenceValidatorTests: XCTestCase {
    func testGeneratedCommitSequencePassesValidation() {
        let runtime = InputTurnSequencingRuntime()
        let token = runtime.beginTurn(kind: .commitResult, snapshot: snapshot(rawInput: "ni", compositionID: 4))
        let sequence = runtime.commitSequence(
            token: token,
            applicationPlan: .insertAndReset("committed"),
            acceptedAIRecommendation: nil,
            resetPlan: finishPlan(reason: .reset, compositionID: 4, shouldClearOwnedMarkedText: true)
        )

        XCTAssertEqual(InputTurnSequenceValidator().validate(sequence), [])
    }

    func testGeneratedLifecycleSequencePassesValidation() {
        let runtime = InputTurnSequencingRuntime()
        let token = runtime.beginTurn(kind: .lifecycleFinish, snapshot: snapshot(rawInput: "ni", compositionID: 9))
        let sequence = runtime.lifecycleFinishSequence(
            token: token,
            finishPlan: finishPlan(
                reason: .deactivate,
                compositionID: 9,
                commitText: "committed",
                shouldClearOwnedMarkedText: true
            )
        )

        XCTAssertEqual(InputTurnSequenceValidator().validate(sequence), [])
    }

    func testGeneratedNativeCommitSequencePassesValidation() {
        let runtime = InputTurnSequencingRuntime()
        let token = runtime.beginTurn(kind: .nativeCommit, snapshot: snapshot(rawInput: "ni", compositionID: 5))
        let sequence = runtime.nativeCommitSequence(
            token: token,
            text: "committed",
            snapshot: ConversionEngineSnapshot(rawInput: "n", preedit: "n")
        )

        XCTAssertEqual(InputTurnSequenceValidator().validate(sequence), [])
    }

    func testGeneratedNativeHandledSequencePassesValidation() {
        let runtime = InputTurnSequencingRuntime()
        let token = runtime.beginTurn(kind: .nativeHandled, snapshot: snapshot(rawInput: "ni", compositionID: 6))
        let sequence = runtime.nativeHandledSequence(
            token: token,
            snapshot: ConversionEngineSnapshot(rawInput: "ni", preedit: "ni")
        )

        XCTAssertEqual(InputTurnSequenceValidator().validate(sequence), [])
    }

    func testGeneratedDirectPassthroughSequencePassesValidation() {
        let runtime = InputTurnSequencingRuntime()
        let token = runtime.beginTurn(kind: .directPassthrough, snapshot: snapshot(rawInput: "", compositionID: 12))
        let sequence = runtime.directPassthroughSequence(
            token: token,
            text: " ",
            resetPlan: finishPlan(reason: .reset, compositionID: 12, shouldClearOwnedMarkedText: false)
        )

        XCTAssertEqual(InputTurnSequenceValidator().validate(sequence), [])
    }

    func testInsertBeforeRecordIsRejectedWithoutUserTextInViolationDescription() {
        let sequence = InputTurnEffectSequence(
            token: token(kind: .commitResult),
            effects: [
                .insertCommittedText("secret-user-text", clientScope: .provided),
                .recordCommitSideEffects(
                    text: "secret-user-text",
                    acceptedAIRecommendation: nil,
                    clientScope: .provided
                )
            ],
            handled: true
        )

        let violations = InputTurnSequenceValidator().validate(sequence)

        XCTAssertEqual(violations.map(\.code), [.insertBeforeRecord])
        XCTAssertFalse(violations[0].description.contains("secret-user-text"))
        XCTAssertEqual(violations[0].effectName, "insertCommittedText")
    }

    func testPostInsertVerificationBeforeInsertIsRejected() {
        let sequence = InputTurnEffectSequence(
            token: token(kind: .commitResult),
            effects: [
                .prepareAcceptedFeedback(text: "committed", acceptedAIRecommendation: nil),
                .recordCommitSideEffects(
                    text: "committed",
                    acceptedAIRecommendation: nil,
                    clientScope: .provided
                ),
                .schedulePostInsertCaretVerification,
                .insertCommittedText("committed", clientScope: .provided)
            ],
            handled: true
        )

        XCTAssertEqual(
            InputTurnSequenceValidator().validate(sequence).map(\.code),
            [.postInsertVerificationBeforeInsert]
        )
    }

    func testResetBeforeHideIsRejected() {
        let sequence = InputTurnEffectSequence(
            token: token(kind: .lifecycleFinish),
            effects: [
                .resetConversionEngine,
                .hideCandidatePanel(.reset),
                .resetCompositionStateAfterLifecycleFinish,
                .resetAnchorState,
                .invalidateSuggestion,
                .finishWriterLifecycle(shouldClearOwnedMarkedTextWhenEndingWithoutCommit: false)
            ],
            handled: false
        )

        XCTAssertEqual(
            InputTurnSequenceValidator().validate(sequence).map(\.code),
            [.lifecycleResetBeforeHide]
        )
    }

    func testDirectPassthroughClearMarkedTextIsRejected() {
        let sequence = InputTurnEffectSequence(
            token: token(kind: .directPassthrough),
            effects: [
                .cancelAIFeedback(reason: "idle_passthrough"),
                .hideCandidatePanel(.reset),
                .clearOwnedMarkedText,
                .resetConversionEngine,
                .resetCompositionStateAfterLifecycleFinish,
                .resetAnchorState,
                .invalidateSuggestion,
                .finishWriterLifecycle(shouldClearOwnedMarkedTextWhenEndingWithoutCommit: false),
                .insertDirectPassthroughText(" ")
            ],
            handled: true
        )

        XCTAssertEqual(
            InputTurnSequenceValidator().validate(sequence).map(\.code),
            [.directPassthroughClearsMarkedText]
        )
    }

    private func token(kind: InputTurnKind) -> InputTurnToken {
        InputTurnToken(turnID: 1, kind: kind, compositionSnapshot: snapshot(rawInput: "ni", compositionID: 7))
    }

    private func snapshot(rawInput: String, compositionID: Int) -> InputCompositionStateSnapshot {
        InputCompositionStateSnapshot(
            rawInput: rawInput,
            compositionBuffer: CompositionBuffer(rawInput: rawInput),
            compositionID: compositionID,
            rawRevision: 3,
            deleteCountBeforeCommit: 0
        )
    }

    private func finishPlan(
        reason: CompositionLifecycleFinishReason,
        compositionID: Int,
        commitText: String? = nil,
        shouldClearOwnedMarkedText: Bool
    ) -> InputCompositionLifecycleFinishPlan {
        InputCompositionLifecycleFinishPlan(
            reason: reason,
            panelVisibilityReason: reason.panelVisibilityReason,
            finishedCompositionID: compositionID,
            commitText: commitText,
            shouldClearOwnedMarkedText: shouldClearOwnedMarkedText,
            shouldPublishCompositionEnded: true
        )
    }
}
