import Foundation
import KnowTypeCore

public enum CandidatePanelRowKind: Sendable, Equatable {
    case rawInput
    case prefixCandidate
    case continuationCandidate
}

public enum CandidatePanelVisualRole: Sendable, Equatable {
    case lockedPrefix
    case continuation
    case rawInput
}

public enum CandidatePanelSelection: Sendable, Equatable {
    case rawInput
    case prefixCandidate(Int)
    case continuationCandidate(Int)
}

public struct CandidatePanelRenderRow: Sendable, Equatable {
    public var kind: CandidatePanelRowKind
    public var shortcutLabel: String?
    public var text: String
    public var isSelected: Bool
    public var visualRole: CandidatePanelVisualRole

    public init(
        kind: CandidatePanelRowKind,
        shortcutLabel: String?,
        text: String,
        isSelected: Bool,
        visualRole: CandidatePanelVisualRole
    ) {
        self.kind = kind
        self.shortcutLabel = shortcutLabel
        self.text = text
        self.isSelected = isSelected
        self.visualRole = visualRole
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
        let rows = allRows[visibleRange].enumerated().map { offset, item in
            let shortcutLabel: String?
            switch item.selection {
            case .rawInput:
                shortcutLabel = nil
            case .prefixCandidate:
                shortcutLabel = "\(offset + 1)"
            case .continuationCandidate(let index):
                shortcutLabel = continuationShortcutLabel(atGlobalIndex: index)
            }
            return CandidatePanelRenderRow(
                kind: item.kind,
                shortcutLabel: shortcutLabel,
                text: item.text,
                isSelected: selection == item.selection,
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
        let hasSuggestions = !viewModel.prefixCandidates.isEmpty || !viewModel.continuationCandidates.isEmpty

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

        if !viewModel.prefixCandidates.isEmpty {
            for (index, candidate) in viewModel.prefixCandidates.enumerated() {
                rows.append(
                    CandidatePanelRenderableRow(
                        selection: .prefixCandidate(index),
                        kind: .prefixCandidate,
                        text: candidate.text,
                        visualRole: .lockedPrefix
                    )
                )
            }
        }

        if !viewModel.continuationCandidates.isEmpty {
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
        }

        return rows
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
    var selection: CandidatePanelSelection
    var kind: CandidatePanelRowKind
    var text: String
    var visualRole: CandidatePanelVisualRole
}
