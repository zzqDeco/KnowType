import Foundation
import KnowTypeAI
import KnowTypeCore

enum InputNativeCandidateNavigationEffect: Sendable, Equatable {
    case publishLocalSuggestion
    case refreshNativeHighlightPresentation
}

struct InputNativeCandidateNavigationResult: Sendable, Equatable {
    var handled: Bool
    var conversionResult: ConversionEngineResult?
    var consumesUnhandledConversionResult: Bool
    var effects: [InputNativeCandidateNavigationEffect]

    static func ignored() -> InputNativeCandidateNavigationResult {
        InputNativeCandidateNavigationResult(handled: false)
    }

    init(
        handled: Bool,
        conversionResult: ConversionEngineResult? = nil,
        consumesUnhandledConversionResult: Bool = false,
        effects: [InputNativeCandidateNavigationEffect] = []
    ) {
        self.handled = handled
        self.conversionResult = conversionResult
        self.consumesUnhandledConversionResult = consumesUnhandledConversionResult
        self.effects = effects
    }
}

final class InputNativeCandidateNavigationRuntime: @unchecked Sendable {
    private(set) var displayedCandidates: [InputCandidateSelection] = []
    private(set) var selectedCandidate: InputCandidateSelection?

    @discardableResult
    func cacheDisplayedCandidates(_ candidates: [InputCandidateSelection]) -> [InputCandidateSelection] {
        displayedCandidates = candidates
        return candidates
    }

    @discardableResult
    func selectDisplayedCandidate(matching text: String?) -> InputCandidateSelection? {
        guard let text,
              let selection = displayedCandidates.first(where: { $0.text == text }) else {
            selectedCandidate = nil
            return nil
        }
        selectedCandidate = selection
        return selection
    }

    @discardableResult
    func setSelectedCandidate(_ selection: InputCandidateSelection?) -> InputCandidateSelection? {
        selectedCandidate = selection
        return selection
    }

    func clearSelectedCandidate() {
        selectedCandidate = nil
    }

    @discardableResult
    func updateSelectedCandidate(
        for selection: CandidatePanelSelection?,
        in viewModel: CandidatePanelViewModel
    ) -> InputCandidateSelection? {
        setSelectedCandidate(inputCandidateSelection(for: selection, in: viewModel))
    }

    func inputCandidateSelection(
        for selection: CandidatePanelSelection?,
        in viewModel: CandidatePanelViewModel
    ) -> InputCandidateSelection? {
        guard let selection else {
            return nil
        }

        switch selection {
        case .rawInput:
            guard !viewModel.rawInput.isEmpty else {
                return nil
            }
            return InputCandidateSelection(text: viewModel.rawInput, kind: .rawInput)
        case .prefixCandidate(let index):
            guard viewModel.prefixCandidates.indices.contains(index) else {
                return nil
            }
            let candidate = viewModel.prefixCandidates[index]
            return InputCandidateSelection(
                text: candidate.text,
                kind: .prefixCandidate(index: index),
                nativeCandidateIndex: ConversionCandidateSource.nativeIndex(from: candidate.source)
            )
        case .fullCandidate(let index):
            guard viewModel.prefixCandidates.indices.contains(index) else {
                return nil
            }
            let candidate = viewModel.prefixCandidates[index]
            return InputCandidateSelection(
                text: candidate.text,
                kind: .fullCandidate(index: index),
                nativeCandidateIndex: ConversionCandidateSource.nativeIndex(from: candidate.source)
            )
        case .segmentCandidate(let index):
            guard viewModel.prefixCandidates.indices.contains(index) else {
                return nil
            }
            let candidate = viewModel.prefixCandidates[index]
            return InputCandidateSelection(
                text: candidate.text,
                kind: .segmentCandidate(index: index),
                nativeCandidateIndex: ConversionCandidateSource.nativeIndex(from: candidate.source)
            )
        case .continuationCandidate(let index):
            guard viewModel.continuationCandidates.indices.contains(index) else {
                return nil
            }
            return InputCandidateSelection(
                text: viewModel.continuationCandidates[index].text,
                kind: .continuationCandidate(index: index)
            )
        case .aiRecommendation:
            guard let text = viewModel.aiRecommendation.displayText,
                  !text.isEmpty else {
                return nil
            }
            return InputCandidateSelection(text: text, kind: .aiRecommendation)
        }
    }

