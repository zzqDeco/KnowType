import Foundation

#if canImport(AppKit)
import AppKit
import KnowTypeCore

struct CandidatePanelAppearance {
    var panelCornerRadius: CGFloat = 7
    var rowCornerRadius: CGFloat = 5
    var borderWidth: CGFloat = 0.5
    var borderAlpha: CGFloat = 0.22
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var contentInsets = CandidatePanelLayoutInsets(top: 5, left: 6, bottom: 5, right: 6)
    var itemInsets = CandidatePanelLayoutInsets(top: 2, left: 7, bottom: 2, right: 9)
    var horizontalRowHeight: CGFloat = 32
    var verticalRowHeight: CGFloat = 30
    var minimumVerticalRowHeight: CGFloat = 20
    var horizontalItemSpacing: CGFloat = 3
    var verticalItemSpacing: CGFloat = 3
    var shortcutReservedWidth: CGFloat = 22
    var shortcutTextSpacing: CGFloat = 5
    var textFontSize: CGFloat = 16
    var shortcutFontSize: CGFloat = 11
    var rawFontSize: CGFloat = 14
    var usesSnapshotColors = false
    var usesSnapshotDarkColors = false

    static let native = CandidatePanelAppearance()

    static let snapshotLight = CandidatePanelAppearance(usesSnapshotColors: true)
    static let snapshotDark = CandidatePanelAppearance(usesSnapshotColors: true, usesSnapshotDarkColors: true)

    func layoutConfiguration(layoutMode: CandidatePanelLayoutMode) -> CandidatePanelLayoutConfiguration {
        var configuration = CandidatePanelLayoutConfiguration(layoutMode: layoutMode)
        configuration.horizontalRowHeight = horizontalRowHeight
        configuration.verticalRowHeight = verticalRowHeight
        configuration.minimumVerticalRowHeight = minimumVerticalRowHeight
        configuration.contentInsets = contentInsets
        configuration.itemInsets = itemInsets
        configuration.horizontalItemSpacing = horizontalItemSpacing
        configuration.verticalItemSpacing = verticalItemSpacing
        configuration.shortcutReservedWidth = shortcutReservedWidth
        configuration.shortcutTextSpacing = shortcutTextSpacing
        return configuration
    }

    func shortcutFont() -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: shortcutFontSize, weight: .medium)
    }

    func font(for role: CandidatePanelVisualRole) -> NSFont {
        switch role {
        case .lockedPrefix, .aiRecommendation, .continuation:
            return .systemFont(ofSize: textFontSize, weight: .regular)
        case .rawInput:
            return .monospacedSystemFont(ofSize: rawFontSize, weight: .regular)
        }
    }

    func panelBorderColor() -> NSColor {
        color(
            .separatorColor,
            snapshot: NSColor(calibratedWhite: 0.72, alpha: 1),
            darkSnapshot: NSColor(calibratedWhite: 0.36, alpha: 1)
        ).withAlphaComponent(borderAlpha)
    }

    func panelBackgroundColor() -> NSColor? {
        guard usesSnapshotColors else {
            return nil
        }
        return usesSnapshotDarkColors
            ? NSColor(calibratedWhite: 0.14, alpha: 0.98)
            : NSColor(calibratedWhite: 0.97, alpha: 0.98)
    }

    func rowBackgroundColor(isSelected: Bool) -> NSColor {
        guard isSelected else {
            return .clear
        }
        return color(
            .selectedContentBackgroundColor,
            snapshot: NSColor(calibratedRed: 0.08, green: 0.36, blue: 0.84, alpha: 1)
        )
    }

    func textColor(for role: CandidatePanelVisualRole, isSelected: Bool, isEnabled: Bool) -> NSColor {
        if isSelected {
            return color(.alternateSelectedControlTextColor, snapshot: .white)
        }
        guard isEnabled else {
            return color(
                .tertiaryLabelColor,
                snapshot: NSColor(calibratedWhite: 0.45, alpha: 1),
                darkSnapshot: NSColor(calibratedWhite: 0.50, alpha: 1)
            )
        }
        switch role {
        case .lockedPrefix:
            return color(
                .labelColor,
                snapshot: NSColor(calibratedWhite: 0.08, alpha: 1),
                darkSnapshot: NSColor(calibratedWhite: 0.92, alpha: 1)
            )
        case .aiRecommendation, .continuation:
            return color(
                .secondaryLabelColor,
                snapshot: NSColor(calibratedWhite: 0.32, alpha: 1),
                darkSnapshot: NSColor(calibratedWhite: 0.74, alpha: 1)
            )
        case .rawInput:
            return color(
                .tertiaryLabelColor,
                snapshot: NSColor(calibratedWhite: 0.45, alpha: 1),
                darkSnapshot: NSColor(calibratedWhite: 0.56, alpha: 1)
            )
        }
    }

    func shortcutColor(for role: CandidatePanelVisualRole, isSelected: Bool, isEnabled: Bool) -> NSColor {
        if isSelected {
            return color(.alternateSelectedControlTextColor, snapshot: .white)
        }
        guard isEnabled else {
            return color(
                .quaternaryLabelColor,
                snapshot: NSColor(calibratedWhite: 0.60, alpha: 1),
                darkSnapshot: NSColor(calibratedWhite: 0.42, alpha: 1)
            )
        }
        switch role {
        case .lockedPrefix:
            return color(
                .secondaryLabelColor,
                snapshot: NSColor(calibratedWhite: 0.32, alpha: 1),
                darkSnapshot: NSColor(calibratedWhite: 0.74, alpha: 1)
            )
        case .aiRecommendation, .continuation, .rawInput:
            return color(
                .tertiaryLabelColor,
                snapshot: NSColor(calibratedWhite: 0.45, alpha: 1),
                darkSnapshot: NSColor(calibratedWhite: 0.56, alpha: 1)
            )
        }
    }

    private func color(_ dynamic: NSColor, snapshot: NSColor, darkSnapshot: NSColor? = nil) -> NSColor {
        guard usesSnapshotColors else {
            return dynamic
        }
        return usesSnapshotDarkColors ? (darkSnapshot ?? snapshot) : snapshot
    }
}
#endif
