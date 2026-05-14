import Foundation
import CoreGraphics
import KnowTypeCore

public struct CandidatePanelWindowState: Sendable, Equatable {
    public var isVisible: Bool
    public var anchorRect: CGRect
    public var viewModel: CandidatePanelViewModel
    public var selection: CandidatePanelSelection?

    public init(
        isVisible: Bool = false,
        anchorRect: CGRect = .zero,
        viewModel: CandidatePanelViewModel = CandidatePanelViewModel(
            rawInput: "",
            prefixCandidates: [],
            continuationCandidates: []
        ),
        selection: CandidatePanelSelection? = nil
    ) {
        self.isVisible = isVisible
        self.anchorRect = anchorRect
        self.viewModel = viewModel
        self.selection = selection
    }
}

public struct CandidatePanelState: Sendable, Equatable {
    public private(set) var windowState: CandidatePanelWindowState

    public init(windowState: CandidatePanelWindowState = CandidatePanelWindowState()) {
        self.windowState = windowState
    }

    public mutating func update(
        rawInput: String,
        suggestion: SuggestionResponse?,
        anchorRect: CGRect = .zero,
        isDisplayable: Bool = true
    ) {
        let prefixCandidates = suggestion?.prefixCandidates ?? []
        let continuationCandidates = suggestion?.continuationCandidates ?? []
        let viewModel = CandidatePanelViewModel(
            rawInput: rawInput,
            prefixCandidates: prefixCandidates,
            continuationCandidates: continuationCandidates
        )
        let hasRows = !rawInput.isEmpty || !prefixCandidates.isEmpty || !continuationCandidates.isEmpty
        let isVisible = isDisplayable && hasRows
        windowState = CandidatePanelWindowState(
            isVisible: isVisible,
            anchorRect: anchorRect,
            viewModel: viewModel,
            selection: isVisible ? defaultSelection(
                rawInput: rawInput,
                prefixCandidates: prefixCandidates,
                continuationCandidates: continuationCandidates
            ) : nil
        )
    }

    public mutating func hide() {
        windowState = CandidatePanelWindowState()
    }

    @discardableResult
    public mutating func moveSelection(_ navigation: InputCandidateNavigation) -> Bool {
        guard windowState.isVisible else {
            return false
        }
        let rows = selectableRows()
        guard !rows.isEmpty else {
            return false
        }

        let currentIndex = windowState.selection.flatMap { rows.firstIndex(of: $0) } ?? 0
        let nextIndex = clampedIndex(
            currentIndex + offset(for: navigation),
            upperBound: rows.count - 1
        )
        windowState.selection = rows[nextIndex]
        return true
    }

    private func defaultSelection(
        rawInput: String,
        prefixCandidates: [CorrectionCandidate],
        continuationCandidates: [ContinuationCandidate]
    ) -> CandidatePanelSelection? {
        if !prefixCandidates.isEmpty {
            return .prefixCandidate(0)
        }
        if !rawInput.isEmpty {
            return .rawInput
        }
        if !continuationCandidates.isEmpty {
            return .continuationCandidate(0)
        }
        return nil
    }

    private func selectableRows() -> [CandidatePanelSelection] {
        let viewModel = windowState.viewModel
        let hasSuggestions = !viewModel.prefixCandidates.isEmpty || !viewModel.continuationCandidates.isEmpty
        var rows: [CandidatePanelSelection] = []

        if !viewModel.rawInput.isEmpty && !hasSuggestions {
            rows.append(.rawInput)
        }
        rows.append(
            contentsOf: viewModel.prefixCandidates.indices.map { .prefixCandidate($0) }
        )
        rows.append(
            contentsOf: viewModel.continuationCandidates.indices.map { .continuationCandidate($0) }
        )
        return rows
    }

    private func offset(for navigation: InputCandidateNavigation) -> Int {
        switch navigation {
        case .down, .right:
            return 1
        case .up, .left:
            return -1
        case .pageDown:
            return 5
        case .pageUp:
            return -5
        }
    }

    private func clampedIndex(_ index: Int, upperBound: Int) -> Int {
        min(max(index, 0), upperBound)
    }
}
