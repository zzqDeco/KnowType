import Foundation
import KnowTypeAI
import KnowTypeCore

struct InputCommitDecisionContext: Sendable, Equatable {
    var action: InputAction
    var rawInput: String
    var compositionBuffer: CompositionBuffer
    var suggestionSnapshot: InputSuggestionStateSnapshot
    var commitSuggestionSnapshot: InputSuggestionCommitSnapshot
    var selectedCandidate: InputCandidateSelection?
    var panelSelection: CandidatePanelSelection?
    var panelIsVisible: Bool
    var aiRecommendationState: AIRecommendationState
    var hasActiveTextComposition: Bool
    var enablesAsyncSuggestionRefresh: Bool
    var isNativeActive: Bool
    var selectedCandidateShouldSelectBeforeSpace: Bool
    var selectedCandidateHasNativeIndex: Bool
    var appBundleID: String?
    var locale: KnowTypeLocale
    var runtimePreferences: InputMethodRuntimePreferences
}

enum InputCommitDecisionPlan: Sendable, Equatable {
    case directPassthroughSpace
    case finishEmptyRawCommit
    case selectNativeCandidateBeforeSpace(InputCandidateSelection)
    case processNativeSpace
    case resolve(InputCommitDecisionResultPlan)
}

enum InputCommitDecisionResultPlan: Sendable, Equatable {
    case result(InputCommitResult)
    case applySegmentCandidate(index: Int, commitIfFullyResolved: Bool)
    case selectNativeCandidateForCommit(InputCandidateSelection)
    case processNativeSpace
}

/// Pure value-in/value-out decision runtime for commit and candidate-selection planning.
///
/// Concurrency contract:
/// - Contains no mutable stored state.
/// - Invoked synchronously on the `InputControllerCoordinator` main-thread turn path.
/// - Marked `@unchecked Sendable` to align with the coordinator runtime boundary without
///   requiring `@MainActor` propagation into synchronous IMK entry points.
final class InputCommitDecisionRuntime: @unchecked Sendable {
    func commitPlan(context: InputCommitDecisionContext) -> InputCommitDecisionPlan {
        if context.action == .space,
           !context.hasActiveTextComposition {
            return .directPassthroughSpace
        }
        if context.action == .commitRaw,
           !context.hasActiveTextComposition {
            return .finishEmptyRawCommit
        }
        if context.action == .space,
           context.isNativeActive,
           !context.rawInput.isEmpty {
            if let selectedCandidate = context.selectedCandidate,
               shouldCommitSelectedNonNativeCandidateBeforeNativeSpace(selectedCandidate) {
                return .resolve(resultPlan(context: context))
            }
            if let selectedCandidate = context.selectedCandidate,
               context.selectedCandidateShouldSelectBeforeSpace {
                return .selectNativeCandidateBeforeSpace(selectedCandidate)
            }
            return .processNativeSpace
        }
        return .resolve(resultPlan(context: context))
    }

    func resultPlan(context: InputCommitDecisionContext) -> InputCommitDecisionResultPlan {
        switch context.action {
        case .commitRaw:
            return decideReturn(context: context)
        case .space:
            return decideSpace(context: context)
        case .tab:
            return decideTab(context: context)
        case .optionNumber:
            return decideOptionNumber(context: context)
        case .toggleSymbolMode, .toggleTextMode, .toggleSymbolWidth:
            return sessionCommitResultPlan(
                context: context,
                selectedCandidate: context.selectedCandidate
            )
        }
    }

    private func decideReturn(context: InputCommitDecisionContext) -> InputCommitDecisionResultPlan {
        if let legacyDecision = resolveLegacySegmentedReturnDecisionIfNeeded(context: context) {
            return legacyDecision
        }
        return .result(context.rawInput.isEmpty ? .noAction : .commit(context.rawInput))
    }

