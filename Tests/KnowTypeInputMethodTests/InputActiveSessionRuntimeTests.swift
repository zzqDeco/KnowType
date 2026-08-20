import Foundation
@testable import KnowTypeInputMethod
import XCTest

final class InputActiveSessionRuntimeTests: XCTestCase {
    func testTextAndSymbolSessionsAreMutuallyExclusiveWithMonotonicIDs() {
        let runtime = InputActiveSessionRuntime()

        XCTAssertEqual(runtime.currentSession, .none)

        runtime.beginTextCompositionIfNeeded()
        runtime.appendText("ni")
        guard case .text(let text) = runtime.currentSession else {
            return XCTFail("Expected an active text composition")
        }
        XCTAssertNil(
            runtime.beginSymbolComposition(
                trigger: "/",
                candidates: candidates,
                pageSize: 3,
                hostCursorSnapshot: hostSnapshot
            )
        )

        runtime.resetTextAfterLifecycleFinish()
        let symbol = runtime.beginSymbolComposition(
            trigger: "/",
            candidates: candidates,
            pageSize: 3,
            hostCursorSnapshot: hostSnapshot
        )
        XCTAssertNotNil(symbol)
        XCTAssertGreaterThan(symbol?.compositionID ?? 0, text.compositionID)
        XCTAssertEqual(runtime.currentSession, symbol.map(ActiveInputSession.symbol))

        _ = runtime.cancelSymbolComposition()
        runtime.beginTextCompositionIfNeeded()
        runtime.appendText("a")
        guard case .text(let nextText) = runtime.currentSession else {
            return XCTFail("Expected the next text composition")
        }
        XCTAssertGreaterThan(nextText.compositionID, symbol?.compositionID ?? 0)
    }

    func testSymbolCompositionCapturesImmutableContextAndDefaultPolicies() {
        let runtime = InputActiveSessionRuntime()

        let composition = runtime.beginSymbolComposition(
            trigger: "/",
            candidates: candidates,
            pageSize: 0,
            hostCursorSnapshot: hostSnapshot
        )

        XCTAssertEqual(composition?.trigger, "/")
        XCTAssertEqual(composition?.candidates, candidates)
        XCTAssertEqual(composition?.selectedIndex, 0)
        XCTAssertEqual(composition?.revision, 0)
        XCTAssertEqual(composition?.pageSize, 1)
        XCTAssertEqual(composition?.hostCursorSnapshot, hostSnapshot)
        XCTAssertNil(composition?.presentation)
        XCTAssertEqual(composition?.policies.commit, .selectedCandidate)
        XCTAssertEqual(composition?.policies.cancel, .discardSymbolOnly)
        XCTAssertEqual(composition?.policies.focus, .commitSelected)
        XCTAssertEqual(composition?.policies.shortcut, .cancelThenPassThrough)
        XCTAssertEqual(composition?.policies.fallthroughPolicy, .commitThenReplay)
    }

    func testNavigationClampsAtBoundariesAndOnlyChangesRevisionWhenSelectionMoves() {
        let runtime = makeSymbolRuntime(pageSize: 2)

        guard case .update(let first, .navigation) = runtime.transition(
            for: .moveCandidateSelection(.left)
        ) else {
            return XCTFail("Expected clamped navigation update")
        }
        XCTAssertEqual(first.selectedIndex, 0)
        XCTAssertEqual(first.revision, 0)

        guard case .update(let second, .navigation) = runtime.transition(
            for: .moveCandidateSelection(.right)
        ) else {
            return XCTFail("Expected navigation update")
        }
        XCTAssertEqual(second.selectedIndex, 1)
        XCTAssertEqual(second.revision, 1)

        guard case .update(let third, .navigation) = runtime.transition(
            for: .moveCandidateSelection(.pageDown)
        ) else {
            return XCTFail("Expected page navigation update")
        }
        XCTAssertEqual(third.selectedIndex, 3)
        XCTAssertEqual(third.revision, 2)

        guard case .update(let fourth, .navigation) = runtime.transition(
            for: .moveCandidateSelection(.right)
        ) else {
            return XCTFail("Expected clamped navigation update")
        }
        XCTAssertEqual(fourth.selectedIndex, 3)
        XCTAssertEqual(fourth.revision, 2)
    }

