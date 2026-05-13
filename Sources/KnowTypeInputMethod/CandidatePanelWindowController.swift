import Foundation

#if canImport(AppKit)
import AppKit
import KnowTypeCore

@MainActor
final class CandidatePanelWindowController {
    private var panel: NSPanel?
    private let contentView = CandidatePanelContentView()

    func update(state: CandidatePanelState, locale: KnowTypeLocale) {
        let windowState = state.windowState
        guard windowState.isVisible else {
            hide()
            return
        }

        let renderModel = CandidatePanelRenderer(locale: locale).render(
            windowState.viewModel,
            selected: windowState.selection
        )
        contentView.update(model: renderModel)

        let panel = candidatePanel()
        let contentSize = contentView.fittingSize
        panel.setContentSize(contentSize)
        panel.setFrameOrigin(origin(for: windowState.anchorRect, contentSize: contentSize))
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func candidatePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 120),
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
        self.panel = panel
        return panel
    }

    private func origin(for anchorRect: CGRect, contentSize: NSSize) -> NSPoint {
        let fallbackAnchor = fallbackAnchorRect()
        let anchor = anchorRect.isNull || anchorRect.isEmpty || anchorRect == .zero
            ? fallbackAnchor
            : anchorRect
        let visibleFrame = screen(containing: anchor)?.visibleFrame ?? NSScreen.main?.visibleFrame
        guard let visibleFrame else {
            return NSPoint(x: max(8, anchor.minX), y: max(8, anchor.minY - contentSize.height - 6))
        }

        let inset: CGFloat = 8
        let minX = visibleFrame.minX + inset
        let maxX = visibleFrame.maxX - contentSize.width - inset
        let minY = visibleFrame.minY + inset
        let maxY = visibleFrame.maxY - contentSize.height - inset
        let preferredY = anchor.minY - contentSize.height - 6
        let fallbackY = anchor.maxY + 6

        return NSPoint(
            x: clamp(anchor.minX, minimum: minX, maximum: maxX),
            y: clamp(preferredY < minY ? fallbackY : preferredY, minimum: minY, maximum: maxY)
        )
    }

    private func screen(containing rect: CGRect) -> NSScreen? {
        let point = NSPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.screens.first { $0.frame.intersects(rect) }
    }

    private func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        guard maximum >= minimum else {
            return minimum
        }
        return min(max(value, minimum), maximum)
    }

    private func fallbackAnchorRect() -> CGRect {
        if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) {
            return CGRect(x: mouseScreen.frame.minX + 24, y: mouseScreen.frame.maxY - 80, width: 1, height: 1)
        }
        if let screen = NSScreen.main {
            return CGRect(x: screen.visibleFrame.minX + 24, y: screen.visibleFrame.maxY - 80, width: 1, height: 1)
        }
        return CGRect(x: 24, y: 600, width: 1, height: 1)
    }
}

@MainActor
private final class CandidatePanelContentView: NSView {
    private let stackView = NSStackView()

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

        if let previewText = model.previewText {
            stackView.addArrangedSubview(makePreviewLabel(previewText))
        }

        for row in model.rows {
            stackView.addArrangedSubview(makeRowView(row))
        }

        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        layer?.cornerRadius = 8
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        layer?.borderWidth = 1

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 2
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            widthAnchor.constraint(lessThanOrEqualToConstant: 420)
        ])
    }

    private func makePreviewLabel(_ text: String) -> NSTextField {
        let label = baseLabel(text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func makeRowView(_ row: CandidatePanelRenderRow) -> NSView {
        if row.kind == .sectionHeader {
            let label = baseLabel(row.text.uppercased())
            label.font = .systemFont(ofSize: 10, weight: .semibold)
            label.textColor = .secondaryLabelColor
            return label
        }

        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 8
        container.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        container.wantsLayer = true
        container.layer?.cornerRadius = 5
        container.layer?.backgroundColor = row.isSelected
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor

        if let shortcutLabel = row.shortcutLabel {
            container.addArrangedSubview(makeShortcutLabel(shortcutLabel))
        }

        let textLabel = baseLabel(row.text)
        textLabel.font = font(for: row.visualRole)
        textLabel.textColor = textColor(for: row.visualRole)
        textLabel.lineBreakMode = .byTruncatingTail
        container.addArrangedSubview(textLabel)
        return container
    }

    private func makeShortcutLabel(_ text: String) -> NSTextField {
        let label = baseLabel(text)
        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        let minimumWidth = max(32, ceil(label.intrinsicContentSize.width) + 10)
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: minimumWidth).isActive = true
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
            return .systemFont(ofSize: 13, weight: .semibold)
        case .continuation:
            return .systemFont(ofSize: 13, weight: .regular)
        case .rawInput:
            return .monospacedSystemFont(ofSize: 12, weight: .regular)
        case .sectionHeader:
            return .systemFont(ofSize: 10, weight: .semibold)
        }
    }

    private func textColor(for role: CandidatePanelVisualRole) -> NSColor {
        switch role {
        case .lockedPrefix:
            return .labelColor
        case .continuation:
            return .secondaryLabelColor
        case .rawInput:
            return .tertiaryLabelColor
        case .sectionHeader:
            return .secondaryLabelColor
        }
    }
}
#endif
