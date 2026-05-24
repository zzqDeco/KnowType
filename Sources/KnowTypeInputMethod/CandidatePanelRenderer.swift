import Foundation
import KnowTypeAI
import KnowTypeCore

public enum CandidatePanelRowKind: Sendable, Equatable {
    case rawInput
    case prefixCandidate
    case aiRecommendation
    case continuationCandidate
}

public enum CandidatePanelVisualRole: Sendable, Equatable, Hashable {
    case lockedPrefix
    case aiRecommendation
    case continuation
    case rawInput
}

public enum CandidatePanelSelection: Sendable, Equatable {
    case rawInput
    case prefixCandidate(Int)
    case fullCandidate(Int)
    case segmentCandidate(Int)
    case aiRecommendation
    case continuationCandidate(Int)
}

public struct CandidatePanelRenderRow: Sendable, Equatable {
    public var kind: CandidatePanelRowKind
    public var selection: CandidatePanelSelection?
    public var shortcutLabel: String?
    public var text: String
    public var isSelected: Bool
    public var isEnabled: Bool
    public var visualRole: CandidatePanelVisualRole
    public var accessibilityLabel: String

    public init(
        kind: CandidatePanelRowKind,
        selection: CandidatePanelSelection? = nil,
        shortcutLabel: String?,
        text: String,
        isSelected: Bool,
        isEnabled: Bool = true,
        visualRole: CandidatePanelVisualRole,
        accessibilityLabel: String? = nil
    ) {
        self.kind = kind
        self.selection = selection
        self.shortcutLabel = shortcutLabel
        self.text = text
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.visualRole = visualRole
        self.accessibilityLabel = accessibilityLabel ?? Self.defaultAccessibilityLabel(
            shortcutLabel: shortcutLabel,
            text: text,
            visualRole: visualRole,
            isEnabled: isEnabled
        )
    }

    private static func defaultAccessibilityLabel(
        shortcutLabel: String?,
        text: String,
        visualRole: CandidatePanelVisualRole,
        isEnabled: Bool
    ) -> String {
        let rolePrefix: String?
        switch visualRole {
        case .aiRecommendation:
            rolePrefix = isEnabled ? "AI 推荐" : "AI 状态"
        case .continuation:
            rolePrefix = "续写"
        case .rawInput:
            rolePrefix = "原文"
        case .lockedPrefix:
            rolePrefix = nil
        }
        return [rolePrefix, shortcutLabel, text]
            .compactMap { $0 }
            .joined(separator: "，")
    }
}

public struct CandidatePanelRenderModel: Sendable, Equatable {
    public var title: String
    public var previewText: String?
    public var rows: [CandidatePanelRenderRow]

    public init(title: String, previewText: String?, rows: [CandidatePanelRenderRow]) {
        self.title = title
        self.previewText = previewText
        self.rows = rows
    }
}

public struct CandidatePanelRenderer: Sendable {
    private let locale: KnowTypeLocale

    public init(locale: KnowTypeLocale = .mixed) {
        self.locale = locale
    }

    public func render(
        _ viewModel: CandidatePanelViewModel,
        selected selection: CandidatePanelSelection? = nil,
        paging explicitPaging: CandidatePanelPagingState? = nil
    ) -> CandidatePanelRenderModel {
        let allRows = selectableRows(in: viewModel)
        let paging = explicitPaging ?? pagingState(containing: selection, in: allRows)
        let visibleRange = paging.visibleRange(totalRows: allRows.count)
        var nextNumberShortcut = 1
        let rows = allRows[visibleRange].map { item in
            let shortcutLabel: String?
            switch item.selection {
            case nil:
                shortcutLabel = nil
            case .some(.rawInput):
                shortcutLabel = nil
            case .some(.prefixCandidate), .some(.fullCandidate), .some(.segmentCandidate):
                shortcutLabel = "\(nextNumberShortcut)"
                nextNumberShortcut += 1
            case .some(.aiRecommendation):
                if viewModel.aiRecommendation.isSelectableRecommendation {
                    shortcutLabel = "⇥"
                } else {
                    shortcutLabel = nil
                }
            case .some(.continuationCandidate(let index)):
                shortcutLabel = continuationShortcutLabel(atGlobalIndex: index)
            }
            return CandidatePanelRenderRow(
                kind: item.kind,
                selection: item.selection,
                shortcutLabel: shortcutLabel,
                text: item.text,
                isSelected: item.isEnabled && selection == item.selection,
                isEnabled: item.isEnabled,
                visualRole: item.visualRole
            )
        }

        return CandidatePanelRenderModel(
            title: viewModel.title,
            previewText: nil,
            rows: rows
        )
    }

    private func selectableRows(in viewModel: CandidatePanelViewModel) -> [CandidatePanelRenderableRow] {
        var rows: [CandidatePanelRenderableRow] = []
        let hasSuggestions = !viewModel.prefixCandidates.isEmpty
            || !viewModel.continuationCandidates.isEmpty
            || viewModel.aiRecommendation.displayText != nil

        if !viewModel.rawInput.isEmpty && !hasSuggestions {
            rows.append(
                CandidatePanelRenderableRow(
                    selection: .rawInput,
                    kind: .rawInput,
                    text: viewModel.rawInput,
                    visualRole: .rawInput
                )
            )
        }

        for (index, candidate) in viewModel.prefixCandidates.enumerated() {
            rows.append(
                CandidatePanelRenderableRow(
                    selection: prefixSelection(for: candidate, rawInput: viewModel.rawInput, index: index),
                    kind: .prefixCandidate,
                    text: candidate.text,
                    visualRole: .lockedPrefix
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
                CandidatePanelRenderableRow(
                    selection: .continuationCandidate(index),
                    kind: .continuationCandidate,
                    text: candidate.text,
                    visualRole: .continuation
                )
            )
        }

        return rows
    }

    private func aiRecommendationRow(_ state: AIRecommendationState) -> CandidatePanelRenderableRow? {
        guard let text = state.displayText else {
            return nil
        }
        return CandidatePanelRenderableRow(
            selection: state.isSelectableRecommendation ? .aiRecommendation : nil,
            kind: .aiRecommendation,
            text: text,
            visualRole: .aiRecommendation,
            isEnabled: state.isSelectableRecommendation
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

    private func pagingState(
        containing selection: CandidatePanelSelection?,
        in rows: [CandidatePanelRenderableRow]
    ) -> CandidatePanelPagingState {
        guard let selection,
              let index = rows.firstIndex(where: { $0.selection == selection }) else {
            return CandidatePanelPagingState()
        }
        return CandidatePanelPagingState(
            currentPage: index / CandidatePanelPagingState.defaultPageSize
        )
    }

    private func continuationShortcutLabel(atGlobalIndex index: Int) -> String? {
        guard index > 0 else {
            return "⇥"
        }
        guard index < 9 else {
            return nil
        }
        return "⌥\(index + 1)"
    }
}

private struct CandidatePanelRenderableRow: Sendable, Equatable {
    var selection: CandidatePanelSelection?
    var kind: CandidatePanelRowKind
    var text: String
    var visualRole: CandidatePanelVisualRole
    var isEnabled: Bool = true
}
