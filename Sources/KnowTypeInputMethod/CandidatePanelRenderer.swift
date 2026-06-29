import Foundation
import KnowTypeAI
import KnowTypeCore

public enum CandidatePanelRowKind: Sendable, Equatable {
    case preedit
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
    private let rowBuilder = CandidatePanelRowBuilder()

    public init(locale: KnowTypeLocale = .mixed) {
        self.locale = locale
    }

    public func render(
        _ viewModel: CandidatePanelViewModel,
        selected selection: CandidatePanelSelection? = nil,
        paging explicitPaging: CandidatePanelPagingState? = nil
    ) -> CandidatePanelRenderModel {
        let rowList = rowBuilder.buildRows(in: viewModel)
        let allRows = rowList.pageableRows
        let paging = explicitPaging ?? pagingState(containing: selection, in: allRows)
        let visibleRange = paging.visibleRange(totalRows: allRows.count)
        var nextNumberShortcut = 1
        let rows = rowList.fixedRows.map { renderRow(from: $0, selected: selection, shortcutLabel: nil) }
            + allRows[visibleRange].map { item in
            let shortcutLabel: String?
            switch item.selection {
            case nil:
                shortcutLabel = nil
            case .some(.rawInput):
                shortcutLabel = nil
            case .some(.prefixCandidate), .some(.fullCandidate), .some(.segmentCandidate):
                if item.isNumberShortcutEligible {
                    shortcutLabel = "\(nextNumberShortcut)"
                    nextNumberShortcut += 1
                } else {
                    shortcutLabel = nil
                }
            case .some(.aiRecommendation):
                if viewModel.aiRecommendation.isSelectableRecommendation {
                    shortcutLabel = "⇥"
                } else {
                    shortcutLabel = nil
                }
            case .some(.continuationCandidate(let index)):
                shortcutLabel = continuationShortcutLabel(atGlobalIndex: index)
            }
            return renderRow(from: item, selected: selection, shortcutLabel: shortcutLabel)
        }

        return CandidatePanelRenderModel(
            title: viewModel.title,
            previewText: nil,
            rows: rows
        )
    }

    private func renderRow(
        from item: CandidatePanelRowItem,
        selected selection: CandidatePanelSelection?,
        shortcutLabel: String?
    ) -> CandidatePanelRenderRow {
        CandidatePanelRenderRow(
            kind: item.kind,
            selection: item.selection,
            shortcutLabel: shortcutLabel,
            text: item.text,
            isSelected: item.isEnabled && item.selection != nil && selection == item.selection,
            isEnabled: item.isEnabled,
            visualRole: item.visualRole,
            accessibilityLabel: item.accessibilityLabel
        )
    }

    private func pagingState(
        containing selection: CandidatePanelSelection?,
        in rows: [CandidatePanelRowItem]
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
