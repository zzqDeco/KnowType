import Foundation
import KnowTypeAI
import KnowTypeCore

public struct CandidatePanelRowItem: Sendable, Equatable {
    public var selection: CandidatePanelSelection?
    public var kind: CandidatePanelRowKind
    public var text: String
    public var visualRole: CandidatePanelVisualRole
    public var accessibilityLabel: String?
    public var isEnabled: Bool
    public var isNumberShortcutEligible: Bool
    public var accessory: CandidatePanelRowAccessory?

    public init(
        selection: CandidatePanelSelection?,
        kind: CandidatePanelRowKind,
        text: String,
        visualRole: CandidatePanelVisualRole,
        accessibilityLabel: String? = nil,
        isEnabled: Bool = true,
        isNumberShortcutEligible: Bool = false,
        accessory: CandidatePanelRowAccessory? = nil
    ) {
        self.selection = selection
        self.kind = kind
        self.text = text
        self.visualRole = visualRole
        self.accessibilityLabel = accessibilityLabel
        self.isEnabled = isEnabled
        self.isNumberShortcutEligible = isNumberShortcutEligible
        self.accessory = accessory
    }
}

public struct CandidatePanelRowList: Sendable, Equatable {
    public var fixedRows: [CandidatePanelRowItem]
    public var pageableRows: [CandidatePanelRowItem]

    public init(
        fixedRows: [CandidatePanelRowItem],
        pageableRows: [CandidatePanelRowItem]
    ) {
        self.fixedRows = fixedRows
        self.pageableRows = pageableRows
    }

    public var isEmpty: Bool {
        fixedRows.isEmpty && pageableRows.isEmpty
    }
}

public struct CandidatePanelRowBuilder: Sendable {
    public init() {}

    public func buildRows(in viewModel: CandidatePanelViewModel) -> CandidatePanelRowList {
        CandidatePanelRowList(
            fixedRows: fixedRows(in: viewModel),
            pageableRows: pageableRows(in: viewModel)
        )
    }

    public func defaultSelection(in viewModel: CandidatePanelViewModel) -> CandidatePanelSelection? {
        buildRows(in: viewModel)
            .pageableRows
            .first { row in
                guard row.isEnabled,
                      let selection = row.selection else {
                    return false
                }
                return selection != .aiRecommendation
            }?
            .selection
    }

    public func pageableSelections(in viewModel: CandidatePanelViewModel) -> [CandidatePanelSelection?] {
        buildRows(in: viewModel).pageableRows.map(\.selection)
    }

    public func hasVisibleNumberShortcut(_ selection: CandidatePanelSelection, in viewModel: CandidatePanelViewModel) -> Bool {
        buildRows(in: viewModel)
            .pageableRows
            .contains { $0.selection == selection && $0.isNumberShortcutEligible }
    }

    private func fixedRows(in viewModel: CandidatePanelViewModel) -> [CandidatePanelRowItem] {
        var rows: [CandidatePanelRowItem] = []
        if let modeStatusText = viewModel.modeStatusText,
           !modeStatusText.isEmpty {
            rows.append(
                CandidatePanelRowItem(
                    selection: nil,
                    kind: .modeStatus,
                    text: modeStatusText,
                    visualRole: .status,
                    accessibilityLabel: "输入模式，\(modeStatusText)",
                    isEnabled: false
                )
            )
        }
        guard let preeditDisplayText = viewModel.preeditDisplayText,
              !preeditDisplayText.isEmpty else {
            return rows
        }
        rows.append(
            CandidatePanelRowItem(
                selection: nil,
                kind: .preedit,
                text: preeditDisplayText,
                visualRole: .rawInput,
                accessibilityLabel: "预编辑，\(preeditDisplayText)"
            )
        )
        return rows
    }

    private func pageableRows(in viewModel: CandidatePanelViewModel) -> [CandidatePanelRowItem] {
        var rows: [CandidatePanelRowItem] = []
        let hasSuggestions = !viewModel.prefixCandidates.isEmpty
            || !viewModel.continuationCandidates.isEmpty
            || viewModel.aiRecommendation.displayText != nil
            || !viewModel.symbolCandidates.isEmpty
        let hasPreeditDisplayText = viewModel.preeditDisplayText?.isEmpty == false

        if !viewModel.symbolCandidates.isEmpty {
            return viewModel.symbolCandidates.enumerated().map { index, candidate in
                CandidatePanelRowItem(
                    selection: .symbolCandidate(index),
                    kind: .symbolCandidate,
                    text: candidate.label,
                    visualRole: .symbolCandidate,
                    accessibilityLabel: "符号，\(index + 1)，\(candidate.label)",
                    isNumberShortcutEligible: true
                )
            }
        }

        if !viewModel.rawInput.isEmpty && !hasSuggestions && !hasPreeditDisplayText {
            rows.append(
                CandidatePanelRowItem(
                    selection: .rawInput,
                    kind: .rawInput,
                    text: viewModel.rawInput,
                    visualRole: .rawInput
                )
            )
        }

        for (index, candidate) in viewModel.prefixCandidates.enumerated() {
            rows.append(
                CandidatePanelRowItem(
                    selection: prefixSelection(for: candidate, rawInput: viewModel.rawInput, index: index),
                    kind: .prefixCandidate,
                    text: candidate.text,
                    visualRole: .lockedPrefix,
                    isNumberShortcutEligible: true
                )
            )
            if index == 0, let aiRow = aiRecommendationRow(viewModel.aiRecommendation) {
                rows.append(aiRow)
            }
        }

        if viewModel.prefixCandidates.isEmpty,
           let aiRow = aiRecommendationRow(viewModel.aiRecommendation) {
            rows.append(aiRow)
        }

        for (index, candidate) in viewModel.continuationCandidates.enumerated() {
            rows.append(
                CandidatePanelRowItem(
                    selection: .continuationCandidate(index),
                    kind: .continuationCandidate,
                    text: candidate.text,
                    visualRole: .continuation
                )
            )
        }

        return rows
    }

    private func aiRecommendationRow(_ state: AIRecommendationState) -> CandidatePanelRowItem? {
        guard let text = state.displayText else {
            return nil
        }
        let isPending = state.isPendingRecommendation
        return CandidatePanelRowItem(
            selection: state.isSelectableRecommendation ? .aiRecommendation : nil,
            kind: .aiRecommendation,
            text: isPending ? "" : text,
            visualRole: .aiRecommendation,
            accessibilityLabel: isPending ? "AI 状态，AI 推荐中" : nil,
            isEnabled: state.isSelectableRecommendation,
            accessory: isPending ? .spinner : nil
        )
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
}