    private func decideSpace(context: InputCommitDecisionContext) -> InputCommitDecisionResultPlan {
        let selectedCandidate = context.selectedCandidate
        if let selectedCandidate,
           case .aiRecommendation = selectedCandidate.kind {
            return .result(aiRecommendationCommitResult(state: context.aiRecommendationState))
        }
        if let selectedCandidate,
           case .continuationCandidate = selectedCandidate.kind {
            return sessionCommitResultPlan(
                context: context,
                selectedCandidate: selectedCandidate,
                respectsPendingFallback: false
            )
        }
        if let legacyDecision = resolveLegacySegmentedSpaceDecisionIfNeeded(context: context) {
            return legacyDecision
        }
        if context.isNativeActive,
           let selectedCandidate,
           context.selectedCandidateShouldSelectBeforeSpace {
            return numberSelectionPlan(selection: selectedCandidate, context: context)
        }
        if context.isNativeActive,
           let selectedCandidate,
           InputNativeCandidateNavigationRuntime.isNativeSelectablePrefixOrFull(selectedCandidate),
           !context.selectedCandidateHasNativeIndex {
            return numberSelectionPlan(selection: selectedCandidate, context: context)
        }
        if context.isNativeActive {
            return .processNativeSpace
        }
        return .result(context.rawInput.isEmpty ? .noAction : .commit(context.rawInput))
    }

    private func decideTab(context: InputCommitDecisionContext) -> InputCommitDecisionResultPlan {
        if let aiShortcutResult = InputCommitResultPolicy.aiShortcutResult(
            for: .tab,
            aiRecommendationState: context.aiRecommendationState
        ) {
            return .result(aiShortcutResult)
        }
        if let legacyDecision = resolveLegacySegmentedTabDecisionIfNeeded(context: context) {
            return legacyDecision
        }
        if shouldSuppressTabCommitForPartialComposition(context: context) {
            return .result(.noAction)
        }
        if context.enablesAsyncSuggestionRefresh,
           !hasVisibleContinuationForCurrentSuggestion(context: context) {
            return .result(.noAction)
        }
        return sessionCommitResultPlan(
            context: context,
            selectedCandidate: context.selectedCandidate
        )
    }

    private func decideOptionNumber(context: InputCommitDecisionContext) -> InputCommitDecisionResultPlan {
        if let aiShortcutResult = InputCommitResultPolicy.aiShortcutResult(
            for: context.action,
            aiRecommendationState: context.aiRecommendationState
        ) {
            return .result(aiShortcutResult)
        }
        if !context.panelIsVisible {
            return .result(.noAction)
        }
        return sessionCommitResultPlan(
            context: context,
            selectedCandidate: context.selectedCandidate
        )
    }

    private func sessionCommitResultPlan(
        context: InputCommitDecisionContext,
        selectedCandidate: InputCandidateSelection?,
        respectsPendingFallback: Bool = true
    ) -> InputCommitDecisionResultPlan {
        let commitSuggestion = context.commitSuggestionSnapshot
        return .result(
            InputSessionCommitPolicy.result(
                for: context.action,
                rawInput: context.rawInput,
                suggestion: commitSuggestion.suggestion,
                suggestionRawInput: commitSuggestion.rawInput,
                selectedCandidate: (respectsPendingFallback && commitSuggestion.usesPendingFallback)
                    ? nil
                    : sessionSelection(from: selectedCandidate),
                appBundleID: context.appBundleID,
                locale: context.locale,
                runtimePreferences: context.runtimePreferences,
                allowsSynchronousFallback: false
            )
        )
    }

    // MARK: - Legacy CompositionBuffer Segmented Fallback Helpers

    private func resolveLegacySegmentedReturnDecisionIfNeeded(
        context: InputCommitDecisionContext
    ) -> InputCommitDecisionResultPlan? {
        guard context.compositionBuffer.hasResolvedSegments else {
            return nil
        }
        return .result(context.rawInput.isEmpty ? .noAction : .commit(context.rawInput))
    }

    private func resolveLegacySegmentedSpaceDecisionIfNeeded(
        context: InputCommitDecisionContext
    ) -> InputCommitDecisionResultPlan? {
        if let selectedCandidate = context.selectedCandidate,
           case .segmentCandidate(let index) = selectedCandidate.kind {
            return .applySegmentCandidate(index: index, commitIfFullyResolved: true)
        }
        guard context.compositionBuffer.hasResolvedSegments else {
            return nil
        }
        guard context.compositionBuffer.isFullyResolved else {
            return nil
        }
        if let selectedCandidate = context.selectedCandidate,
           case .continuationCandidate(let index) = selectedCandidate.kind,
           let suggestion = context.suggestionSnapshot.suggestion,
           suggestion.continuationCandidates.indices.contains(index) {
            return .result(
                InputCompositionController().handle(
                    action: .optionNumber(index + 1),
                    prefixCandidates: [resolvedCompositionCandidate(context: context)],
                    continuationCandidates: suggestion.continuationCandidates,
                    originalText: context.rawInput
                )
            )
        }
        return .result(.commit(context.compositionBuffer.commitText))
    }

