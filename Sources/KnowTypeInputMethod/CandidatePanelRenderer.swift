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
    private static let maxPrefixRows = 5
    private static let compactContinuationRows = 1
    private static let expandedContinuationRows = 3

    private let locale: KnowTypeLocale

    public init(locale: KnowTypeLocale = .mixed) {
        self.locale = locale
    }

    public func render(
        _ viewModel: CandidatePanelViewModel,
        selected selection: CandidatePanelSelection? = nil
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
            for (index, candidate) in viewModel.prefixCandidates.prefix(Self.maxPrefixRows).enumerated() {
                rows.append(
                    CandidatePanelRenderRow(
                        kind: .prefixCandidate,
                        shortcutLabel: "\(index + 1)",
                        text: candidate.text,
                        isSelected: selection == .prefixCandidate(index),
                        visualRole: .lockedPrefix
                    )
                )
            }
        }

        let visibleContinuationCount = continuationLimit(prefixCount: viewModel.prefixCandidates.count)
        if visibleContinuationCount > 0 {
            for (index, candidate) in viewModel.continuationCandidates.prefix(visibleContinuationCount).enumerated() {
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

        return CandidatePanelRenderModel(
            title: viewModel.title,
            previewText: nil,
            rows: rows
        )
    }

    private func continuationLimit(prefixCount: Int) -> Int {
        prefixCount < 2 ? Self.expandedContinuationRows : Self.compactContinuationRows
    }

    private func continuationShortcutLabel(at index: Int) -> String {
        guard index > 0 else {
            return "⇥"
        }
        return "⌥\(index + 1)"
    }
}
