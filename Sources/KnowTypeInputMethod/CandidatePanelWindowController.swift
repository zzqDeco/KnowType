import Foundation

#if canImport(AppKit)
import AppKit
import KnowTypeCore

@MainActor
protocol CandidatePanelWindowOperating: AnyObject {
    func setContentSize(_ size: NSSize)
    func setFrameOrigin(_ point: NSPoint)
    func orderFrontRegardless()
    func orderOut(_ sender: Any?)
}

extension NSPanel: CandidatePanelWindowOperating {}

@MainActor
protocol CandidatePanelContentRendering: AnyObject {
    var appKitView: NSView { get }

    func update(model: CandidatePanelRenderModel, layoutPlan: CandidatePanelLayoutPlan)
}

@MainActor
final class CandidatePanelWindowController {
    private var panel: CandidatePanelWindowOperating?
    private let contentView: CandidatePanelContentRendering
    private let screenProvider: ScreenGeometryProviding
    private let layoutEngine: CandidatePanelLayoutEngine
    private let makePanel: @MainActor (NSView) -> CandidatePanelWindowOperating

    convenience init() {
        self.init(
            screenProvider: AppKitScreenGeometryProvider(),
            contentView: CandidatePanelContentView(),
            layoutEngine: CandidatePanelLayoutEngine(textMeasurer: AppKitCandidatePanelTextMeasurer()),
            makePanel: Self.makeAppKitPanel
        )
    }

    init(
        screenProvider: ScreenGeometryProviding,
        contentView: CandidatePanelContentRendering,
        layoutEngine: CandidatePanelLayoutEngine,
        makePanel: @escaping @MainActor (NSView) -> CandidatePanelWindowOperating
    ) {
        self.screenProvider = screenProvider
        self.contentView = contentView
        self.layoutEngine = layoutEngine
        self.makePanel = makePanel
    }

    func update(state: CandidatePanelState, locale: KnowTypeLocale) {
        let windowState = state.windowState
        guard windowState.isVisible else {
            hide()
            return
        }

        let renderModel = CandidatePanelRenderer(locale: locale).render(
            windowState.viewModel,
            selected: windowState.selection,
            paging: windowState.paging
        )

        let panel = candidatePanel()
        guard let layoutPlan = layoutEngine.layout(
            model: renderModel,
            anchorRect: windowState.anchorRect,
            screenProvider: screenProvider
        ) else {
            panel.orderOut(nil)
            return
        }
        contentView.update(model: renderModel, layoutPlan: layoutPlan)
        panel.setContentSize(layoutPlan.panelSize)
        panel.setFrameOrigin(layoutPlan.panelOrigin)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func candidatePanel() -> CandidatePanelWindowOperating {
        if let panel {
            return panel
        }

        let panel = makePanel(contentView.appKitView)
        self.panel = panel
        return panel
    }

    private static func makeAppKitPanel(contentView: NSView) -> CandidatePanelWindowOperating {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = contentView
        return panel
    }

}

private struct AppKitCandidatePanelTextMeasurer: CandidatePanelTextMeasuring {
    func textWidth(for row: CandidatePanelRenderRow) -> CGFloat {
        ceil(
            (row.text as NSString).size(
                withAttributes: [
                    .font: CandidatePanelTypography.font(for: row.visualRole)
                ]
            ).width
        )
    }

    func shortcutWidth(for label: String) -> CGFloat {
        ceil(
            (label as NSString).size(
                withAttributes: [
                    .font: CandidatePanelTypography.shortcutFont()
                ]
            ).width
        )
    }
}

private enum CandidatePanelTypography {
    static func shortcutFont() -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    }

    static func font(for role: CandidatePanelVisualRole) -> NSFont {
        switch role {
        case .lockedPrefix:
            return .systemFont(ofSize: 15, weight: .regular)
        case .continuation:
            return .systemFont(ofSize: 15, weight: .regular)
        case .rawInput:
            return .monospacedSystemFont(ofSize: 13, weight: .regular)
        }
    }
}