    private func resolveLegacySegmentedTabDecisionIfNeeded(
        context: InputCommitDecisionContext
    ) -> InputCommitDecisionResultPlan? {
        if let selectedCandidate = context.selectedCandidate,
           case .segmentCandidate = selectedCandidate.kind {
            return .result(.noAction)
        }
        guard context.compositionBuffer.hasResolvedSegments else {
            return nil
        }
        guard context.compositionBuffer.isFullyResolved else {
            return .result(.noAction)
        }
        if context.enablesAsyncSuggestionRefresh,
           !hasVisibleContinuationForCurrentSuggestion(context: context) {
            return .result(.noAction)
        }
        let suggestion = context.suggestionSnapshot.suggestion
        guard suggestion?.continuationCandidates.isEmpty == false else {
            return .result(.noAction)
        }
        return .result(
            InputCompositionController().handle(
                action: .tab,
                prefixCandidates: [resolvedCompositionCandidate(context: context)],
                continuationCandidates: suggestion?.continuationCandidates ?? [],
                originalText: context.rawInput
            )
        )
    }

    func numberSelectionPlan(
        selection: InputCandidateSelection,
        context: InputCommitDecisionContext
    ) -> InputCommitDecisionResultPlan {
        switch selection.kind {
        case .segmentCandidate(let index):
            return .applySegmentCandidate(index: index, commitIfFullyResolved: false)
        case .aiRecommendation:
            return .result(aiRecommendationCommitResult(state: context.aiRecommendationState))
        case .rawInput:
            return .result(context.rawInput.isEmpty ? .noAction : .commit(context.rawInput))
        case .symbolCandidate:
            return .result(.noAction)
        case .prefixCandidate, .fullCandidate, .continuationCandidate:
            if context.isNativeActive,
               InputNativeCandidateNavigationRuntime.isNativeSelectablePrefixOrFull(selection) {
                return .selectNativeCandidateForCommit(selection)
            }
            guard let selectedCandidate = sessionSelection(from: selection) else {
                return .result(.noAction)
            }
            let suggestionSnapshot = context.suggestionSnapshot
            return .result(
                InputSessionCommitPolicy.result(
                    for: .space,
                    rawInput: context.rawInput,
                    suggestion: suggestionSnapshot.suggestion,
                    suggestionRawInput: suggestionSnapshot.rawInput,
                    selectedCandidate: selectedCandidate,
                    appBundleID: context.appBundleID,
                    locale: context.locale,
                    allowsSynchronousFallback: false
                )
            )
        }
    }

    func acceptedAIRecommendationCandidate(
        action: InputAction,
        result: InputCommitResult,
        selectedCandidate: InputCandidateSelection?,
        aiRecommendationState: AIRecommendationState
    ) -> AIRecommendationCandidate? {
        guard case .commit(let text) = result,
              case .ready(let candidate) = aiRecommendationState,
              candidate.displayText == text else {
            return nil
        }
        if action == .tab {
            return candidate
        }
        if case .optionNumber(1) = action {
            return candidate
        }
        if action == .space,
           let selectedCandidate,
           case .aiRecommendation = selectedCandidate.kind {
            return candidate
        }
        return nil
    }

    func selectedPrefixTextForLearning(
        selectedCandidate: InputCandidateSelection?,
        panelSelection: CandidatePanelSelection?,
        suggestion: SuggestionResponse?
    ) -> String? {
        if let selectedCandidate {
            switch selectedCandidate.kind {
            case .rawInput:
                return nil
            case .prefixCandidate(let index), .fullCandidate(let index):
                return suggestion?.prefixCandidates[inputCommitDecisionSafe: index]?.text
            case .segmentCandidate:
                return nil
            case .aiRecommendation:
                return nil
            case .continuationCandidate:
                return suggestion?.prefixCandidates.first?.text
            case .symbolCandidate:
                return nil
            }
        }

        switch panelSelection {
        case .prefixCandidate(let index), .fullCandidate(let index):
            return suggestion?.prefixCandidates[inputCommitDecisionSafe: index]?.text
        case .segmentCandidate:
            return nil
        case .aiRecommendation:
            return nil
        case .continuationCandidate:
            return suggestion?.prefixCandidates.first?.text
        case .symbolCandidate:
            return nil
        case .rawInput, .none:
            return suggestion?.prefixCandidates.first?.text
        }
    }

