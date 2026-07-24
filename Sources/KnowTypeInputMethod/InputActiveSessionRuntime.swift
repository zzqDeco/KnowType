import Foundation
import KnowTypeCore

typealias TextComposition = InputCompositionStateSnapshot

struct InputHostCursorSnapshot: Sendable, Equatable {
    var selectedRange: NSRange
    var markedRange: NSRange?
    var hostIdentity: ObjectIdentifier?
    var bundleIdentifier: String?
}

enum SymbolCompositionCommitPolicy: Sendable, Equatable {
    case selectedCandidate
}

enum SymbolCompositionCancelPolicy: Sendable, Equatable {
    case discardSymbolOnly
}

enum SymbolCompositionFocusPolicy: Sendable, Equatable {
    case commitSelected
}

enum SymbolCompositionShortcutPolicy: Sendable, Equatable {
    case cancelThenPassThrough
}

enum SymbolCompositionFallthroughPolicy: Sendable, Equatable {
    case commitThenReplay
}

struct SymbolCompositionPolicies: Sendable, Equatable {
    var commit: SymbolCompositionCommitPolicy = .selectedCandidate
    var cancel: SymbolCompositionCancelPolicy = .discardSymbolOnly
    var focus: SymbolCompositionFocusPolicy = .commitSelected
    var shortcut: SymbolCompositionShortcutPolicy = .cancelThenPassThrough
    var fallthroughPolicy: SymbolCompositionFallthroughPolicy = .commitThenReplay
}

struct SymbolComposition: Sendable, Equatable {
    let trigger: String
    let candidates: [InputSymbolCandidate]
    var selectedIndex: Int
    let compositionID: Int
    var revision: Int
    let pageSize: Int
    let hostCursorSnapshot: InputHostCursorSnapshot
    let policies: SymbolCompositionPolicies

    var selectedCandidate: InputSymbolCandidate? {
        candidates.indices.contains(selectedIndex) ? candidates[selectedIndex] : nil
    }

    var currentPage: Int {
        selectedIndex / max(1, pageSize)
    }

    var visibleRange: Range<Int> {
        let start = currentPage * max(1, pageSize)
        return start..<min(start + max(1, pageSize), candidates.count)
    }
}

enum ActiveInputSession: Sendable, Equatable {
    case none
    case text(TextComposition)
    case symbol(SymbolComposition)
}

enum SymbolCompositionTransitionReason: String, Sendable, Equatable {
    case navigation
    case panelSelection
    case mouseCommit
    case numberSelection
    case repeatedTrigger
    case explicitCommit
    case explicitCancel
    case printableFallthrough
    case hostShortcut
    case hostCommand
    case focusCommit
    case missingClientCancel
    case lifecycleCommit
    case lifecycleCancel
    case generationChange
}

enum SymbolCompositionLifecycleEvent: Sendable, Equatable {
    case commitComposition
    case clickOutside(hasUsableClient: Bool)
    case deactivate(hasUsableClient: Bool)
    case reset
    case controllerClose
    case inputModeGenerationChanged
}

enum SymbolCompositionTransitionPlan: Sendable, Equatable {
    case keep(
        composition: SymbolComposition,
        handled: Bool,
        reason: SymbolCompositionTransitionReason
    )
    case update(
        composition: SymbolComposition,
        reason: SymbolCompositionTransitionReason
    )
    case commit(
        composition: SymbolComposition,
        candidate: InputSymbolCandidate,
        replayIntent: InputKeyIntent?,
        reason: SymbolCompositionTransitionReason
    )
    case cancel(
        composition: SymbolComposition,
        replayIntent: InputKeyIntent?,
        handled: Bool,
        reason: SymbolCompositionTransitionReason
    )
}

final class InputActiveSessionRuntime: @unchecked Sendable {
    private let textRuntime: InputCompositionStateRuntime
    private var symbolComposition: SymbolComposition?
    private var nextCompositionID: Int

    init(textRuntime: InputCompositionStateRuntime = InputCompositionStateRuntime()) {
        self.textRuntime = textRuntime
        self.nextCompositionID = textRuntime.currentSnapshot().compositionID
    }

