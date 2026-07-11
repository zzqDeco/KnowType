import KnowTypeAI
import KnowTypeCore
@testable import KnowTypeInputMethod
import XCTest

final class InputTurnSequencingRuntimeTests: XCTestCase {
    func testCommitInsertSequencePreservesOrderAndPostInsertVerificationForAI() {
        let runtime = InputTurnSequencingRuntime()
        let token = runtime.beginTurn(kind: .commitResult, snapshot: snapshot(rawInput: "ni", compositionID: 4))
        let aiCandidate = AIRecommendationCandidate(
            prefixText: "你",
            continuationText: "好",
            displayText: "你好",
            confidence: 0.8,
            provider: "test",
            contextVersion: "v1"
        )
        let resetPlan = finishPlan(reason: .reset, compositionID: 4, shouldClearOwnedMarkedText: true)

        let sequence = runtime.commitSequence(
            token: token,
            applicationPlan: .insertAndReset("你好"),
            acceptedAIRecommendation: aiCandidate,
            resetPlan: resetPlan
        )

        XCTAssertTrue(sequence.handled)
        assertNoSequenceViolations(sequence)
        XCTAssertEqual(sequence.token.turnID, 1)
        XCTAssertEqual(
            sequence.effects,
            [
                .prepareAcceptedFeedback(text: "你好", acceptedAIRecommendation: aiCandidate),
                .recordCommitSideEffects(
                    text: "你好",
                    acceptedAIRecommendation: aiCandidate,
                    commitKindOverride: nil,
                    clientScope: .provided
                ),
                .insertCommittedText("你好", clientScope: .provided),
                .schedulePostInsertCaretVerification,
                .hideCandidatePanel(.reset),
                .clearOwnedMarkedText,
                .resetConversionEngine,
                .resetCompositionStateAfterLifecycleFinish,
                .resetAnchorState,
                .invalidateSuggestion,
                .finishWriterLifecycle(shouldClearOwnedMarkedTextWhenEndingWithoutCommit: true),
                .publishCompositionEnded(reason: .reset, compositionID: 4)
            ]
        )
    }

    func testLifecycleFinishSequenceKeepsPreResetCompositionIDAndOrder() {
        let runtime = InputTurnSequencingRuntime()
        let token = runtime.beginTurn(kind: .lifecycleFinish, snapshot: snapshot(rawInput: "ni", compositionID: 9))
        let plan = finishPlan(
            reason: .deactivate,
            compositionID: 9,
            commitText: "ni",
            shouldClearOwnedMarkedText: true
        )

        let sequence = runtime.lifecycleFinishSequence(token: token, finishPlan: plan)

        XCTAssertTrue(sequence.handled)
        assertNoSequenceViolations(sequence)
        XCTAssertEqual(sequence.token.compositionID, 9)
        XCTAssertEqual(
            sequence.effects,
            [
                .hideCandidatePanel(.deactivate),
                .recordCommitSideEffects(
                    text: "ni",
                    acceptedAIRecommendation: nil,
                    commitKindOverride: nil,
                    clientScope: .effective
                ),
                .insertCommittedText("ni", clientScope: .effective),
                .resetConversionEngine,
                .resetCompositionStateAfterLifecycleFinish,
                .resetAnchorState,
                .invalidateSuggestion,
                .finishWriterLifecycle(shouldClearOwnedMarkedTextWhenEndingWithoutCommit: true),
                .publishCompositionEnded(reason: .deactivate, compositionID: 9)
            ]
        )
    }

    func testNativeCommitWithStillCompositionSyncsNativeSnapshotAfterInsert() {
        let runtime = InputTurnSequencingRuntime()
        let token = runtime.beginTurn(kind: .nativeCommit, snapshot: snapshot(rawInput: "ni", compositionID: 5))
        let nativeSnapshot = ConversionEngineSnapshot(rawInput: "n", preedit: "n")

        let sequence = runtime.nativeCommitSequence(token: token, text: "你", snapshot: nativeSnapshot)

        XCTAssertTrue(sequence.handled)
        assertNoSequenceViolations(sequence)
        XCTAssertEqual(
            sequence.effects,
            [
                .recordCommitSideEffects(
                    text: "你",
                    acceptedAIRecommendation: nil,
                    commitKindOverride: nil,
                    clientScope: .provided
                ),
                .insertCommittedText("你", clientScope: .provided),
                .syncRawInputFromNativeSnapshot(nativeSnapshot),
                .publishLocalSuggestion
            ]
        )
    }

    func testDirectPassthroughCancelsFeedbackBeforeResetAndInsertWithoutHostClear() {
        let runtime = InputTurnSequencingRuntime()
        let token = runtime.beginTurn(kind: .directPassthrough, snapshot: snapshot(rawInput: "", compositionID: 12))
        let resetPlan = finishPlan(reason: .reset, compositionID: 12, shouldClearOwnedMarkedText: false)

        let sequence = runtime.directPassthroughSequence(token: token, text: " ", resetPlan: resetPlan)

        XCTAssertTrue(sequence.handled)
        assertNoSequenceViolations(sequence)
        XCTAssertEqual(
            sequence.effects,
            [
                .cancelAIFeedback(reason: "idle_passthrough"),
                .hideCandidatePanel(.reset),
                .resetConversionEngine,
                .resetCompositionStateAfterLifecycleFinish,
                .resetAnchorState,
                .invalidateSuggestion,
                .finishWriterLifecycle(shouldClearOwnedMarkedTextWhenEndingWithoutCommit: false),
                .publishCompositionEnded(reason: .reset, compositionID: 12),
                .insertDirectPassthroughText(" ")
            ]
        )
    }

    private func assertNoSequenceViolations(
        _ sequence: InputTurnEffectSequence,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(InputTurnSequenceValidator().validate(sequence), [], file: file, line: line)
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
