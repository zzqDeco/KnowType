import Foundation
import KnowTypeCore

struct InputCompositionStateSnapshot: Sendable, Equatable {
    var rawInput: String
    var compositionBuffer: CompositionBuffer
    var compositionID: Int
    var rawRevision: Int
    var deleteCountBeforeCommit: Int

    var hasActiveTextComposition: Bool {
        !rawInput.isEmpty || compositionBuffer.hasResolvedSegments
    }
}

struct InputCompositionBeginResult: Sendable, Equatable {
    var didBegin: Bool
    var snapshot: InputCompositionStateSnapshot
}

struct InputCompositionDeleteResult: Sendable, Equatable {
    var didDelete: Bool
    var removedRawCharacter: Bool
    var removedResolvedSegment: Bool
    var becameEmpty: Bool
    var snapshot: InputCompositionStateSnapshot
}

enum InputCompositionLifecycleCommitPolicy: Sendable, Equatable {
    case none
    case commitRawIfNeeded
}

final class InputCompositionStateRuntime: @unchecked Sendable {
    private var rawInput = ""
    private var compositionBuffer = CompositionBuffer()
    private var compositionID = 0
    private var rawRevision = 0
    private var deleteCountBeforeCommit = 0

    func currentSnapshot() -> InputCompositionStateSnapshot {
        InputCompositionStateSnapshot(
            rawInput: rawInput,
            compositionBuffer: compositionBuffer,
            compositionID: compositionID,
            rawRevision: rawRevision,
            deleteCountBeforeCommit: deleteCountBeforeCommit
        )
    }

    @discardableResult
    func beginCompositionIfNeeded(compositionID requestedCompositionID: Int? = nil) -> InputCompositionBeginResult {
        guard rawInput.isEmpty else {
            return InputCompositionBeginResult(didBegin: false, snapshot: currentSnapshot())
        }
        compositionBuffer = CompositionBuffer()
        compositionID = requestedCompositionID ?? compositionID + 1
        return InputCompositionBeginResult(didBegin: true, snapshot: currentSnapshot())
    }

    @discardableResult
    func appendText(_ text: String) -> InputCompositionStateSnapshot {
        rawInput.append(text)
        rawRevision += 1
        compositionBuffer.updateRawInput(rawInput)
        return currentSnapshot()
    }

    @discardableResult
    func deleteBackward() -> InputCompositionDeleteResult {
        guard !rawInput.isEmpty else {
            return InputCompositionDeleteResult(
                didDelete: false,
                removedRawCharacter: false,
                removedResolvedSegment: false,
                becameEmpty: false,
                snapshot: currentSnapshot()
            )
        }

        deleteCountBeforeCommit += 1
        if compositionBuffer.undoLastResolvedSegment() {
            return InputCompositionDeleteResult(
                didDelete: true,
                removedRawCharacter: false,
                removedResolvedSegment: true,
                becameEmpty: false,
                snapshot: currentSnapshot()
            )
        }

        rawInput.removeLast()
        rawRevision += 1
        compositionBuffer.updateRawInput(rawInput)
        let becameEmpty = rawInput.isEmpty
        if becameEmpty {
            deleteCountBeforeCommit = 0
        }
        return InputCompositionDeleteResult(
            didDelete: true,
            removedRawCharacter: true,
            removedResolvedSegment: false,
            becameEmpty: becameEmpty,
            snapshot: currentSnapshot()
        )
    }

    @discardableResult
    func applySegmentCandidate(_ candidate: CorrectionCandidate) -> Bool {
        compositionBuffer.apply(candidate)
    }

    @discardableResult
    func syncRawInputFromNativeSnapshot(_ snapshot: ConversionEngineSnapshot) -> Bool {
        guard rawInput != snapshot.rawInput else {
            return false
        }
        rawInput = snapshot.rawInput
        rawRevision += 1
        compositionBuffer.updateRawInput(rawInput)
        return true
    }

    @discardableResult
    func incrementCompositionIDForAnchorReset() -> InputCompositionStateSnapshot {
        compositionID += 1
        return currentSnapshot()
    }

    @discardableResult
    func replaceCompositionID(_ compositionID: Int) -> InputCompositionStateSnapshot {
        self.compositionID = compositionID
        return currentSnapshot()
    }

    @discardableResult
    func resetAfterLifecycleFinish() -> InputCompositionStateSnapshot {
        rawInput = ""
        compositionBuffer = CompositionBuffer()
        rawRevision += 1
        deleteCountBeforeCommit = 0
        return currentSnapshot()
    }

    func lifecycleCommitText(policy: InputCompositionLifecycleCommitPolicy) -> String? {
        switch policy {
        case .none:
            return nil
        case .commitRawIfNeeded:
            if compositionBuffer.hasResolvedSegments {
                return compositionBuffer.commitText
            }
            return rawInput.isEmpty ? nil : rawInput
        }
    }
}
