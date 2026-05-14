import Foundation
import CoreGraphics
import KnowTypeCore

public struct CandidatePanelWindowState: Sendable, Equatable {
    public static let defaultPageSize = 9

    public var isVisible: Bool
    public var anchorRect: CGRect
    public var viewModel: CandidatePanelViewModel
    public var selection: CandidatePanelSelection?
    public var pageStart: Int
    public var pageSize: Int

    public init(
        isVisible: Bool = false,
        anchorRect: CGRect = .zero,
        viewModel: CandidatePanelViewModel = CandidatePanelViewModel(
            rawInput: "",
            prefixCandidates: [],
            continuationCandidates: []
        ),
        selection: CandidatePanelSelection? = nil,
        pageStart: Int = 0,
        pageSize: Int = CandidatePanelWindowState.defaultPageSize
    ) {
        self.isVisible = isVisible
        self.anchorRect = anchorRect
        self.viewModel = viewModel
        self.selection = selection
        self.pageStart = pageStart
        self.pageSize = pageSize
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
        anchorRect: CGRect = .zero
    ) {
        let prefixCandidates = suggestion?.prefixCandidates ?? []
        let continuationCandidates = suggestion?.continuationCandidates ?? []
        let viewModel = CandidatePanelViewModel(
            rawInput: rawInput,
            prefixCandidates: prefixCandidates,
            continuationCandidates: continuationCandidates
        )
        let isVisible = !rawInput.isEmpty || !prefixCandidates.isEmpty || !continuationCandidates.isEmpty
        let rows = selectableRows(in: viewModel)
        let selection = nextSelection(
            rawInput: rawInput,
            rows: rows,
            prefixCandidates: prefixCandidates,
            continuationCandidates: continuationCandidates
        )
        let nextPageStart = nextPageStart(rawInput: rawInput, selection: selection, rows: rows)
        windowState = CandidatePanelWindowState(
            isVisible: isVisible,
            anchorRect: anchorRect,
            viewModel: viewModel,
            selection: selection,
            pageStart: nextPageStart
        )
    }

    public mutating func hide() {
        windowState = CandidatePanelWindowState()
    }

    @discardableResult
    public mutating func moveSelection(_ navigation: InputCandidateNavigation) -> Bool {
        let rows = selectableRows()
        guard !rows.isEmpty else {
            return false
        }

        let currentIndex = windowState.selection.flatMap { rows.firstIndex(of: $0) } ?? 0
        let nextIndex: Int
        switch navigation {
        case .pageDown:
            nextIndex = clampedIndex(windowState.pageStart + windowState.pageSize, upperBound: rows.count - 1)
        case .pageUp:
            nextIndex = clampedIndex(windowState.pageStart - windowState.pageSize, upperBound: rows.count - 1)
        case .down, .right, .up, .left:
            nextIndex = clampedIndex(
                currentIndex + offset(for: navigation),
                upperBound: rows.count - 1
            )
        }
        windowState.selection = rows[nextIndex]
        windowState.pageStart = pageStart(containingIndex: nextIndex, rowCount: rows.count)
        return true
    }

    public func selectionForShortcutNumber(_ number: Int) -> CandidatePanelSelection? {
        guard number > 0,
              number <= windowState.pageSize else {
            return nil
        }

        let visiblePrefixRows = visibleRows().filter { selection in
            if case .prefixCandidate = selection {
                return true
            }
            return false
        }
        let shortcutIndex = number - 1
        guard visiblePrefixRows.indices.contains(shortcutIndex) else {
            return nil
        }
        return visiblePrefixRows[shortcutIndex]
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

    private func nextSelection(
        rawInput: String,
        rows: [CandidatePanelSelection],
        prefixCandidates: [CorrectionCandidate],
        continuationCandidates: [ContinuationCandidate]
    ) -> CandidatePanelSelection? {
        let rawInputDidNotChange = rawInput == windowState.viewModel.rawInput
        if rawInputDidNotChange {
            if let selection = windowState.selection,
               rows.contains(selection) {
                return selection
            }
            if !rows.isEmpty {
                let preservedPageStart = min(windowState.pageStart, rows.count - 1)
                return rows[preservedPageStart]
            }
        }

        return defaultSelection(
            rawInput: rawInput,
            prefixCandidates: prefixCandidates,
            continuationCandidates: continuationCandidates
        )
    }

    private func nextPageStart(
        rawInput: String,
        selection: CandidatePanelSelection?,
        rows: [CandidatePanelSelection]
    ) -> Int {
        guard !rows.isEmpty else {
            return 0
        }
        let rawInputDidNotChange = rawInput == windowState.viewModel.rawInput
        if rawInputDidNotChange {
            let preservedPageStart = min(windowState.pageStart, rows.count - 1)
            if let selection,
               let selectedIndex = rows.firstIndex(of: selection),
               selectedIndex >= preservedPageStart,
               selectedIndex < preservedPageStart + windowState.pageSize {
                return preservedPageStart
            }
        }
        return pageStart(containing: selection, rows: rows)
    }

    private func selectableRows() -> [CandidatePanelSelection] {
        selectableRows(in: windowState.viewModel)
    }

    private func selectableRows(in viewModel: CandidatePanelViewModel) -> [CandidatePanelSelection] {
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

    private func visibleRows() -> [CandidatePanelSelection] {
        let rows = selectableRows()
        guard !rows.isEmpty else {
            return []
        }
        let start = min(windowState.pageStart, rows.count - 1)
        let end = min(start + windowState.pageSize, rows.count)
        return Array(rows[start..<end])
    }

    private func offset(for navigation: InputCandidateNavigation) -> Int {
        switch navigation {
        case .down, .right:
            return 1
        case .up, .left:
            return -1
        case .pageDown:
            return windowState.pageSize
        case .pageUp:
            return -windowState.pageSize
        }
    }

    private func clampedIndex(_ index: Int, upperBound: Int) -> Int {
        min(max(index, 0), upperBound)
    }

    private func pageStart(containing selection: CandidatePanelSelection?, rows: [CandidatePanelSelection]) -> Int {
        guard let selection,
              let index = rows.firstIndex(of: selection) else {
            return 0
        }
        return pageStart(containingIndex: index, rowCount: rows.count)
    }

    private func pageStart(containingIndex index: Int, rowCount: Int) -> Int {
        guard rowCount > 0 else {
            return 0
        }
        let pageSize = max(1, windowState.pageSize)
        let start = (index / pageSize) * pageSize
        return min(start, max(0, rowCount - 1))
    }
}
