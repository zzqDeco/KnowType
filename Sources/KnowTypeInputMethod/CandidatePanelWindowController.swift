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
    var fittingSize: NSSize { get }

    func update(model: CandidatePanelRenderModel)
}

enum CandidatePanelWindowSizing {
    static let minimumSize = NSSize(width: 180, height: 30)
    static let maximumSize = NSSize(width: 560, height: 44)

    static func constrained(_ size: NSSize) -> NSSize {
        NSSize(
            width: clamp(size.width, minimum: minimumSize.width, maximum: maximumSize.width),
            height: clamp(size.height, minimum: minimumSize.height, maximum: maximumSize.height)
        )
    }

    private static func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        guard maximum >= minimum else {
            return minimum
        }
        return min(max(value, minimum), maximum)
    }
}

enum CandidatePanelWindowPlacement {
    private static let visibleFrameInset: CGFloat = 8
    private static let verticalAnchorSpacing: CGFloat = 6

    static func origin(
        for anchorRect: CGRect,
        contentSize: NSSize,
        screenProvider: ScreenGeometryProviding
    ) -> NSPoint? {
        guard CandidateAnchorValidation.isUsable(anchorRect, screenProvider: screenProvider) else {
            return nil
        }

        let anchor = CandidateAnchorValidation.normalized(anchorRect)
        guard let visibleFrame = screenProvider.screen(containing: anchor)?.visibleFrame else {
            return nil
        }

        let minX = visibleFrame.minX + visibleFrameInset
        let maxX = visibleFrame.maxX - contentSize.width - visibleFrameInset
        let minY = visibleFrame.minY + visibleFrameInset
        let maxY = visibleFrame.maxY - contentSize.height - visibleFrameInset
        let preferredY = anchor.minY - contentSize.height - verticalAnchorSpacing
        let fallbackY = anchor.maxY + verticalAnchorSpacing

        return NSPoint(
            x: clamp(anchor.minX, minimum: minX, maximum: maxX),
            y: clamp(preferredY < minY ? fallbackY : preferredY, minimum: minY, maximum: maxY)
        )
    }

    private static func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        guard maximum >= minimum else {
            return minimum
        }
        return min(max(value, minimum), maximum)
    }
}

@MainActor
final class CandidatePanelWindowController {
    private var panel: CandidatePanelWindowOperating?
    private let contentView: CandidatePanelContentRendering
    private let screenProvider: ScreenGeometryProviding
    private let makePanel: @MainActor (NSView) -> CandidatePanelWindowOperating

    convenience init() {
        self.init(
            screenProvider: AppKitScreenGeometryProvider(),
            contentView: CandidatePanelContentView(),
            makePanel: Self.makeAppKitPanel
        )
    }

    init(
        screenProvider: ScreenGeometryProviding,
        contentView: CandidatePanelContentRendering,
        makePanel: @escaping @MainActor (NSView) -> CandidatePanelWindowOperating
    ) {
        self.screenProvider = screenProvider
        self.contentView = contentView
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
        contentView.update(model: renderModel)

        let panel = candidatePanel()
        let contentSize = CandidatePanelWindowSizing.constrained(contentView.fittingSize)
        panel.setContentSize(contentSize)
        if let origin = CandidatePanelWindowPlacement.origin(
            for: windowState.anchorRect,
            contentSize: contentSize,
            screenProvider: screenProvider
        ) {
            panel.setFrameOrigin(origin)
        } else {
            panel.orderOut(nil)
            return
        }
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

    func update(model: CandidatePanelRenderModel) {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for row in model.rows {
            stackView.addArrangedSubview(makeRowView(row))
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
            stackView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: CandidatePanelWindowSizing.minimumSize.width),
            widthAnchor.constraint(lessThanOrEqualToConstant: CandidatePanelWindowSizing.maximumSize.width),
            heightAnchor.constraint(greaterThanOrEqualToConstant: CandidatePanelWindowSizing.minimumSize.height),
            heightAnchor.constraint(lessThanOrEqualToConstant: CandidatePanelWindowSizing.maximumSize.height)
        ])
    }

    private func makeRowView(_ row: CandidatePanelRenderRow) -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 4
        container.edgeInsets = NSEdgeInsets(top: 1, left: 5, bottom: 1, right: 7)
        container.wantsLayer = true
        container.layer?.cornerRadius = 4
        container.layer?.cornerCurve = .continuous
        container.layer?.backgroundColor = rowBackgroundColor(row).cgColor
        container.heightAnchor.constraint(equalToConstant: 24).isActive = true

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
        textLabel.font = font(for: row.visualRole)
        textLabel.textColor = textColor(for: row.visualRole, isSelected: row.isSelected)
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textLabel.widthAnchor.constraint(lessThanOrEqualToConstant: textWidthLimit(for: row.visualRole)).isActive = true
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
        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
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

    private func font(for role: CandidatePanelVisualRole) -> NSFont {
        switch role {
        case .lockedPrefix:
            return .systemFont(ofSize: 15, weight: .regular)
        case .continuation:
            return .systemFont(ofSize: 15, weight: .regular)
        case .rawInput:
            return .monospacedSystemFont(ofSize: 13, weight: .regular)
        }
    }

    private func textWidthLimit(for role: CandidatePanelVisualRole) -> CGFloat {
        switch role {
        case .lockedPrefix:
            return 148
        case .continuation:
            return 188
        case .rawInput:
            return 260
        }
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