    var currentSession: ActiveInputSession {
        if let symbolComposition {
            return .symbol(symbolComposition)
        }
        let text = textRuntime.currentSnapshot()
        return text.hasActiveTextComposition ? .text(text) : .none
    }

    var currentTextSnapshot: InputCompositionStateSnapshot {
        textRuntime.currentSnapshot()
    }

    var currentSymbolComposition: SymbolComposition? {
        symbolComposition
    }

    var currentCompositionID: Int {
        switch currentSession {
        case .none:
            return textRuntime.currentSnapshot().compositionID
        case .text(let text):
            return text.compositionID
        case .symbol(let symbol):
            return symbol.compositionID
        }
    }

    var currentRevision: Int {
        switch currentSession {
        case .none, .text:
            return textRuntime.currentSnapshot().rawRevision
        case .symbol(let symbol):
            return symbol.revision
        }
    }

    @discardableResult
    func beginTextCompositionIfNeeded() -> InputCompositionBeginResult {
        precondition(symbolComposition == nil, "Cannot begin text while a symbol composition is active.")
        let snapshot = textRuntime.currentSnapshot()
        guard !snapshot.hasActiveTextComposition else {
            return InputCompositionBeginResult(didBegin: false, snapshot: snapshot)
        }
        nextCompositionID += 1
        return textRuntime.beginCompositionIfNeeded(compositionID: nextCompositionID)
    }

    @discardableResult
    func appendText(_ text: String) -> InputCompositionStateSnapshot {
        precondition(symbolComposition == nil, "Cannot append text while a symbol composition is active.")
        return textRuntime.appendText(text)
    }

    @discardableResult
    func deleteBackward() -> InputCompositionDeleteResult {
        precondition(symbolComposition == nil, "Cannot delete text while a symbol composition is active.")
        return textRuntime.deleteBackward()
    }

    @discardableResult
    func applySegmentCandidate(_ candidate: CorrectionCandidate) -> Bool {
        precondition(symbolComposition == nil, "Cannot mutate text while a symbol composition is active.")
        return textRuntime.applySegmentCandidate(candidate)
    }

    @discardableResult
    func syncRawInputFromNativeSnapshot(_ snapshot: ConversionEngineSnapshot) -> Bool {
        precondition(symbolComposition == nil, "Cannot synchronize text while a symbol composition is active.")
        return textRuntime.syncRawInputFromNativeSnapshot(snapshot)
    }

    func lifecycleCommitText(policy: InputCompositionLifecycleCommitPolicy) -> String? {
        textRuntime.lifecycleCommitText(policy: policy)
    }

    @discardableResult
    func resetTextAfterLifecycleFinish() -> InputCompositionStateSnapshot {
        textRuntime.resetAfterLifecycleFinish()
    }

    @discardableResult
    func incrementCompositionIDForAnchorReset() -> InputCompositionStateSnapshot {
        precondition(symbolComposition == nil, "Cannot reset a text anchor while a symbol composition is active.")
        nextCompositionID += 1
        return textRuntime.replaceCompositionID(nextCompositionID)
    }

    @discardableResult
    func beginSymbolComposition(
        trigger: String,
        candidates: [InputSymbolCandidate],
        pageSize: Int,
        hostCursorSnapshot: InputHostCursorSnapshot,
        policies: SymbolCompositionPolicies = SymbolCompositionPolicies()
    ) -> SymbolComposition? {
        guard symbolComposition == nil,
              !textRuntime.currentSnapshot().hasActiveTextComposition,
              !candidates.isEmpty else {
            return nil
        }
        nextCompositionID += 1
        let composition = SymbolComposition(
            trigger: trigger,
            candidates: candidates,
            selectedIndex: 0,
            compositionID: nextCompositionID,
            revision: 0,
            pageSize: max(1, pageSize),
            hostCursorSnapshot: hostCursorSnapshot,
            policies: policies
        )
        symbolComposition = composition
        return composition
    }

