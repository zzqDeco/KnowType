import KnowTypeCore
@testable import KnowTypeInputMethod
import XCTest

final class InputCompositionStateRuntimeTests: XCTestCase {
    func testInitialStateIsEmpty() {
        let snapshot = InputCompositionStateRuntime().currentSnapshot()

        XCTAssertEqual(snapshot.rawInput, "")
        XCTAssertEqual(snapshot.compositionBuffer, CompositionBuffer())
        XCTAssertEqual(snapshot.compositionID, 0)
        XCTAssertEqual(snapshot.rawRevision, 0)
        XCTAssertEqual(snapshot.deleteCountBeforeCommit, 0)
        XCTAssertFalse(snapshot.hasActiveTextComposition)
    }

    func testBeginOnlyIncrementsCompositionIDWhenIdle() {
        let runtime = InputCompositionStateRuntime()

        let first = runtime.beginCompositionIfNeeded()
        let second = runtime.beginCompositionIfNeeded()

        XCTAssertTrue(first.didBegin)
        XCTAssertEqual(first.snapshot.compositionID, 1)
        XCTAssertTrue(second.didBegin)
        XCTAssertEqual(second.snapshot.compositionID, 2)

        runtime.appendText("n")
        let active = runtime.beginCompositionIfNeeded()

        XCTAssertFalse(active.didBegin)
        XCTAssertEqual(active.snapshot.compositionID, 2)
    }

    func testAppendUpdatesRawBufferAndRevision() {
        let runtime = InputCompositionStateRuntime()
        runtime.beginCompositionIfNeeded()

        let snapshot = runtime.appendText("n")

        XCTAssertEqual(snapshot.rawInput, "n")
        XCTAssertEqual(snapshot.compositionBuffer.rawInput, "n")
        XCTAssertEqual(snapshot.rawRevision, 1)
        XCTAssertTrue(snapshot.hasActiveTextComposition)
    }

    func testDeleteRawCharacterUpdatesDeleteCountRevisionAndEmptyState() {
        let runtime = InputCompositionStateRuntime()
        runtime.beginCompositionIfNeeded()
        runtime.appendText("n")
        runtime.appendText("i")

        let firstDelete = runtime.deleteBackward()
        let secondDelete = runtime.deleteBackward()

        XCTAssertTrue(firstDelete.didDelete)
        XCTAssertTrue(firstDelete.removedRawCharacter)
        XCTAssertFalse(firstDelete.removedResolvedSegment)
        XCTAssertFalse(firstDelete.becameEmpty)
        XCTAssertEqual(firstDelete.snapshot.rawInput, "n")
        XCTAssertEqual(firstDelete.snapshot.rawRevision, 3)
        XCTAssertEqual(firstDelete.snapshot.deleteCountBeforeCommit, 1)

        XCTAssertTrue(secondDelete.becameEmpty)
        XCTAssertEqual(secondDelete.snapshot.rawInput, "")
        XCTAssertEqual(secondDelete.snapshot.rawRevision, 4)
        XCTAssertEqual(secondDelete.snapshot.deleteCountBeforeCommit, 0)
    }

    func testDeleteResolvedSegmentDoesNotRemoveRawCharacterOrAdvanceRevision() {
        let runtime = InputCompositionStateRuntime()
        runtime.beginCompositionIfNeeded()
        runtime.appendText("n")
        runtime.appendText("i")
        XCTAssertTrue(runtime.applySegmentCandidate(candidate(rawInput: "ni", text: "你")))

        let before = runtime.currentSnapshot()
        let result = runtime.deleteBackward()

        XCTAssertTrue(result.didDelete)
        XCTAssertFalse(result.removedRawCharacter)
        XCTAssertTrue(result.removedResolvedSegment)
        XCTAssertFalse(result.becameEmpty)
        XCTAssertEqual(result.snapshot.rawInput, "ni")
        XCTAssertEqual(result.snapshot.rawRevision, before.rawRevision)
        XCTAssertEqual(result.snapshot.deleteCountBeforeCommit, before.deleteCountBeforeCommit + 1)
        XCTAssertFalse(result.snapshot.compositionBuffer.hasResolvedSegments)
    }

    func testApplySegmentCandidatePreservesCompositionBufferSemantics() {
        let runtime = InputCompositionStateRuntime()
        runtime.beginCompositionIfNeeded()
        runtime.appendText("n")
        runtime.appendText("i")

        XCTAssertTrue(runtime.applySegmentCandidate(candidate(rawInput: "ni", text: "你")))

        let buffer = runtime.currentSnapshot().compositionBuffer
        XCTAssertEqual(buffer.displayText, "你")
        XCTAssertEqual(buffer.commitText, "你")
        XCTAssertTrue(buffer.isFullyResolved)
    }

    func testLifecycleCommitTextMatchesPolicy() {
        let runtime = InputCompositionStateRuntime()
        runtime.beginCompositionIfNeeded()
        runtime.appendText("n")
        runtime.appendText("i")

        XCTAssertNil(runtime.lifecycleCommitText(policy: .none))
        XCTAssertEqual(runtime.lifecycleCommitText(policy: .commitRawIfNeeded), "ni")

        XCTAssertTrue(runtime.applySegmentCandidate(candidate(rawInput: "ni", text: "你")))
        XCTAssertEqual(runtime.lifecycleCommitText(policy: .commitRawIfNeeded), "你")
    }

    func testResetAfterLifecycleClearsStateAndAdvancesRevisionWithoutChangingCompositionID() {
        let runtime = InputCompositionStateRuntime()
        runtime.beginCompositionIfNeeded()
        runtime.appendText("n")
        runtime.deleteBackward()
        let before = runtime.currentSnapshot()

        let after = runtime.resetAfterLifecycleFinish()

        XCTAssertEqual(after.rawInput, "")
        XCTAssertEqual(after.compositionBuffer, CompositionBuffer())
        XCTAssertEqual(after.deleteCountBeforeCommit, 0)
        XCTAssertEqual(after.rawRevision, before.rawRevision + 1)
        XCTAssertEqual(after.compositionID, before.compositionID)
    }

    func testNativeSnapshotRawSyncOnlyUpdatesWhenRawInputChanges() {
        let runtime = InputCompositionStateRuntime()
        runtime.beginCompositionIfNeeded()
        runtime.appendText("n")
        let before = runtime.currentSnapshot()

        XCTAssertFalse(runtime.syncRawInputFromNativeSnapshot(snapshot(rawInput: "n")))
        XCTAssertEqual(runtime.currentSnapshot(), before)

        XCTAssertTrue(runtime.syncRawInputFromNativeSnapshot(snapshot(rawInput: "ni")))
        let after = runtime.currentSnapshot()
        XCTAssertEqual(after.rawInput, "ni")
        XCTAssertEqual(after.compositionBuffer.rawInput, "ni")
        XCTAssertEqual(after.rawRevision, before.rawRevision + 1)
    }

    private func candidate(rawInput: String, text: String) -> CorrectionCandidate {
        CorrectionCandidate(
            text: text,
            source: "test",
            confidence: 1,
            correctionLevel: .none,
            rawRange: TextRange(start: 0, length: rawInput.count)
        )
    }

    private func snapshot(rawInput: String) -> ConversionEngineSnapshot {
        ConversionEngineSnapshot(
            rawInput: rawInput,
            preedit: rawInput,
            candidates: [],
            highlightedIndex: 0,
            pageSize: 0,
            pageNumber: 0,
            isLastPage: true,
            engineName: "test"
        )
    }
}
