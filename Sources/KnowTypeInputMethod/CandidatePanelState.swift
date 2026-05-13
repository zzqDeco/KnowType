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
        windowState = CandidatePanelWindowState(
            isVisible: isVisible,
            anchorRect: anchorRect,
            viewModel: viewModel,
            selection: defaultSelection(
                rawInput: rawInput,
                prefixCandidates: prefixCandidates,
                continuationCandidates: continuationCandidates
            )
        )
    }

    public mutating func hide() {
        windowState = CandidatePanelWindowState()
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
}