    @discardableResult
    func moveSymbolSelection(_ navigation: InputCandidateNavigation) -> SymbolComposition? {
        guard var composition = symbolComposition else {
            return nil
        }
        let previousIndex = composition.selectedIndex
        switch navigation {
        case .left, .up:
            composition.selectedIndex = max(0, previousIndex - 1)
        case .right, .down:
            composition.selectedIndex = min(composition.candidates.count - 1, previousIndex + 1)
        case .pageUp:
            composition.selectedIndex = pagedIndex(
                from: previousIndex,
                pageDelta: -1,
                pageSize: composition.pageSize,
                candidateCount: composition.candidates.count
            )
        case .pageDown:
            composition.selectedIndex = pagedIndex(
                from: previousIndex,
                pageDelta: 1,
                pageSize: composition.pageSize,
                candidateCount: composition.candidates.count
            )
        }
        if composition.selectedIndex != previousIndex {
            composition.revision += 1
        }
        symbolComposition = composition
        return composition
    }

    @discardableResult
    func selectSymbolCandidate(at index: Int) -> SymbolComposition? {
        guard var composition = symbolComposition,
              composition.candidates.indices.contains(index) else {
            return nil
        }
        if composition.selectedIndex != index {
            composition.selectedIndex = index
            composition.revision += 1
        }
        symbolComposition = composition
        return composition
    }

    @discardableResult
    func selectVisibleSymbolShortcut(_ number: Int) -> SymbolComposition? {
        guard let composition = symbolComposition,
              number > 0 else {
            return nil
        }
        let index = composition.visibleRange.lowerBound + number - 1
        guard composition.visibleRange.contains(index) else {
            return nil
        }
        return selectSymbolCandidate(at: index)
    }

    @discardableResult
    func advanceRepeatedTrigger(_ trigger: String) -> SymbolComposition? {
        guard var composition = symbolComposition,
              composition.trigger == trigger,
              !composition.candidates.isEmpty else {
            return nil
        }
        composition.selectedIndex = (composition.selectedIndex + 1) % composition.candidates.count
        composition.revision += 1
        symbolComposition = composition
        return composition
    }

    func transition(for intent: InputKeyIntent) -> SymbolCompositionTransitionPlan? {
        guard let composition = symbolComposition else {
            return nil
        }
        switch intent {
        case .action(.space), .action(.commitRaw):
            return finishSymbolComposition(
                composition,
                replayIntent: nil,
                reason: .explicitCommit
            )
        case .selectCandidate(let number) where number > 0:
            guard let selected = selectVisibleSymbolShortcut(number) else {
                return fallThroughSymbolComposition(
                    composition,
                    intent: intent,
                    reason: .printableFallthrough
                )
            }
            return finishSymbolComposition(
                selected,
                replayIntent: nil,
                reason: .numberSelection
            )
        case .selectCandidate:
            return fallThroughSymbolComposition(
                composition,
                intent: intent,
                reason: .printableFallthrough
            )
        case .moveCandidateSelection(let navigation):
            guard let updated = moveSymbolSelection(navigation) else {
                return nil
            }
            return .update(composition: updated, reason: .navigation)
        case .cancelComposition, .deleteBackward:
            return cancelSymbolComposition(
                composition,
                reason: .explicitCancel
            )
        case .symbol(let trigger):
            if let updated = advanceRepeatedTrigger(trigger) {
                return .update(composition: updated, reason: .repeatedTrigger)
            }
            return fallThroughSymbolComposition(
                composition,
                intent: intent,
                reason: .printableFallthrough
            )
        case .append:
            return fallThroughSymbolComposition(
                composition,
                intent: intent,
                reason: .printableFallthrough
            )
        case .hostShortcut:
            return handleHostShortcut(composition)
        case .action(.toggleSymbolMode),
             .action(.toggleTextMode),
             .action(.toggleSymbolWidth),
             .action(.tab),
             .action(.optionNumber):
            return cancelSymbolComposition(
                composition,
                replayIntent: intent,
                handled: true,
                reason: .hostCommand
            )
        case .modifierFlagsChanged, .ignored:
            return .keep(
                composition: composition,
                handled: false,
                reason: .hostCommand
            )
        }
    }

    func transitionForPanelSelection(at index: Int) -> SymbolCompositionTransitionPlan? {
        guard let composition = selectSymbolCandidate(at: index) else {
            return nil
        }
        return .update(composition: composition, reason: .panelSelection)
    }

