import KnowTypeCore
@testable import KnowTypeInputMethod
import XCTest

final class InputCompositionLifecycleRuntimeTests: XCTestCase {
    func testIdleBeginReturnsPlanAndTracesOnlyOnce() {
        let runtime = InputCompositionLifecycleRuntime()
        let snapshot = compositionSnapshot(rawInput: "", compositionID: 0)

        let first = runtime.beginPlan(compositionSnapshot: snapshot)
        let second = runtime.beginPlan(compositionSnapshot: snapshot)

        XCTAssertTrue(first.shouldBegin)
        XCTAssertTrue(first.shouldTraceFirstCompositionBegin)
        XCTAssertEqual(first.feedbackCancellationReason, "new_composition")
        XCTAssertTrue(first.shouldReloadPreferences)
        XCTAssertTrue(first.shouldReloadRuntimeLexicon)
        XCTAssertTrue(first.shouldPublishCompositionStarted)
        XCTAssertTrue(first.shouldResetAnchor)

        XCTAssertTrue(second.shouldBegin)
        XCTAssertFalse(second.shouldTraceFirstCompositionBegin)
        XCTAssertEqual(second.feedbackCancellationReason, "new_composition")
    }

    func testActiveRawCompositionBeginReturnsNoop() {
        let plan = InputCompositionLifecycleRuntime().beginPlan(
            compositionSnapshot: compositionSnapshot(rawInput: "ni", compositionID: 7)
        )

        XCTAssertFalse(plan.shouldBegin)
        XCTAssertFalse(plan.shouldTraceFirstCompositionBegin)
        XCTAssertNil(plan.feedbackCancellationReason)
        XCTAssertFalse(plan.shouldReloadPreferences)
        XCTAssertFalse(plan.shouldReloadRuntimeLexicon)
        XCTAssertFalse(plan.shouldPublishCompositionStarted)
        XCTAssertFalse(plan.shouldResetAnchor)
    }

    func testActiveResolvedCompositionBeginReturnsNoop() {
        let plan = InputCompositionLifecycleRuntime().beginPlan(
            compositionSnapshot: compositionSnapshot(rawInput: "ni", compositionID: 7, resolvedText: "你")
        )

        XCTAssertFalse(plan.shouldBegin)
        XCTAssertFalse(plan.shouldPublishCompositionStarted)
    }

    func testFinishReasonMapsPanelVisibilityReason() {
        let runtime = InputCompositionLifecycleRuntime()
        let snapshot = compositionSnapshot(rawInput: "ni", compositionID: 9)

        XCTAssertEqual(
            runtime.finishPlan(
                reason: .commit,
                compositionSnapshot: snapshot,
                hasNativeComposition: false,
                commitText: nil
            ).panelVisibilityReason,
            .compositionEnded
        )
        XCTAssertEqual(
            runtime.finishPlan(
                reason: .deactivate,
                compositionSnapshot: snapshot,
                hasNativeComposition: false,
                commitText: nil
            ).panelVisibilityReason,
            .deactivate
        )
        XCTAssertEqual(
            runtime.finishPlan(
                reason: .close,
                compositionSnapshot: snapshot,
                hasNativeComposition: false,
                commitText: nil
            ).panelVisibilityReason,
            .close
        )
        XCTAssertEqual(
            runtime.finishPlan(
                reason: .reset,
                compositionSnapshot: snapshot,
                hasNativeComposition: false,
                commitText: nil
            ).panelVisibilityReason,
            .reset
        )
        XCTAssertEqual(
            runtime.finishPlan(
                reason: .nativeEnded,
                compositionSnapshot: snapshot,
                hasNativeComposition: false,
                commitText: nil
            ).panelVisibilityReason,
            .nativeEnded
        )
    }

    func testFinishWithCommitTextPlansInsertWithoutClearOnlyPath() {
        let plan = InputCompositionLifecycleRuntime().finishPlan(
            reason: .commit,
            compositionSnapshot: compositionSnapshot(rawInput: "ni", compositionID: 11),
            hasNativeComposition: true,
            commitText: "你"
        )

        XCTAssertEqual(plan.reason, .commit)
        XCTAssertEqual(plan.panelVisibilityReason, .compositionEnded)
        XCTAssertEqual(plan.finishedCompositionID, 11)
        XCTAssertEqual(plan.commitText, "你")
        XCTAssertTrue(plan.shouldClearOwnedMarkedText)
        XCTAssertTrue(plan.shouldPublishCompositionEnded)
    }

    func testFinishWithoutCommitClearsOwnedMarkedTextForActiveTextComposition() {
        let plan = InputCompositionLifecycleRuntime().finishPlan(
            reason: .reset,
            compositionSnapshot: compositionSnapshot(rawInput: "ni", compositionID: 12),
            hasNativeComposition: false,
            commitText: nil
        )

        XCTAssertEqual(plan.finishedCompositionID, 12)
        XCTAssertNil(plan.commitText)
        XCTAssertTrue(plan.shouldClearOwnedMarkedText)
    }

    func testFinishWithoutCommitClearsOwnedMarkedTextForNativeComposition() {
        let plan = InputCompositionLifecycleRuntime().finishPlan(
            reason: .nativeEnded,
            compositionSnapshot: compositionSnapshot(rawInput: "", compositionID: 13),
            hasNativeComposition: true,
            commitText: nil
        )

        XCTAssertEqual(plan.finishedCompositionID, 13)
        XCTAssertTrue(plan.shouldClearOwnedMarkedText)
    }

    func testFinishWithoutActiveCompositionDoesNotClearOwnedMarkedText() {
        let plan = InputCompositionLifecycleRuntime().finishPlan(
            reason: .close,
            compositionSnapshot: compositionSnapshot(rawInput: "", compositionID: 14),
            hasNativeComposition: false,
            commitText: nil
        )

        XCTAssertEqual(plan.panelVisibilityReason, .close)
        XCTAssertEqual(plan.finishedCompositionID, 14)
        XCTAssertFalse(plan.shouldClearOwnedMarkedText)
        XCTAssertTrue(plan.shouldPublishCompositionEnded)
    }

    private func compositionSnapshot(
        rawInput: String,
        compositionID: Int,
        resolvedText: String? = nil
    ) -> InputCompositionStateSnapshot {
        var buffer = CompositionBuffer(rawInput: rawInput)
        if let resolvedText {
            _ = buffer.apply(
                CorrectionCandidate(
                    text: resolvedText,
                    source: "test",
                    confidence: 1,
                    correctionLevel: .none,
                    rawRange: TextRange(start: 0, length: rawInput.count)
                )
            )
        }
        return InputCompositionStateSnapshot(
            rawInput: rawInput,
            compositionBuffer: buffer,
            compositionID: compositionID,
            rawRevision: 3,
            deleteCountBeforeCommit: 0
        )
    }
}