    func testPresentationAcknowledgementRequiresCurrentSessionRevisionAndHost() {
        let runtime = makeSymbolRuntime()
        let composition = try! XCTUnwrap(runtime.currentSymbolComposition)
        var presentedSnapshot = hostSnapshot
        presentedSnapshot.markedRange = NSRange(location: 7, length: 1)

        let presented = runtime.recordSymbolPresentation(
            compositionID: composition.compositionID,
            revision: composition.revision,
            carrier: .inline,
            hostCursorSnapshot: presentedSnapshot
        )

        XCTAssertEqual(presented?.revision, 0)
        XCTAssertEqual(presented?.presentation?.revision, 0)
        XCTAssertEqual(presented?.presentation?.carrier, .inline)
        XCTAssertEqual(presented?.focusValidationSnapshot, presentedSnapshot)

        XCTAssertNil(
            runtime.recordSymbolPresentation(
                compositionID: composition.compositionID,
                revision: composition.revision + 1,
                carrier: .placeholder,
                hostCursorSnapshot: presentedSnapshot
            )
        )

        var changedHost = presentedSnapshot
        changedHost.bundleIdentifier = "com.example.changed"
        XCTAssertNil(
            runtime.recordSymbolPresentation(
                compositionID: composition.compositionID,
                revision: composition.revision,
                carrier: .placeholder,
                hostCursorSnapshot: changedHost
            )
        )
        XCTAssertEqual(runtime.currentSymbolComposition?.presentation?.carrier, .inline)
    }

    func testFocusLifecycleUsesLatestSuccessfulPresentationSnapshot() {
        let runtime = makeSymbolRuntime()
        let composition = try! XCTUnwrap(runtime.currentSymbolComposition)
        var presentedSnapshot = hostSnapshot
        presentedSnapshot.markedRange = NSRange(location: 7, length: 1)
        XCTAssertNotNil(
            runtime.recordSymbolPresentation(
                compositionID: composition.compositionID,
                revision: composition.revision,
                carrier: .inline,
                hostCursorSnapshot: presentedSnapshot
            )
        )

        guard case .commit(_, let candidate, nil, .focusCommit) =
            runtime.transition(for: .clickOutside(currentHostSnapshot: presentedSnapshot)) else {
            return XCTFail("Expected focus commit from the presented host snapshot")
        }

        XCTAssertEqual(candidate.text, "、")
    }

    func testClampedNavigationPreservesCurrentPresentation() {
        let runtime = makeSymbolRuntime()
        let composition = try! XCTUnwrap(runtime.currentSymbolComposition)
        XCTAssertNotNil(
            runtime.recordSymbolPresentation(
                compositionID: composition.compositionID,
                revision: composition.revision,
                carrier: .inline,
                hostCursorSnapshot: hostSnapshot
            )
        )

        guard case .update(let clamped, .navigation) = runtime.transition(
            for: .moveCandidateSelection(.left)
        ) else {
            return XCTFail("Expected clamped navigation")
        }

        XCTAssertEqual(clamped.revision, 0)
        XCTAssertEqual(clamped.presentation?.revision, 0)
    }

    func testRepeatedTriggerCyclesSelectionAndRevision() {
        let runtime = makeSymbolRuntime()

        guard case .update(let first, .repeatedTrigger) = runtime.transition(for: .symbol("/")),
              case .update(let second, .repeatedTrigger) = runtime.transition(for: .symbol("/")) else {
            return XCTFail("Expected repeated-trigger updates")
        }

        XCTAssertEqual(first.selectedIndex, 1)
        XCTAssertEqual(first.revision, 1)
        XCTAssertEqual(second.selectedIndex, 2)
        XCTAssertEqual(second.revision, 2)
    }

    func testCommitCancelAndPrintableReplayPlansClearTheSymbolSession() {
        let numberRuntime = makeSymbolRuntime(pageSize: 2)
        guard case .commit(let numberComposition, let numberCandidate, nil, .numberSelection) =
            numberRuntime.transition(for: .selectCandidate(2)) else {
            return XCTFail("Expected visible-number commit")
        }
        XCTAssertEqual(numberComposition.selectedIndex, 1)
        XCTAssertEqual(numberCandidate.text, "/")
        XCTAssertEqual(numberRuntime.currentSession, .none)

        let cancelRuntime = makeSymbolRuntime()
        guard case .cancel(_, nil, true, .explicitCancel) =
            cancelRuntime.transition(for: .deleteBackward) else {
            return XCTFail("Expected symbol-only cancellation")
        }
        XCTAssertEqual(cancelRuntime.currentSession, .none)

        let replayRuntime = makeSymbolRuntime()
        guard case .commit(_, let replayCandidate, .append("a"), .printableFallthrough) =
            replayRuntime.transition(for: .append("a")) else {
            return XCTFail("Expected commit-and-replay")
        }
        XCTAssertEqual(replayCandidate.text, "、")
        XCTAssertEqual(replayRuntime.currentSession, .none)
    }