    func nativeHighlightedSelection(
        suggestion: SuggestionResponse?,
        rawInput: String,
        engine: any KnowTypeConversionEngine
    ) -> CandidatePanelSelection? {
        guard engine.isNativeActive,
              let suggestion,
              !suggestion.prefixCandidates.isEmpty else {
            return nil
        }
        let highlightedIndex = engine.snapshot.highlightedIndex
        guard suggestion.prefixCandidates.indices.contains(highlightedIndex) else {
            return nil
        }
        let candidate = suggestion.prefixCandidates[highlightedIndex]
        guard let range = candidate.rawRange else {
            return .prefixCandidate(highlightedIndex)
        }
        return range == TextRange(start: 0, length: rawInput.count)
            ? .fullCandidate(highlightedIndex)
            : .segmentCandidate(highlightedIndex)
    }

    func selectCandidateOnCurrentPage(
        _ index: Int,
        engine: inout any KnowTypeConversionEngine
    ) -> InputNativeCandidateNavigationResult {
        let snapshot = engine.snapshot
        guard snapshot.candidates.indices.contains(index) else {
            return InputNativeCandidateNavigationResult(handled: true)
        }
        return InputNativeCandidateNavigationResult(
            handled: true,
            conversionResult: engine.process(.selectCandidateOnCurrentPage(index)),
            consumesUnhandledConversionResult: true
        )
    }

    func selectNativeCandidateIfNeeded(
        _ selection: InputCandidateSelection,
        engine: inout any KnowTypeConversionEngine
    ) -> InputNativeCandidateNavigationResult {
        guard engine.isNativeActive,
              Self.isNativeSelectablePrefixOrFull(selection),
              let nativeIndex = nativeCandidateIndex(for: selection, engine: engine) else {
            return .ignored()
        }
        return InputNativeCandidateNavigationResult(
            handled: true,
            conversionResult: engine.process(.selectCandidateOnCurrentPage(nativeIndex))
        )
    }

    func selectNativeCandidateForCommit(
        _ selection: InputCandidateSelection,
        engine: inout any KnowTypeConversionEngine
    ) -> ConversionEngineResult? {
        guard engine.isNativeActive,
              Self.isNativeSelectablePrefixOrFull(selection),
              let nativeIndex = nativeCandidateIndex(for: selection, engine: engine) else {
            return nil
        }
        return engine.process(.selectCandidateOnCurrentPage(nativeIndex))
    }

    func highlightSelectionIfNeeded(
        _ selection: InputCandidateSelection,
        engine: inout any KnowTypeConversionEngine
    ) -> InputNativeCandidateNavigationResult {
        guard engine.isNativeActive,
              Self.isNativeSelectablePrefixOrFull(selection),
              let nativeIndex = nativeCandidateIndex(for: selection, engine: engine),
              nativeIndex != engine.snapshot.highlightedIndex else {
            return .ignored()
        }
        let result = engine.process(.highlightCandidateOnCurrentPage(nativeIndex))
        guard result.handled else {
            return .ignored()
        }
        return InputNativeCandidateNavigationResult(
            handled: true,
            effects: [.refreshNativeHighlightPresentation]
        )
    }

    func shouldSelectBeforeSpace(
        _ selection: InputCandidateSelection,
        engine: any KnowTypeConversionEngine
    ) -> Bool {
        guard Self.isNativeSelectablePrefixOrFull(selection),
              let nativeIndex = nativeCandidateIndex(for: selection, engine: engine) else {
            return false
        }
        return nativeIndex != engine.snapshot.highlightedIndex
    }

    func moveNativeCandidatePage(
        _ navigation: InputCandidateNavigation,
        rawInput: String,
        engine: inout any KnowTypeConversionEngine,
        consumeOnlyWhenSnapshotChanges: Bool = false
    ) -> InputNativeCandidateNavigationResult {
        pageNavigationResult(
            navigation,
            rawInput: rawInput,
            engine: &engine,
            consumeOnlyWhenSnapshotChanges: consumeOnlyWhenSnapshotChanges
        )
    }

    func moveNativeCandidatePage(
        forPagingSymbol text: String,
        rawInput: String,
        engine: inout any KnowTypeConversionEngine
    ) -> InputNativeCandidateNavigationResult {
        guard let navigation = Self.pagingSymbolNavigation(for: text) else {
            return .ignored()
        }
        return moveNativeCandidatePage(
            navigation,
            rawInput: rawInput,
            engine: &engine,
            consumeOnlyWhenSnapshotChanges: true
        )
    }

    func moveNativeCandidateSelection(
        _ navigation: InputCandidateNavigation,
        rawInput: String,
        engine: inout any KnowTypeConversionEngine
    ) -> InputNativeCandidateNavigationResult {
        switch navigation {
        case .pageDown, .pageUp:
            return moveNativeCandidatePage(navigation, rawInput: rawInput, engine: &engine)
        case .right, .down:
            return moveNativeCandidateHighlight(delta: 1, rawInput: rawInput, engine: &engine)
        case .left, .up:
            return moveNativeCandidateHighlight(delta: -1, rawInput: rawInput, engine: &engine)
        }
    }

