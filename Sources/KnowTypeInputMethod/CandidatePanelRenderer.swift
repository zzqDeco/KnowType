import Foundation
import KnowTypeCore

public enum CandidatePanelRowKind: Sendable, Equatable {
    case sectionHeader
    case rawInput
    case prefixCandidate
    case continuationCandidate
}

public enum CandidatePanelVisualRole: Sendable, Equatable {
    case lockedPrefix
    case continuation
    case rawInput
    case sectionHeader
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
        selected selection: CandidatePanelSelection? = nil
    ) -> CandidatePanelRenderModel {
        var rows: [CandidatePanelRenderRow] = []

        if !viewModel.rawInput.isEmpty {
            appendSectionHeader(localizedRawInputLabel, to: &rows)
            rows.append(
                CandidatePanelRenderRow(
                    kind: .rawInput,
                    shortcutLabel: viewModel.prefixCandidates.isEmpty ? nil : "0",
                    text: viewModel.rawInput,
                    isSelected: selection == .rawInput,
                    visualRole: .rawInput
                )
            )
        }

        if !viewModel.prefixCandidates.isEmpty {
            appendSectionHeader(localizedPrefixLabel, to: &rows)
            for (index, candidate) in viewModel.prefixCandidates.enumerated() {
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

        if !viewModel.continuationCandidates.isEmpty {
            appendSectionHeader(localizedContinuationLabel, to: &rows)
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

        return CandidatePanelRenderModel(
            title: viewModel.title,
            previewText: viewModel.lockedPreview,
            rows: rows
        )
    }

    private var localizedPrefixLabel: String {
        switch locale {
        case .zhCN:
            return "锁定前缀"
        case .enUS, .mixed:
            return "Locked Prefix"
        }
    }

    private var localizedContinuationLabel: String {
        switch locale {
        case .zhCN:
            return "续写"
        case .enUS, .mixed:
            return "Continuation"
        }
    }

    private var localizedRawInputLabel: String {
        switch locale {
        case .zhCN:
            return "原始输入"
        case .enUS, .mixed:
            return "Raw Input"
        }
    }

    private func appendSectionHeader(_ text: String, to rows: inout [CandidatePanelRenderRow]) {
        rows.append(
            CandidatePanelRenderRow(
                kind: .sectionHeader,
                shortcutLabel: nil,
                text: text,
                isSelected: false,
                visualRole: .sectionHeader
            )
        )
    }

    private func continuationShortcutLabel(at index: Int) -> String {
        guard index > 0 else {
            return "Tab / Option+1"
        }
        return "Option+\(index + 1)"
    }
}