    func testInvalidNumberCommitsCurrentCandidateAndReplaysNumberOnce() {
        let runtime = makeSymbolRuntime(pageSize: 2)

        guard case .commit(_, let candidate, .selectCandidate(9), .printableFallthrough) =
            runtime.transition(for: .selectCandidate(9)) else {
            return XCTFail("Expected invalid-number replay")
        }

        XCTAssertEqual(candidate.text, "、")
        XCTAssertEqual(runtime.currentSession, .none)
    }

    func testPanelSelectionAndMouseCommitUseValuePlans() {
        let runtime = makeSymbolRuntime()

        guard case .update(let selected, .panelSelection) =
            runtime.transitionForPanelSelection(at: 2) else {
            return XCTFail("Expected panel-selection update")
        }
        XCTAssertEqual(selected.selectedIndex, 2)
        XCTAssertEqual(selected.revision, 1)

        guard case .commit(let committed, let candidate, nil, .mouseCommit) =
            runtime.transitionForMouseCommit(at: 2) else {
            return XCTFail("Expected mouse commit")
        }
        XCTAssertEqual(committed.selectedIndex, 2)
        XCTAssertEqual(candidate.text, "／")
        XCTAssertEqual(runtime.currentSession, .none)
    }

    func testHostShortcutCancelsAndReturnsUnhandledWhileModifierKeepsSession() {
        let modifierRuntime = makeSymbolRuntime()
        guard case .keep(let composition, false, .hostCommand) =
            modifierRuntime.transition(for: .modifierFlagsChanged([.shift])) else {
            return XCTFail("Expected modifier pass-through")
        }
        XCTAssertEqual(modifierRuntime.currentSession, .symbol(composition))

        let shortcutRuntime = makeSymbolRuntime()
        guard case .cancel(_, nil, false, .hostShortcut) =
            shortcutRuntime.transition(for: .hostShortcut) else {
            return XCTFail("Expected host-shortcut cancellation")
        }
        XCTAssertEqual(shortcutRuntime.currentSession, .none)
    }

    func testFocusAndLifecycleTransitionsFollowClientAvailability() {
        let focusRuntime = makeSymbolRuntime()
        guard case .commit(_, let candidate, nil, .focusCommit) =
            focusRuntime.transition(for: .deactivate(currentHostSnapshot: hostSnapshot)) else {
            return XCTFail("Expected focus commit")
        }
        XCTAssertEqual(candidate.text, "、")

        let missingClientRuntime = makeSymbolRuntime()
        guard case .cancel(_, nil, true, .missingClientCancel) =
            missingClientRuntime.transition(for: .clickOutside(currentHostSnapshot: nil)) else {
            return XCTFail("Expected missing-client cancellation")
        }

        let changedHostRuntime = makeSymbolRuntime()
        var changedHostSnapshot = hostSnapshot
        changedHostSnapshot.selectedRange.location += 1
        guard case .cancel(_, nil, true, .hostContextChanged) =
            changedHostRuntime.transition(
                for: .clickOutside(currentHostSnapshot: changedHostSnapshot)
            ) else {
            return XCTFail("Expected changed-host cancellation")
        }

        let resetRuntime = makeSymbolRuntime()
        guard case .cancel(_, nil, true, .lifecycleCancel) =
            resetRuntime.transition(for: .controllerClose) else {
            return XCTFail("Expected close cancellation")
        }

        let generationRuntime = makeSymbolRuntime()
        guard case .cancel(_, nil, true, .generationChange) =
            generationRuntime.transition(for: .inputModeGenerationChanged) else {
            return XCTFail("Expected generation-change cancellation")
        }
    }

    private var candidates: [InputSymbolCandidate] {
        [
            InputSymbolCandidate(text: "、"),
            InputSymbolCandidate(text: "/"),
            InputSymbolCandidate(text: "／"),
            InputSymbolCandidate(text: "÷")
        ]
    }

    private var hostSnapshot: InputHostCursorSnapshot {
        InputHostCursorSnapshot(
            selectedRange: NSRange(location: 7, length: 2),
            markedRange: NSRange(location: 5, length: 2),
            hostIdentity: nil,
            bundleIdentifier: "com.example.host"
        )
    }

    private func makeSymbolRuntime(pageSize: Int = 3) -> InputActiveSessionRuntime {
        let runtime = InputActiveSessionRuntime()
        XCTAssertNotNil(
            runtime.beginSymbolComposition(
                trigger: "/",
                candidates: candidates,
                pageSize: pageSize,
                hostCursorSnapshot: hostSnapshot
            )
        )
        return runtime
    }
}