    func transitionForMouseCommit(at index: Int) -> SymbolCompositionTransitionPlan? {
        guard let composition = selectSymbolCandidate(at: index) else {
            return nil
        }
        return finishSymbolComposition(
            composition,
            replayIntent: nil,
            reason: .mouseCommit
        )
    }

    func transition(
        for event: SymbolCompositionLifecycleEvent
    ) -> SymbolCompositionTransitionPlan? {
        guard let composition = symbolComposition else {
            return nil
        }
        switch event {
        case .commitComposition:
            return finishSymbolComposition(
                composition,
                replayIntent: nil,
                reason: .lifecycleCommit
            )
        case .clickOutside(let hasUsableClient),
             .deactivate(let hasUsableClient):
            if hasUsableClient {
                return commitSymbolCompositionForFocus(composition)
            }
            return cancelSymbolComposition(
                composition,
                reason: .missingClientCancel
            )
        case .reset, .controllerClose:
            return cancelSymbolComposition(
                composition,
                reason: .lifecycleCancel
            )
        case .inputModeGenerationChanged:
            return cancelSymbolComposition(
                composition,
                reason: .generationChange
            )
        }
    }

    @discardableResult
    func cancelSymbolComposition() -> SymbolComposition? {
        defer { symbolComposition = nil }
        return symbolComposition
    }

    private func finishSymbolComposition(
        _ composition: SymbolComposition,
        replayIntent: InputKeyIntent?,
        reason: SymbolCompositionTransitionReason
    ) -> SymbolCompositionTransitionPlan? {
        switch composition.policies.commit {
        case .selectedCandidate:
            guard let candidate = composition.selectedCandidate else {
                return nil
            }
            symbolComposition = nil
            return .commit(
                composition: composition,
                candidate: candidate,
                replayIntent: replayIntent,
                reason: reason
            )
        }
    }

    private func cancelSymbolComposition(
        _ composition: SymbolComposition,
        replayIntent: InputKeyIntent? = nil,
        handled: Bool = true,
        reason: SymbolCompositionTransitionReason
    ) -> SymbolCompositionTransitionPlan {
        switch composition.policies.cancel {
        case .discardSymbolOnly:
            symbolComposition = nil
            return .cancel(
                composition: composition,
                replayIntent: replayIntent,
                handled: handled,
                reason: reason
            )
        }
    }

    private func commitSymbolCompositionForFocus(
        _ composition: SymbolComposition
    ) -> SymbolCompositionTransitionPlan? {
        switch composition.policies.focus {
        case .commitSelected:
            return finishSymbolComposition(
                composition,
                replayIntent: nil,
                reason: .focusCommit
            )
        }
    }

    private func handleHostShortcut(
        _ composition: SymbolComposition
    ) -> SymbolCompositionTransitionPlan {
        switch composition.policies.shortcut {
        case .cancelThenPassThrough:
            return cancelSymbolComposition(
                composition,
                handled: false,
                reason: .hostShortcut
            )
        }
    }

    private func fallThroughSymbolComposition(
        _ composition: SymbolComposition,
        intent: InputKeyIntent,
        reason: SymbolCompositionTransitionReason
    ) -> SymbolCompositionTransitionPlan? {
        switch composition.policies.fallthroughPolicy {
        case .commitThenReplay:
            return finishSymbolComposition(
                composition,
                replayIntent: intent,
                reason: reason
            )
        }
    }

    private func pagedIndex(
        from index: Int,
        pageDelta: Int,
        pageSize: Int,
        candidateCount: Int
    ) -> Int {
        guard candidateCount > 0 else {
            return 0
        }
        let normalizedPageSize = max(1, pageSize)
        let pageCount = (candidateCount + normalizedPageSize - 1) / normalizedPageSize
        let currentPage = index / normalizedPageSize
        let currentOffset = index - currentPage * normalizedPageSize
        let targetPage = min(max(currentPage + pageDelta, 0), pageCount - 1)
        guard targetPage != currentPage else {
            return index
        }
        let targetStart = targetPage * normalizedPageSize
        let targetEnd = min(targetStart + normalizedPageSize, candidateCount)
        return min(targetStart + currentOffset, targetEnd - 1)
    }
}
