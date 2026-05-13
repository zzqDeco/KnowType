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
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 64),
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
        let mouseLocation = NSEvent.mouseLocation
        if NSScreen.screens.contains(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return CGRect(x: mouseLocation.x, y: mouseLocation.y, width: 1, height: 18)
        }
        if let screen = NSScreen.main {
            return CGRect(x: screen.visibleFrame.minX + 24, y: screen.visibleFrame.maxY - 80, width: 1, height: 1)
        }
        return CGRect(x: 24, y: 600, width: 1, height: 1)
    }
}

@MainActor
private final class CandidatePanelContentView: NSView {
    private let effectView = NSVisualEffectView()
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

        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.spacing = 0
        stackView.edgeInsets = NSEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: effectView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            widthAnchor.constraint(lessThanOrEqualToConstant: 420)
        ])
    }

    private func makePreviewLabel(_ text: String) -> NSTextField {
        let label = baseLabel("")
        label.attributedStringValue = previewString(text)
        label.cell?.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        return label
    }

    private func previewString(_ text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
        )
        let separator = " | "
        guard let separatorRange = text.range(of: separator) else {
            return attributed
        }

        let nsSeparatorRange = NSRange(separatorRange, in: text)
        attributed.addAttributes(
            [.foregroundColor: NSColor.separatorColor],
            range: nsSeparatorRange
        )
        let continuationStart = nsSeparatorRange.location + nsSeparatorRange.length
        attributed.addAttributes(
            [.foregroundColor: NSColor.secondaryLabelColor],
            range: NSRange(location: continuationStart, length: attributed.length - continuationStart)
        )
        return attributed
    }

    private func makeSectionHeader(_ text: String) -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 6
        container.edgeInsets = NSEdgeInsets(top: 4, left: 7, bottom: 1, right: 7)
        container.heightAnchor.constraint(greaterThanOrEqualToConstant: 16).isActive = true

        let label = baseLabel(text)
        label.font = .systemFont(ofSize: 9, weight: .medium)
        label.textColor = .tertiaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        let separator = NSBox()
        separator.boxType = .separator
        separator.setContentHuggingPriority(.defaultLow, for: .horizontal)

        container.addArrangedSubview(label)
        container.addArrangedSubview(separator)
        return container
    }

    private func makeRowView(_ row: CandidatePanelRenderRow) -> NSView {
        if row.kind == .sectionHeader {
            return makeSectionHeader(row.text)
        }

        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 7
        container.edgeInsets = NSEdgeInsets(top: 1, left: 7, bottom: 1, right: 9)
        container.wantsLayer = true
        container.layer?.cornerRadius = 3
        container.layer?.cornerCurve = .continuous
        container.layer?.backgroundColor = rowBackgroundColor(row).cgColor
        container.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true

        if let shortcutLabel = row.shortcutLabel {
            container.addArrangedSubview(makeShortcutLabel(shortcutLabel, isSelected: row.isSelected))
        }

        let textLabel = baseLabel(row.text)
        textLabel.font = font(for: row.visualRole)
        textLabel.textColor = textColor(for: row.visualRole, isSelected: row.isSelected)
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        container.addArrangedSubview(textLabel)
        return container
    }

    private func rowBackgroundColor(_ row: CandidatePanelRenderRow) -> NSColor {
        guard row.isSelected else {
            return .clear
        }
        return .selectedContentBackgroundColor
    }

    private func makeShortcutLabel(_ text: String, isSelected: Bool) -> NSTextField {
        let label = baseLabel(text)
        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        label.textColor = isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        label.alignment = .right
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: 28).isActive = true
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
        case .sectionHeader:
            return .systemFont(ofSize: 9, weight: .medium)
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
        case .sectionHeader:
            return .secondaryLabelColor
        }
    }
}
#endif
