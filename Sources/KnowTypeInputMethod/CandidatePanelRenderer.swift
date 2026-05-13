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
        pageStart: Int = 0,
        pageSize: Int = CandidatePanelWindowState.defaultPageSize
    ) -> CandidatePanelRenderModel {
        var rows: [CandidatePanelRenderRow] = []
        let hasSuggestions = !viewModel.prefixCandidates.isEmpty || !viewModel.continuationCandidates.isEmpty

        if !viewModel.rawInput.isEmpty && !hasSuggestions {
            rows.append(
                CandidatePanelRenderRow(
                    kind: .rawInput,
                    shortcutLabel: nil,
                    text: viewModel.rawInput,
                    isSelected: selection == .rawInput,
                    visualRole: .rawInput
                )
            )
        }

        if !viewModel.prefixCandidates.isEmpty {
            for (index, candidate) in viewModel.prefixCandidates.enumerated() {
                rows.append(
                    CandidatePanelRenderRow(
                        kind: .prefixCandidate,
                        shortcutLabel: nil,
                        text: candidate.text,
                        isSelected: selection == .prefixCandidate(index),
                        visualRole: .lockedPrefix
                    )
                )
            }
        }

        if !viewModel.continuationCandidates.isEmpty {
            for (index, candidate) in viewModel.continuationCandidates.enumerated() {
                rows.append(
                    CandidatePanelRenderRow(
                        kind: .continuationCandidate,
                        shortcutLabel: continuationShortcutLabel(at: index),
                        text: candidate.text,
                        isSelected: selection == .continuationCandidate(index),
                        visualRole: .continuation
                    )
                )
            }
        }

        let visibleRows = visibleRows(from: rows, pageStart: pageStart, pageSize: pageSize)

        return CandidatePanelRenderModel(
            title: viewModel.title,
            previewText: nil,
            rows: relabelPrefixShortcuts(in: visibleRows)
        )
    }

    private func continuationShortcutLabel(at index: Int) -> String {
        guard index > 0 else {
            return "⇥"
        }
        return "⌥\(index + 1)"
    }

    private func visibleRows(
        from rows: [CandidatePanelRenderRow],
        pageStart: Int,
        pageSize: Int
    ) -> [CandidatePanelRenderRow] {
        guard !rows.isEmpty else {
            return []
        }
        let start = min(max(0, pageStart), rows.count - 1)
        let end = min(start + max(1, pageSize), rows.count)
        return Array(rows[start..<end])
    }

    private func relabelPrefixShortcuts(in rows: [CandidatePanelRenderRow]) -> [CandidatePanelRenderRow] {
        var prefixShortcut = 1
        return rows.map { row in
            guard row.kind == .prefixCandidate else {
                return row
            }
            var updated = row
            updated.shortcutLabel = "\(prefixShortcut)"
            prefixShortcut += 1
            return updated
        }
    }
}