    func boundaryPageNavigation(for navigation: InputCandidateNavigation) -> InputCandidateNavigation? {
        switch navigation {
        case .right, .down:
            return .pageDown
        case .left, .up:
            return .pageUp
        case .pageDown, .pageUp:
            return nil
        }
    }

    func nativeCandidateIndex(
        for selection: InputCandidateSelection,
        engine: any KnowTypeConversionEngine
    ) -> Int? {
        let snapshot = engine.snapshot
        guard !selection.text.isEmpty else {
            return nil
        }
        if let nativeCandidateIndex = selection.nativeCandidateIndex,
           snapshot.candidates.contains(where: { candidate in
               candidate.index == nativeCandidateIndex && candidate.text == selection.text
           }) {
            return nativeCandidateIndex
        }
        let textMatches = snapshot.candidates.filter { candidate in
            candidate.text == selection.text
        }
        guard textMatches.count == 1 else {
            return nil
        }
        return textMatches[0].index
    }

    static func isNativeSelectablePrefixOrFull(_ selection: InputCandidateSelection) -> Bool {
        switch selection.kind {
        case .prefixCandidate, .fullCandidate:
            return true
        case .rawInput, .segmentCandidate, .continuationCandidate, .aiRecommendation:
            return false
        }
    }

    private func moveNativeCandidateHighlight(
        delta: Int,
        rawInput: String,
        engine: inout any KnowTypeConversionEngine
    ) -> InputNativeCandidateNavigationResult {
        let snapshot = engine.snapshot
        guard !snapshot.candidates.isEmpty else {
            return .ignored()
        }
        let currentIndex = min(max(snapshot.highlightedIndex, 0), snapshot.candidates.count - 1)
        let targetIndex = currentIndex + delta
        if snapshot.candidates.indices.contains(targetIndex) {
            let result = engine.process(.highlightCandidateOnCurrentPage(targetIndex))
            guard result.handled else {
                return .ignored()
            }
            return InputNativeCandidateNavigationResult(
                handled: true,
                effects: [.refreshNativeHighlightPresentation]
            )
        }

        if targetIndex >= snapshot.candidates.count {
            let pageResult = pageNavigationResult(.pageDown, rawInput: rawInput, engine: &engine)
            guard pageResult.handled else {
                return InputNativeCandidateNavigationResult(handled: true)
            }
            let highlightResult = engine.process(.highlightCandidateOnCurrentPage(0))
            var effects = pageResult.effects
            if highlightResult.handled {
                effects.append(.refreshNativeHighlightPresentation)
            }
            return InputNativeCandidateNavigationResult(handled: true, effects: effects)
        }

        let pageResult = pageNavigationResult(.pageUp, rawInput: rawInput, engine: &engine)
        guard pageResult.handled else {
            return InputNativeCandidateNavigationResult(handled: true)
        }
        let previousPageSnapshot = engine.snapshot
        guard let lastIndex = previousPageSnapshot.candidates.indices.last else {
            return InputNativeCandidateNavigationResult(handled: true, effects: pageResult.effects)
        }
        let highlightResult = engine.process(.highlightCandidateOnCurrentPage(lastIndex))
        var effects = pageResult.effects
        if highlightResult.handled {
            effects.append(.refreshNativeHighlightPresentation)
        }
        return InputNativeCandidateNavigationResult(handled: true, effects: effects)
    }

    private func pageNavigationResult(
        _ navigation: InputCandidateNavigation,
        rawInput: String,
        engine: inout any KnowTypeConversionEngine,
        consumeOnlyWhenSnapshotChanges: Bool = false
    ) -> InputNativeCandidateNavigationResult {
        guard engine.isNativeActive,
              !rawInput.isEmpty else {
            return .ignored()
        }
        let snapshotBeforePage = engine.snapshot
        let key: ConversionEngineKey
        switch navigation {
        case .pageUp:
            key = .pageUp
        case .pageDown:
            key = .pageDown
        case .up, .down, .left, .right:
            return .ignored()
        }
        let result = engine.process(key)
        guard result.handled else {
            return .ignored()
        }
        if consumeOnlyWhenSnapshotChanges,
           result.snapshot == snapshotBeforePage,
           result.commitText == nil {
            return .ignored()
        }
        return InputNativeCandidateNavigationResult(
            handled: true,
            effects: [.publishLocalSuggestion]
        )
    }

    private static func pagingSymbolNavigation(for text: String) -> InputCandidateNavigation? {
        switch text {
        case "-", ",":
            return .pageUp
        case "=", ".":
            return .pageDown
        default:
            return nil
        }
    }
}