    func shouldSkipPrefixLearning(action: InputAction, aiRecommendationState: AIRecommendationState) -> Bool {
        if action == .tab,
           aiRecommendationState.isSelectableRecommendation {
            return true
        }
        if case .optionNumber(1) = action,
           aiRecommendationState.isSelectableRecommendation {
            return true
        }
        return false
    }

    private func shouldSuppressTabCommitForPartialComposition(context: InputCommitDecisionContext) -> Bool {
        if context.compositionBuffer.hasResolvedSegments && !context.compositionBuffer.isFullyResolved {
            return true
        }
        guard hasCurrentSuggestion(context: context) else {
            return false
        }
        return shouldSuppressContinuations(
            prefixCandidates: context.suggestionSnapshot.suggestion?.prefixCandidates ?? [],
            compositionBuffer: context.compositionBuffer
        )
    }

    private func hasVisibleContinuationForCurrentSuggestion(context: InputCommitDecisionContext) -> Bool {
        guard hasCurrentSuggestion(context: context) else {
            return false
        }
        return context.suggestionSnapshot.suggestion?.continuationCandidates.isEmpty == false
    }

    private func hasCurrentSuggestion(context: InputCommitDecisionContext) -> Bool {
        SuggestionPublicationGuard.hasCurrentSuggestion(
            suggestionRawInput: context.suggestionSnapshot.rawInput,
            currentRawInput: context.rawInput
        )
    }

    private func shouldCommitSelectedNonNativeCandidateBeforeNativeSpace(
        _ selection: InputCandidateSelection
    ) -> Bool {
        switch selection.kind {
        case .prefixCandidate, .fullCandidate:
            return false
        case .rawInput, .segmentCandidate, .aiRecommendation, .continuationCandidate, .symbolCandidate:
            return true
        }
    }

    private func aiRecommendationCommitResult(state: AIRecommendationState) -> InputCommitResult {
        guard case .ready(let candidate) = state else {
            return .noAction
        }
        return candidate.displayText.isEmpty ? .noAction : .commit(candidate.displayText)
    }

    private func sessionSelection(from selection: InputCandidateSelection?) -> InputSessionCandidateSelection? {
        guard let selection else {
            return nil
        }
        switch selection.kind {
        case .rawInput:
            return .rawInput
        case .prefixCandidate(let index), .fullCandidate(let index):
            return .prefixCandidate(index: index)
        case .segmentCandidate:
            return nil
        case .aiRecommendation:
            return nil
        case .continuationCandidate(let index):
            return .continuationCandidate(index: index)
        case .symbolCandidate:
            return nil
        }
    }

    private func resolvedCompositionCandidate(context: InputCommitDecisionContext) -> CorrectionCandidate {
        CorrectionCandidate(
            text: context.compositionBuffer.commitText,
            source: "composition-buffer",
            confidence: 1.0,
            correctionLevel: .contextual,
            rawRange: context.compositionBuffer.rawRange,
            segments: context.compositionBuffer.resolvedSegments
        )
    }

    private func shouldSuppressContinuations(
        prefixCandidates: [CorrectionCandidate],
        compositionBuffer: CompositionBuffer
    ) -> Bool {
        if compositionBuffer.hasResolvedSegments && !compositionBuffer.isFullyResolved {
            return true
        }
        guard !compositionBuffer.isFullyResolved,
              let firstPrefix = prefixCandidates.first else {
            return false
        }
        return isPartialSegmentCandidate(firstPrefix, compositionBuffer: compositionBuffer)
    }

    private func isPartialSegmentCandidate(
        _ candidate: CorrectionCandidate,
        compositionBuffer: CompositionBuffer
    ) -> Bool {
        guard let rawRange = candidate.rawRange else {
            return false
        }
        return rawRange != compositionBuffer.rawRange
    }
}

private extension Collection {
    subscript(inputCommitDecisionSafe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
