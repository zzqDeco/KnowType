import Foundation
import CoreGraphics
import KnowTypeAI
import KnowTypeCore

public struct CandidatePanelWindowState: Sendable, Equatable {
    public var isVisible: Bool
    public var anchorRect: CGRect
    public var anchorSource: CandidateAnchorSource
    public var viewModel: CandidatePanelViewModel
    public var selection: CandidatePanelSelection?
    public var paging: CandidatePanelPagingState
    public var layoutMode: CandidatePanelLayoutMode

    public init(
        isVisible: Bool = false,
        anchorRect: CGRect = .zero,
        anchorSource: CandidateAnchorSource = .none,
        viewModel: CandidatePanelViewModel = CandidatePanelViewModel(
            rawInput: "",
            prefixCandidates: [],
            continuationCandidates: []
        ),
        selection: CandidatePanelSelection? = nil,
        paging: CandidatePanelPagingState = CandidatePanelPagingState(),
        layoutMode: CandidatePanelLayoutMode = .adaptive
    ) {
        self.isVisible = isVisible
        self.anchorRect = anchorRect
        self.anchorSource = anchorSource
        self.viewModel = viewModel
        self.selection = selection
        self.paging = paging
        self.layoutMode = layoutMode
    }
}

public struct CandidatePanelPagingState: Sendable, Equatable {
    public static let defaultPageSize = InputMethodRuntimePreferences.adaptiveCandidatePageSize

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
        anchorSource: CandidateAnchorSource = .none,
        isDisplayable: Bool = true,
        pageSize: Int = CandidatePanelPagingState.defaultPageSize,
        layoutMode: CandidatePanelLayoutMode = .adaptive,
        aiRecommendation: AIRecommendationState = .idle
    ) {
        let prefixCandidates = suggestion?.prefixCandidates ?? []
        let continuationCandidates = suggestion?.continuationCandidates ?? []
        let viewModel = CandidatePanelViewModel(
            rawInput: rawInput,
            prefixCandidates: prefixCandidates,
            continuationCandidates: continuationCandidates,
            aiRecommendation: aiRecommendation
        )
        let hasAIRow = aiRecommendation.displayText != nil
        let hasRows = !rawInput.isEmpty || !prefixCandidates.isEmpty || !continuationCandidates.isEmpty || hasAIRow
        let isVisible = isDisplayable && hasRows
        let selection = isVisible ? selectionAfterUpdate(
            rawInput: rawInput,
            prefixCandidates: prefixCandidates,
            continuationCandidates: continuationCandidates,
            viewModel: viewModel
        ) : nil
        let paging = pagingState(for: selection, in: viewModel, pageSize: pageSize)
        windowState = CandidatePanelWindowState(
            isVisible: isVisible,
            anchorRect: anchorRect,
            anchorSource: anchorSource,
            viewModel: viewModel,
            selection: selection,
            paging: isVisible ? paging : CandidatePanelPagingState(pageSize: pageSize),
            layoutMode: layoutMode
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
        let renderedRows = renderRows()
        let selectableRows = selectableRows(in: renderedRows)
        guard !selectableRows.isEmpty else {
            return false
        }

        let currentRenderedIndex = windowState.selection
            .flatMap { renderedRows.firstIndex(of: .some($0)) }
            ?? windowState.paging.visibleRange(totalRows: renderedRows.count).lowerBound
        let nextRenderedIndex: Int
        switch navigation {
        case .pageDown:
            nextRenderedIndex = firstSelectableRenderedIndex(
                onPage: windowState.paging.currentPage + 1,
                currentRenderedIndex: currentRenderedIndex,
                renderedRows: renderedRows
            )
        case .pageUp:
            nextRenderedIndex = firstSelectableRenderedIndex(
                onPage: windowState.paging.currentPage - 1,
                currentRenderedIndex: currentRenderedIndex,
                renderedRows: renderedRows
            )
        case .down, .right:
            nextRenderedIndex = adjacentSelectableRenderedIndex(
                from: currentRenderedIndex,
                step: 1,
                renderedRows: renderedRows
            )
        case .up, .left:
            nextRenderedIndex = adjacentSelectableRenderedIndex(
                from: currentRenderedIndex,
                step: -1,
                renderedRows: renderedRows
            )
        }
        guard renderedRows.indices.contains(nextRenderedIndex),
              let selection = renderedRows[nextRenderedIndex] else {
            return false
        }
        windowState.selection = selection
        windowState.paging = pagingState(forRowIndex: nextRenderedIndex, pageSize: windowState.paging.pageSize)
        return true
    }

    @discardableResult
    public mutating func selectVisibleRow(_ selection: CandidatePanelSelection) -> Bool {
        guard windowState.isVisible else {
            return false
        }
        let renderedRows = renderRows()
        let visibleRange = windowState.paging.visibleRange(totalRows: renderedRows.count)
        guard let rowIndex = renderedRows[visibleRange].firstIndex(of: .some(selection)) else {
            return false
        }
        windowState.selection = selection
        windowState.paging = pagingState(forRowIndex: rowIndex, pageSize: windowState.paging.pageSize)
        return true
    }

    @discardableResult
    public mutating func selectVisiblePrefixCandidate(shortcutNumber number: Int) -> CandidatePanelSelection? {
        guard windowState.isVisible,
              number > 0 else {
            return nil
        }
        let visibleRows = visibleSelectableRows()
            .filter { hasVisibleNumberShortcut($0, in: windowState.viewModel) }
        let shortcutIndex = number - 1
        guard visibleRows.indices.contains(shortcutIndex) else {
            return nil
        }
        let selection = visibleRows[shortcutIndex]
        windowState.selection = selection
        if let rowIndex = renderRows().firstIndex(of: .some(selection)) {
            windowState.paging = pagingState(forRowIndex: rowIndex, pageSize: windowState.paging.pageSize)
        }
        return selection
    }

    private func defaultSelection(
        rawInput: String,
        prefixCandidates: [CorrectionCandidate],
        continuationCandidates: [ContinuationCandidate],
        aiRecommendation: AIRecommendationState
    ) -> CandidatePanelSelection? {
        if let firstPrefix = prefixCandidates.first {
            return prefixSelection(for: firstPrefix, rawInput: rawInput, index: 0)
        }
        if !rawInput.isEmpty {
            return .rawInput
        }
        if aiRecommendation.isSelectableRecommendation {
            return .aiRecommendation
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
           canPreserveSelection(selection, in: viewModel) {
            return selection
        }
        return defaultSelection(
            rawInput: rawInput,
            prefixCandidates: prefixCandidates,
            continuationCandidates: continuationCandidates,
            aiRecommendation: viewModel.aiRecommendation
        )
    }

    private func canPreserveSelection(
        _ selection: CandidatePanelSelection,
        in viewModel: CandidatePanelViewModel
    ) -> Bool {
        guard renderRows(in: viewModel).contains(.some(selection)) else {
            return false
        }

        switch selection {
        case .rawInput:
            return windowState.viewModel.rawInput == viewModel.rawInput
        case .prefixCandidate(let index), .fullCandidate(let index), .segmentCandidate(let index):
            guard windowState.viewModel.prefixCandidates.indices.contains(index),
                  viewModel.prefixCandidates.indices.contains(index) else {
                return false
            }
            return windowState.viewModel.prefixCandidates[index].text == viewModel.prefixCandidates[index].text
                && prefixSelection(
                    for: viewModel.prefixCandidates[index],
                    rawInput: viewModel.rawInput,
                    index: index
                ) == selection
        case .continuationCandidate(let index):
            guard windowState.viewModel.continuationCandidates.indices.contains(index),
                  viewModel.continuationCandidates.indices.contains(index) else {
                return false
            }
            return windowState.viewModel.continuationCandidates[index].text == viewModel.continuationCandidates[index].text
        case .aiRecommendation:
            return windowState.viewModel.aiRecommendation == viewModel.aiRecommendation
                && viewModel.aiRecommendation.isSelectableRecommendation
        }
    }

    private func renderRows() -> [CandidatePanelSelection?] {
        renderRows(in: windowState.viewModel)
    }

    private func selectableRows(in renderedRows: [CandidatePanelSelection?]) -> [CandidatePanelSelection] {
        renderedRows.compactMap { $0 }
    }

    private func visibleSelectableRows() -> [CandidatePanelSelection] {
        let rows = renderRows()
        let range = windowState.paging.visibleRange(totalRows: rows.count)
        return rows[range].compactMap { $0 }
    }

    private func renderRows(in viewModel: CandidatePanelViewModel) -> [CandidatePanelSelection?] {
        let hasSuggestions = !viewModel.prefixCandidates.isEmpty
            || !viewModel.continuationCandidates.isEmpty
            || viewModel.aiRecommendation.displayText != nil
        var rows: [CandidatePanelSelection?] = []

        if !viewModel.rawInput.isEmpty && !hasSuggestions {
            rows.append(.rawInput)
        }
        let prefixRows = prefixRows(in: viewModel)
        if let first = prefixRows.first {
            rows.append(first)
            if viewModel.aiRecommendation.displayText != nil {
                rows.append(viewModel.aiRecommendation.isSelectableRecommendation ? .aiRecommendation : nil)
            }
            rows.append(contentsOf: prefixRows.dropFirst().map { Optional.some($0) })
        } else if viewModel.aiRecommendation.displayText != nil {
            rows.append(viewModel.aiRecommendation.isSelectableRecommendation ? .aiRecommendation : nil)
        }
        rows.append(
            contentsOf: viewModel.continuationCandidates.indices.map { .continuationCandidate($0) }
        )
        return rows
    }

    private func firstSelectableRenderedIndex(
        onPage page: Int,
        currentRenderedIndex: Int,
        renderedRows: [CandidatePanelSelection?]
    ) -> Int {
        let pageCount = windowState.paging.pageCount(totalRows: renderedRows.count)
        let targetPage = min(max(page, 0), max(pageCount - 1, 0))
        guard targetPage != windowState.paging.currentPage else {
            return currentRenderedIndex
        }
        let currentPageStart = windowState.paging.currentPage * windowState.paging.pageSize
        let currentOffset = max(0, currentRenderedIndex - currentPageStart)
        let targetPageStart = targetPage * windowState.paging.pageSize
        let targetPageEnd = min(targetPageStart + windowState.paging.pageSize, renderedRows.count)
        let preferredIndex = min(targetPageStart + currentOffset, max(targetPageEnd - 1, targetPageStart))
        if let forward = firstSelectableIndex(
            in: renderedRows,
            range: preferredIndex..<targetPageEnd,
            direction: 1
        ) {
            return forward
        }
        if let backward = firstSelectableIndex(
            in: renderedRows,
            range: targetPageStart...preferredIndex,
            direction: -1
        ) {
            return backward
        }
        return currentRenderedIndex
    }

    private func adjacentSelectableRenderedIndex(
        from currentRenderedIndex: Int,
        step: Int,
        renderedRows: [CandidatePanelSelection?]
    ) -> Int {
        guard step != 0 else {
            return currentRenderedIndex
        }
        var index = currentRenderedIndex + step
        while renderedRows.indices.contains(index) {
            if renderedRows[index] != nil {
                return index
            }
            index += step
        }
        return currentRenderedIndex
    }

    private func firstSelectableIndex<R: Sequence>(
        in renderedRows: [CandidatePanelSelection?],
        range: R,
        direction: Int
    ) -> Int? where R.Element == Int {
        var indexes = Array(range)
        if direction < 0 {
            indexes.reverse()
        }
        return indexes.first { renderedRows.indices.contains($0) && renderedRows[$0] != nil }
    }

    private func pagingState(
        for selection: CandidatePanelSelection?,
        in viewModel: CandidatePanelViewModel,
        pageSize: Int
    ) -> CandidatePanelPagingState {
        let rows = renderRows(in: viewModel)
        guard let selection,
              let rowIndex = rows.firstIndex(of: .some(selection)) else {
            return CandidatePanelPagingState(pageSize: pageSize)
        }
        return pagingState(forRowIndex: rowIndex, pageSize: pageSize)
    }

    private func pagingState(forRowIndex rowIndex: Int, pageSize: Int) -> CandidatePanelPagingState {
        CandidatePanelPagingState(
            currentPage: rowIndex / max(1, pageSize),
            pageSize: pageSize
        )
    }

    private func prefixRows(in viewModel: CandidatePanelViewModel) -> [CandidatePanelSelection] {
        viewModel.prefixCandidates.enumerated().map { index, candidate in
            prefixSelection(for: candidate, rawInput: viewModel.rawInput, index: index)
        }
    }

    private func prefixSelection(
        for candidate: CorrectionCandidate,
        rawInput: String,
        index: Int
    ) -> CandidatePanelSelection {
        guard let range = candidate.rawRange else {
            return .prefixCandidate(index)
        }
        return range == KnowTypeCore.TextRange(start: 0, length: rawInput.count)
            ? .fullCandidate(index)
            : .segmentCandidate(index)
    }

    private func hasVisibleNumberShortcut(
        _ selection: CandidatePanelSelection,
        in viewModel: CandidatePanelViewModel
    ) -> Bool {
        switch selection {
        case .prefixCandidate, .fullCandidate, .segmentCandidate:
            return true
        case .aiRecommendation:
            return viewModel.aiRecommendation.isSelectableRecommendation
        case .rawInput, .continuationCandidate:
            return false
        }
    }
}
