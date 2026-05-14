import Foundation
import CoreGraphics
import KnowTypeCore

public struct CandidatePanelWindowState: Sendable, Equatable {
    public var isVisible: Bool
    public var anchorRect: CGRect
    public var viewModel: CandidatePanelViewModel
    public var selection: CandidatePanelSelection?
    public var paging: CandidatePanelPagingState

    public init(
        isVisible: Bool = false,
        anchorRect: CGRect = .zero,
        viewModel: CandidatePanelViewModel = CandidatePanelViewModel(
            rawInput: "",
            prefixCandidates: [],
            continuationCandidates: []
        ),
        selection: CandidatePanelSelection? = nil,
        paging: CandidatePanelPagingState = CandidatePanelPagingState()
    ) {
        self.isVisible = isVisible
        self.anchorRect = anchorRect
        self.viewModel = viewModel
        self.selection = selection
        self.paging = paging
    }
}

public struct CandidatePanelPagingState: Sendable, Equatable {
    public static let defaultPageSize = 9

    public var currentPage: Int
    public var pageSize: Int

    public init(currentPage: Int = 0, pageSize: Int = Self.defaultPageSize) {
        self.currentPage = max(0, currentPage)
        self.pageSize = max(1, pageSize)
    }

    public func pageCount(totalRows: Int) -> Int {
        guard totalRows > 0 else {
            return 0
        }
        return (totalRows + pageSize - 1) / pageSize
    }

    public func visibleRange(totalRows: Int) -> Range<Int> {
        guard totalRows > 0 else {
            return 0..<0
        }
        let normalizedPage = min(currentPage, pageCount(totalRows: totalRows) - 1)
        let start = normalizedPage * pageSize
        let end = min(start + pageSize, totalRows)
        return start..<end
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
        let selection = isVisible ? selectionAfterUpdate(
            rawInput: rawInput,
            prefixCandidates: prefixCandidates,
            continuationCandidates: continuationCandidates,
            viewModel: viewModel
        ) : nil
        let paging = pagingState(for: selection, in: viewModel)
        windowState = CandidatePanelWindowState(
            isVisible: isVisible,
            anchorRect: anchorRect,
            viewModel: viewModel,
            selection: selection,
            paging: isVisible ? paging : CandidatePanelPagingState()
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

        let currentIndex = windowState.selection.flatMap { rows.firstIndex(of: $0) } ?? windowState.paging.visibleRange(totalRows: rows.count).lowerBound
        let nextIndex: Int
        switch navigation {
        case .pageDown:
            nextIndex = firstIndex(
                onPage: windowState.paging.currentPage + 1,
                currentIndex: currentIndex,
                totalRows: rows.count
            )
        case .pageUp:
            nextIndex = firstIndex(
                onPage: windowState.paging.currentPage - 1,
                currentIndex: currentIndex,
                totalRows: rows.count
            )
        case .down, .right:
            nextIndex = clampedIndex(currentIndex + 1, upperBound: rows.count - 1)
        case .up, .left:
            nextIndex = clampedIndex(currentIndex - 1, upperBound: rows.count - 1)
        }
        windowState.selection = rows[nextIndex]
        windowState.paging = pagingState(forRowIndex: nextIndex)
        return true
    }

    @discardableResult
    public mutating func selectVisiblePrefixCandidate(shortcutNumber number: Int) -> CandidatePanelSelection? {
        guard windowState.isVisible,
              number > 0 else {
            return nil
        }
        let visibleRows = visibleSelectableRows()
        let prefixRows = visibleRows.filter { selection in
            if case .prefixCandidate = selection {
                return true
            }
            return false
        }
        let shortcutIndex = number - 1
        guard prefixRows.indices.contains(shortcutIndex) else {
            return nil
        }
        let selection = prefixRows[shortcutIndex]
        windowState.selection = selection
        if let rowIndex = selectableRows().firstIndex(of: selection) {
            windowState.paging = pagingState(forRowIndex: rowIndex)
        }
        return selection
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

    private func selectionAfterUpdate(
        rawInput: String,
        prefixCandidates: [CorrectionCandidate],
        continuationCandidates: [ContinuationCandidate],
        viewModel: CandidatePanelViewModel
    ) -> CandidatePanelSelection? {
        if windowState.viewModel.rawInput == rawInput,
           let selection = windowState.selection,
           selectableRows(in: viewModel).contains(selection) {
            return selection
        }
        return defaultSelection(
            rawInput: rawInput,
            prefixCandidates: prefixCandidates,
            continuationCandidates: continuationCandidates
        )
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

    private func visibleSelectableRows() -> [CandidatePanelSelection] {
        let rows = selectableRows()
        let range = windowState.paging.visibleRange(totalRows: rows.count)
        return Array(rows[range])
    }

    private func clampedIndex(_ index: Int, upperBound: Int) -> Int {
        min(max(index, 0), upperBound)
    }

    private func firstIndex(onPage page: Int, currentIndex: Int, totalRows: Int) -> Int {
        let pageCount = windowState.paging.pageCount(totalRows: totalRows)
        let targetPage = min(max(page, 0), max(pageCount - 1, 0))
        guard targetPage != windowState.paging.currentPage else {
            return currentIndex
        }
        return min(targetPage * windowState.paging.pageSize, max(totalRows - 1, 0))
    }

    private func pagingState(
        for selection: CandidatePanelSelection?,
        in viewModel: CandidatePanelViewModel
    ) -> CandidatePanelPagingState {
        let rows = selectableRows(in: viewModel)
        guard let selection,
              let rowIndex = rows.firstIndex(of: selection) else {
            return CandidatePanelPagingState()
        }
        return pagingState(forRowIndex: rowIndex)
    }

    private func pagingState(forRowIndex rowIndex: Int) -> CandidatePanelPagingState {
        CandidatePanelPagingState(
            currentPage: rowIndex / CandidatePanelPagingState.defaultPageSize
        )
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
}