@MainActor
private final class CandidatePanelContentView: NSView, CandidatePanelContentRendering {
    private let effectView = NSVisualEffectView()
    private let stackView = NSStackView()

    var appKitView: NSView {
        self
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var isFlipped: Bool {
        true
    }

    func update(model: CandidatePanelRenderModel, layoutPlan: CandidatePanelLayoutPlan) {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        stackView.orientation = layoutPlan.orientation == .horizontal ? .horizontal : .vertical
        stackView.alignment = layoutPlan.orientation == .horizontal ? .centerY : .leading
        stackView.spacing = layoutPlan.itemSpacing
        stackView.edgeInsets = NSEdgeInsets(
            top: layoutPlan.contentInsets.top,
            left: layoutPlan.contentInsets.left,
            bottom: layoutPlan.contentInsets.bottom,
            right: layoutPlan.contentInsets.right
        )

        for item in layoutPlan.items {
            guard model.rows.indices.contains(item.rowIndex) else {
                continue
            }
            stackView.addArrangedSubview(makeRowView(model.rows[item.rowIndex], layoutItem: item))
        }

        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 6
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.18).cgColor
        effectView.layer?.borderWidth = 0.5
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 2
        stackView.edgeInsets = NSEdgeInsets(top: 4, left: 5, bottom: 4, right: 5)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: effectView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])
    }

    private func makeRowView(_ row: CandidatePanelRenderRow, layoutItem: CandidatePanelLayoutItem) -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 4
        container.edgeInsets = NSEdgeInsets(top: 1, left: 5, bottom: 1, right: 7)
        container.wantsLayer = true
        container.layer?.cornerRadius = 4
        container.layer?.cornerCurve = .continuous
        container.layer?.backgroundColor = rowBackgroundColor(row).cgColor
        container.widthAnchor.constraint(equalToConstant: layoutItem.frame.width).isActive = true
        container.heightAnchor.constraint(equalToConstant: layoutItem.frame.height).isActive = true

        if let shortcutLabel = row.shortcutLabel {
            container.addArrangedSubview(
                makeShortcutLabel(
                    shortcutLabel,
                    role: row.visualRole,
                    isSelected: row.isSelected
                )
            )
        }

        let textLabel = baseLabel(row.text)
        textLabel.font = CandidatePanelTypography.font(for: row.visualRole)
        textLabel.textColor = textColor(for: row.visualRole, isSelected: row.isSelected)
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textLabel.widthAnchor.constraint(lessThanOrEqualToConstant: layoutItem.textWidthLimit).isActive = true
        container.addArrangedSubview(textLabel)
        return container
    }

    private func rowBackgroundColor(_ row: CandidatePanelRenderRow) -> NSColor {
        guard row.isSelected else {
            return .clear
        }
        return .selectedContentBackgroundColor
    }

    private func makeShortcutLabel(
        _ text: String,
        role: CandidatePanelVisualRole,
        isSelected: Bool
    ) -> NSTextField {
        let label = baseLabel(text)
        label.font = CandidatePanelTypography.shortcutFont()
        label.textColor = shortcutColor(for: role, isSelected: isSelected)
        label.alignment = .right
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: 20).isActive = true
        return label
    }

    private func baseLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func textColor(for role: CandidatePanelVisualRole, isSelected: Bool) -> NSColor {
        if isSelected {
            return .alternateSelectedControlTextColor
        }
        switch role {
        case .lockedPrefix:
            return .labelColor
        case .continuation:
            return .secondaryLabelColor
        case .rawInput:
            return .tertiaryLabelColor
        }
    }

    private func shortcutColor(for role: CandidatePanelVisualRole, isSelected: Bool) -> NSColor {
        if isSelected {
            return .alternateSelectedControlTextColor
        }
        switch role {
        case .lockedPrefix:
            return .secondaryLabelColor
        case .continuation, .rawInput:
            return .tertiaryLabelColor
        }
    }
}
#endif
