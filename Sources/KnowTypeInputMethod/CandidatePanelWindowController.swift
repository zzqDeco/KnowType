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

struct CandidatePanelWindowConfiguration {
    var contentRect = NSRect(x: 0, y: 0, width: 220, height: 32)
    var styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    var level: NSWindow.Level = .popUpMenu
    var collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .ignoresCycle
    ]
    var hasShadow = true
    var isFloatingPanel = true
    var worksWhenModal = true
    var hidesOnDeactivate = false
    var isOpaque = false
    var backgroundColor: NSColor = .clear
    var isReleasedWhenClosed = false

    static let native = CandidatePanelWindowConfiguration()

    @MainActor
    func apply(to panel: NSPanel) {
        panel.level = level
        panel.collectionBehavior = collectionBehavior
        panel.hasShadow = hasShadow
        panel.isFloatingPanel = isFloatingPanel
        panel.worksWhenModal = worksWhenModal
        panel.hidesOnDeactivate = hidesOnDeactivate
        panel.isOpaque = isOpaque
        panel.backgroundColor = backgroundColor
        panel.isReleasedWhenClosed = isReleasedWhenClosed
    }
}

@MainActor
protocol CandidatePanelContentRendering: AnyObject {
    var appKitView: NSView { get }
    var interactionHandler: CandidatePanelContentInteractionHandling? { get set }

    func update(model: CandidatePanelRenderModel, layoutPlan: CandidatePanelLayoutPlan)
}

@MainActor
protocol CandidatePanelContentInteractionHandling: AnyObject {
    func candidatePanelContentDidHover(_ selection: CandidatePanelSelection)
    func candidatePanelContentDidCommit(_ selection: CandidatePanelSelection)
    func candidatePanelContentDidScroll(_ navigation: InputCandidateNavigation)
}

protocol CandidatePanelInteractionHandling: AnyObject {
    func candidatePanelDidHover(_ selection: CandidatePanelSelection)
    func candidatePanelDidCommit(_ selection: CandidatePanelSelection)
    func candidatePanelDidScroll(_ navigation: InputCandidateNavigation)
}

@MainActor
final class CandidatePanelWindowController: CandidatePanelContentInteractionHandling {
    private var panel: CandidatePanelWindowOperating?
    private let contentView: CandidatePanelContentRendering
    private let screenProvider: ScreenGeometryProviding
    private let layoutEngine: CandidatePanelLayoutEngine
    private let makePanel: @MainActor (NSView) -> CandidatePanelWindowOperating
    private let panelAppearance: CandidatePanelAppearance
    private weak var interactionHandler: CandidatePanelInteractionHandling?
    private var lastPresentationSignature: CandidatePanelPresentationSignature?
    private var isPanelOrderedVisible = false
    private var latestAppliedPresentationGeneration = 0

    convenience init(interactionHandler: CandidatePanelInteractionHandling? = nil) {
        self.init(
            screenProvider: AppKitScreenGeometryProvider(),
            contentView: CandidatePanelContentView(appearance: .native),
            layoutEngine: CandidatePanelLayoutEngine(textMeasurer: CachingCandidatePanelTextMeasurer(appearance: .native)),
            makePanel: Self.makeAppKitPanel,
            appearance: .native,
            interactionHandler: interactionHandler
        )
    }

    init(
        screenProvider: ScreenGeometryProviding,
        contentView: CandidatePanelContentRendering,
        layoutEngine: CandidatePanelLayoutEngine,
        makePanel: @escaping @MainActor (NSView) -> CandidatePanelWindowOperating,
        appearance: CandidatePanelAppearance = .native,
        interactionHandler: CandidatePanelInteractionHandling? = nil
    ) {
        self.screenProvider = screenProvider
        self.contentView = contentView
        self.layoutEngine = layoutEngine
        self.makePanel = makePanel
        self.panelAppearance = appearance
        self.interactionHandler = interactionHandler
        self.contentView.interactionHandler = self
    }

    func update(state: CandidatePanelState, locale: KnowTypeLocale) {
        let windowState = state.windowState
        guard windowState.isVisible else {
            hide()
            return
        }
        let presentationSignature = CandidatePanelPresentationSignature(
            windowState: windowState,
            locale: locale,
            screens: screenProvider.screens
        )
        if isPanelOrderedVisible,
           presentationSignature == lastPresentationSignature,
           let panel {
            panel.orderFrontRegardless()
            return
        }

        let renderModel = CandidatePanelRenderer(locale: locale).render(
            windowState.viewModel,
            selected: windowState.selection,
            paging: windowState.paging
        )

        let panel = candidatePanel()
        let effectiveLayoutEngine = CandidatePanelLayoutEngine(
            configuration: panelAppearance.layoutConfiguration(layoutMode: windowState.layoutMode),
            textMeasurer: layoutEngine.textMeasurer
        )
        let layoutStartedAt = ContinuousClock.now
        guard let layoutPlan = effectiveLayoutEngine.layout(
            model: renderModel,
            anchorRect: windowState.anchorRect,
            screenProvider: screenProvider,
            placementPreference: windowState.placementPreference
        ) else {
            traceLayout(
                windowState: windowState,
                renderModel: renderModel,
                layoutPlan: nil,
                elapsedMilliseconds: InputDebugDiagnostics.milliseconds(layoutStartedAt.duration(to: .now))
            )
            orderOutPanel(panel)
            return
        }
        traceLayout(
            windowState: windowState,
            renderModel: renderModel,
            layoutPlan: layoutPlan,
            elapsedMilliseconds: InputDebugDiagnostics.milliseconds(layoutStartedAt.duration(to: .now))
        )
        panel.setContentSize(layoutPlan.panelSize)
        panel.setFrameOrigin(layoutPlan.panelOrigin)
        contentView.update(model: renderModel, layoutPlan: layoutPlan)
        panel.orderFrontRegardless()
        markPanelVisible(presentationSignature: presentationSignature)
    }

    func apply(frame: CandidatePanelFrame, locale: KnowTypeLocale) {
        guard frame.presentationGeneration >= latestAppliedPresentationGeneration else {
            traceDroppedFrame(frame)
            return
        }
        let startedAt = ContinuousClock.now
        latestAppliedPresentationGeneration = frame.presentationGeneration
        if frame.isVisible {
            update(state: frame.panelModel, locale: locale)
        } else {
            hide()
        }
        traceAppliedFrame(
            frame,
            elapsedMilliseconds: InputDebugDiagnostics.milliseconds(startedAt.duration(to: .now))
        )
    }

    func candidatePanelContentDidHover(_ selection: CandidatePanelSelection) {
        interactionHandler?.candidatePanelDidHover(selection)
    }

    func candidatePanelContentDidCommit(_ selection: CandidatePanelSelection) {
        interactionHandler?.candidatePanelDidCommit(selection)
    }

    func candidatePanelContentDidScroll(_ navigation: InputCandidateNavigation) {
        interactionHandler?.candidatePanelDidScroll(navigation)
    }

    func hide() {
        orderOutPanel(panel)
    }

    private func orderOutPanel(_ panel: CandidatePanelWindowOperating?) {
        panel?.orderOut(nil)
        isPanelOrderedVisible = false
        lastPresentationSignature = nil
    }

    private func markPanelVisible(presentationSignature: CandidatePanelPresentationSignature) {
        isPanelOrderedVisible = true
        lastPresentationSignature = presentationSignature
    }

    private func candidatePanel() -> CandidatePanelWindowOperating {
        if let panel {
            return panel
        }

        let panel = makePanel(contentView.appKitView)
        self.panel = panel
        return panel
    }

    private func traceLayout(
        windowState: CandidatePanelWindowState,
        renderModel: CandidatePanelRenderModel,
        layoutPlan: CandidatePanelLayoutPlan?,
        elapsedMilliseconds: Double
    ) {
        guard InputDebugDiagnostics.isEnabled(.panel) else {
            return
        }
        let layoutReason: String
        if let layoutPlan {
            layoutReason = "layoutMode=\(windowState.layoutMode.rawValue);placement=\(layoutPlan.verticalPlacement.rawValue);renderRows=\(renderModel.rows.count)"
        } else {
            layoutReason = "layoutMode=\(windowState.layoutMode.rawValue);placement=none;renderRows=\(renderModel.rows.count)"
        }
        InputDebugDiagnostics.emit(
            category: .panel,
            fields: [
                .init(.stage, "window_layout"),
                .init(.elapsedMs, String(format: "%.2f", elapsedMilliseconds)),
                .init(.anchorSource, windowState.anchorSource.rawValue),
                .init(.handled, layoutPlan != nil),
                .init(.reason, layoutReason)
            ]
        )
    }

    private func traceDroppedFrame(_ frame: CandidatePanelFrame) {
        guard InputDebugDiagnostics.isEnabled(.panel) else {
            return
        }
        InputDebugDiagnostics.emit(
            category: .panel,
            fields: [
                .init(.stage, "window_drop"),
                .init(.panelGeneration, frame.presentationGeneration),
                .init(.reason, "stale_frame;latestGeneration=\(latestAppliedPresentationGeneration);visibilityReason=\(frame.visibilityReason.rawValue)"),
                .init(.compositionID, frame.compositionID),
                .init(.rawRevision, frame.rawRevision),
                .init(.rawLength, frame.rawLength),
                .init(.anchorSource, frame.anchorSource.rawValue),
                .init(.handled, false)
            ]
        )
    }

    private func traceAppliedFrame(
        _ frame: CandidatePanelFrame,
        elapsedMilliseconds: Double
    ) {
        guard InputDebugDiagnostics.isEnabled(.panel) else {
            return
        }
        InputDebugDiagnostics.emit(
            category: .panel,
            fields: [
                .init(.stage, "window_apply"),
                .init(.elapsedMs, String(format: "%.2f", elapsedMilliseconds)),
                .init(.panelGeneration, frame.presentationGeneration),
                .init(.reason, frame.visibilityReason.rawValue),
                .init(.compositionID, frame.compositionID),
                .init(.rawRevision, frame.rawRevision),
                .init(.rawLength, frame.rawLength),
                .init(.anchorSource, frame.anchorSource.rawValue),
                .init(.handled, frame.isVisible)
            ]
        )
    }

    private static func makeAppKitPanel(contentView: NSView) -> CandidatePanelWindowOperating {
        let configuration = CandidatePanelWindowConfiguration.native
        let panel = NSPanel(
            contentRect: configuration.contentRect,
            styleMask: configuration.styleMask,
            backing: .buffered,
            defer: true
        )
        configuration.apply(to: panel)
        panel.contentView = contentView
        return panel
    }

}

private struct CandidatePanelPresentationSignature: Equatable {
    var windowState: CandidatePanelWindowState
    var locale: KnowTypeLocale
    var screens: [CandidateAnchorScreen]
}

private final class CachingCandidatePanelTextMeasurer: CandidatePanelTextMeasuring {
    private let base: AppKitCandidatePanelTextMeasurer
    private var textWidthCache: [TextWidthKey: CGFloat] = [:]
    private var shortcutWidthCache: [String: CGFloat] = [:]

    init(appearance: CandidatePanelAppearance = .native) {
        self.base = AppKitCandidatePanelTextMeasurer(appearance: appearance)
    }

    func textWidth(for row: CandidatePanelRenderRow) -> CGFloat {
        let key = TextWidthKey(text: row.text, role: row.visualRole)
        if let width = textWidthCache[key] {
            return width
        }
        let width = base.textWidth(for: row)
        textWidthCache[key] = width
        return width
    }

    func shortcutWidth(for label: String) -> CGFloat {
        if let width = shortcutWidthCache[label] {
            return width
        }
        let width = base.shortcutWidth(for: label)
        shortcutWidthCache[label] = width
        return width
    }
}

private struct TextWidthKey: Hashable {
    var text: String
    var role: CandidatePanelVisualRole
}

private struct AppKitCandidatePanelTextMeasurer: CandidatePanelTextMeasuring {
    var appearance: CandidatePanelAppearance = .native

    func textWidth(for row: CandidatePanelRenderRow) -> CGFloat {
        ceil(
            (row.text as NSString).size(
                withAttributes: [
                    .font: appearance.font(for: row.visualRole)
                ]
            ).width
        )
    }

    func shortcutWidth(for label: String) -> CGFloat {
        ceil(
            (label as NSString).size(
                withAttributes: [
                    .font: appearance.shortcutFont()
                ]
            ).width
        )
    }
}

struct CandidatePanelScrollPagingState {
    static let deltaThreshold: CGFloat = 3
    static let wheelCooldown: TimeInterval = 0.120

    private var accumulatedGestureDelta: CGFloat = 0
    private var isGestureActive = false
    private var didPageDuringGesture = false
    private var lastWheelPageTimestamp: TimeInterval?

    mutating func navigation(
        forDelta delta: CGFloat,
        hasPreciseScrollingDeltas: Bool,
        phase: NSEvent.Phase,
        momentumPhase: NSEvent.Phase,
        timestamp: TimeInterval
    ) -> InputCandidateNavigation? {
        guard momentumPhase.isEmpty else {
            return nil
        }

        if phase.isEmpty {
            return wheelNavigation(
                forDelta: delta,
                hasPreciseScrollingDeltas: hasPreciseScrollingDeltas,
                timestamp: timestamp
            )
        }

        if phase.contains(.cancelled) {
            endGesture()
            return nil
        }
        if phase.contains(.began) || !isGestureActive {
            beginGesture()
        }

        accumulatedGestureDelta += delta
        var navigation: InputCandidateNavigation?
        if !didPageDuringGesture,
           abs(accumulatedGestureDelta) >= Self.deltaThreshold {
            didPageDuringGesture = true
            navigation = Self.navigation(forDelta: accumulatedGestureDelta)
        }

        if phase.contains(.ended) {
            endGesture()
        }
        return navigation
    }

    private mutating func wheelNavigation(
        forDelta delta: CGFloat,
        hasPreciseScrollingDeltas: Bool,
        timestamp: TimeInterval
    ) -> InputCandidateNavigation? {
        let reachesPagingThreshold = hasPreciseScrollingDeltas
            ? abs(delta) >= Self.deltaThreshold
            : delta != 0
        guard reachesPagingThreshold else {
            return nil
        }
        if let lastWheelPageTimestamp,
           timestamp - lastWheelPageTimestamp < Self.wheelCooldown {
            return nil
        }
        lastWheelPageTimestamp = timestamp
        return Self.navigation(forDelta: delta)
    }

    private mutating func beginGesture() {
        accumulatedGestureDelta = 0
        isGestureActive = true
        didPageDuringGesture = false
    }

    private mutating func endGesture() {
        accumulatedGestureDelta = 0
        isGestureActive = false
        didPageDuringGesture = false
    }

    private static func navigation(forDelta delta: CGFloat) -> InputCandidateNavigation {
        delta < 0 ? .pageDown : .pageUp
    }
}

@MainActor
final class CandidatePanelContentView: NSView, CandidatePanelContentRendering {
    private let backgroundView: NSView
    private let effectView: NSVisualEffectView?
    private let stackView = NSStackView()
    private let panelAppearance: CandidatePanelAppearance
    private var rowHitTargets: [CandidatePanelRowHitTarget] = []
    private var accessibilityRows: [CandidatePanelAccessibilityRow] = []
    private var hoverSelection: CandidatePanelSelection?
    private var mouseDownSelection: CandidatePanelSelection?
    private var trackingArea: NSTrackingArea?
    private var scrollPagingState = CandidatePanelScrollPagingState()
    private var accessibilityRenderGeneration: UInt64 = 0
    weak var interactionHandler: CandidatePanelContentInteractionHandling?

    var appKitView: NSView {
        self
    }

    init(frame frameRect: NSRect = .zero, appearance: CandidatePanelAppearance = .native) {
        self.panelAppearance = appearance
        if appearance.usesSnapshotColors {
            self.backgroundView = NSView()
            self.effectView = nil
        } else {
            let effectView = NSVisualEffectView()
            self.backgroundView = effectView
            self.effectView = effectView
        }
        super.init(frame: frameRect)
        applySnapshotAppearanceIfNeeded()
        setup()
    }

    required init?(coder: NSCoder) {
        self.panelAppearance = .native
        let effectView = NSVisualEffectView()
        self.backgroundView = effectView
        self.effectView = effectView
        super.init(coder: coder)
        setup()
    }

    override var isFlipped: Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    func update(model: CandidatePanelRenderModel, layoutPlan: CandidatePanelLayoutPlan) {
        accessibilityRenderGeneration &+= 1
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        rowHitTargets = []

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
            let row = model.rows[item.rowIndex]
            stackView.addArrangedSubview(makeRowView(row, layoutItem: item))
            rowHitTargets.append(
                CandidatePanelRowHitTarget(
                    frame: item.frame,
                    selection: row.selection,
                    isEnabled: row.isEnabled && row.selection != nil,
                    accessibilityLabel: row.accessibilityLabel,
                    isSelected: row.isSelected
                )
            )
        }
        rebuildAccessibilityRows()

        needsLayout = true
        layoutSubtreeIfNeeded()
        updateTrackingAreas()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        if let effectView {
            effectView.material = panelAppearance.material
            effectView.blendingMode = panelAppearance.blendingMode
            effectView.state = .active
        }
        backgroundView.appearance = appearance
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = panelAppearance.panelCornerRadius
        backgroundView.layer?.cornerCurve = .continuous
        backgroundView.layer?.masksToBounds = true
        backgroundView.layer?.borderColor = panelAppearance.panelBorderColor().cgColor
        backgroundView.layer?.borderWidth = panelAppearance.borderWidth
        backgroundView.layer?.backgroundColor = panelAppearance.panelBackgroundColor()?.cgColor
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = panelAppearance.horizontalItemSpacing
        stackView.edgeInsets = NSEdgeInsets(
            top: panelAppearance.contentInsets.top,
            left: panelAppearance.contentInsets.left,
            bottom: panelAppearance.contentInsets.bottom,
            right: panelAppearance.contentInsets.right
        )
        stackView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor)
        ])
    }

    private func applySnapshotAppearanceIfNeeded() {
        guard panelAppearance.usesSnapshotColors else {
            return
        }
        appearance = NSAppearance(
            named: panelAppearance.usesSnapshotDarkColors ? .darkAqua : .aqua
        )
    }

    private func makeRowView(_ row: CandidatePanelRenderRow, layoutItem: CandidatePanelLayoutItem) -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = row.accessory == nil
            ? panelAppearance.shortcutTextSpacing
            : panelAppearance.accessoryTextSpacing
        container.edgeInsets = NSEdgeInsets(
            top: panelAppearance.itemInsets.top,
            left: panelAppearance.itemInsets.left,
            bottom: panelAppearance.itemInsets.bottom,
            right: panelAppearance.itemInsets.right
        )
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = panelAppearance.rowCornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.backgroundColor = rowBackgroundColor(row).cgColor
        container.widthAnchor.constraint(equalToConstant: layoutItem.frame.width).isActive = true
        container.heightAnchor.constraint(equalToConstant: layoutItem.frame.height).isActive = true

        if let shortcutLabel = row.shortcutLabel {
            container.addArrangedSubview(
                makeShortcutLabel(
                    shortcutLabel,
                    role: row.visualRole,
                    isSelected: row.isSelected,
                    labelWidth: layoutItem.shortcutLabelWidth > 0 ? layoutItem.shortcutLabelWidth : nil
                )
            )
        }

        if row.accessory == .spinner {
            container.addArrangedSubview(makeSpinner())
        }

        if !row.text.isEmpty {
            let textLabel = baseLabel(row.text)
            textLabel.font = panelAppearance.font(for: row.visualRole)
            textLabel.textColor = textColor(for: row.visualRole, isSelected: row.isSelected, isEnabled: row.isEnabled)
            textLabel.lineBreakMode = .byTruncatingTail
            textLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            textLabel.widthAnchor.constraint(lessThanOrEqualToConstant: layoutItem.textWidthLimit).isActive = true
            container.addArrangedSubview(textLabel)
        }
        return container
    }

    private func makeSpinner() -> NSProgressIndicator {
        let spinner = NSProgressIndicator()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = true
        spinner.setContentCompressionResistancePriority(.required, for: .horizontal)
        spinner.setContentHuggingPriority(.required, for: .horizontal)
        spinner.widthAnchor.constraint(equalToConstant: panelAppearance.accessoryWidth).isActive = true
        spinner.heightAnchor.constraint(equalToConstant: panelAppearance.accessoryWidth).isActive = true
        spinner.startAnimation(nil)
        return spinner
    }

    private func rowBackgroundColor(_ row: CandidatePanelRenderRow) -> NSColor {
        panelAppearance.rowBackgroundColor(isSelected: row.isSelected)
    }

    private func makeShortcutLabel(
        _ text: String,
        role: CandidatePanelVisualRole,
        isSelected: Bool,
        labelWidth: CGFloat?
    ) -> NSTextField {
        let label = baseLabel(text)
        label.font = panelAppearance.shortcutFont()
        label.textColor = shortcutColor(for: role, isSelected: isSelected, isEnabled: true)
        label.alignment = .right
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        if let labelWidth {
            label.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        }
        return label
    }

    private func baseLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    override func mouseMoved(with event: NSEvent) {
        guard let selection = hitTarget(at: convert(event.locationInWindow, from: nil))?.selection else {
            hoverSelection = nil
            return
        }
        guard hoverSelection != selection else {
            return
        }
        hoverSelection = selection
        interactionHandler?.candidatePanelContentDidHover(selection)
    }

    override func mouseExited(with event: NSEvent) {
        hoverSelection = nil
        mouseDownSelection = nil
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownSelection = hitTarget(at: convert(event.locationInWindow, from: nil))?.selection
    }

    override func mouseUp(with event: NSEvent) {
        let upSelection = hitTarget(at: convert(event.locationInWindow, from: nil))?.selection
        defer {
            mouseDownSelection = nil
        }
        guard let upSelection,
              upSelection == mouseDownSelection else {
            return
        }
        commitSelection(upSelection)
    }

    override func scrollWheel(with event: NSEvent) {
        let dominantDelta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
            ? event.scrollingDeltaY
            : event.scrollingDeltaX
        guard let navigation = scrollPagingState.navigation(
            forDelta: dominantDelta,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
            phase: event.phase,
            momentumPhase: event.momentumPhase,
            timestamp: event.timestamp
        ) else {
            return
        }
        interactionHandler?.candidatePanelContentDidScroll(navigation)
    }

    override func isAccessibilityElement() -> Bool {
        false
    }

    override func accessibilityChildren() -> [Any]? {
        accessibilityRows
    }

    override func accessibilityVisibleChildren() -> [Any]? {
        accessibilityRows
    }

    override func accessibilitySelectedChildren() -> [Any]? {
        accessibilityRows.filter(\.isSelected)
    }

    private func hitTarget(at point: NSPoint) -> CandidatePanelRowHitTarget? {
        rowHitTargets.first { target in
            target.isEnabled && target.frame.contains(point)
        }
    }

    private func rebuildAccessibilityRows() {
        accessibilityRows = rowHitTargets.enumerated().map { index, target in
            CandidatePanelAccessibilityRow(
                owner: self,
                index: index,
                frame: target.frame,
                screenFrame: accessibilityScreenFrame(for: target.frame),
                label: target.accessibilityLabel,
                selection: target.selection,
                renderGeneration: accessibilityRenderGeneration,
                isEnabled: target.isEnabled,
                isSelected: target.isSelected
            )
        }
        if let selected = accessibilityRows.first(where: \.isSelected) {
            NSAccessibility.post(element: selected, notification: .focusedUIElementChanged)
            NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
        }
    }

    private func accessibilityScreenFrame(for frame: NSRect) -> NSRect {
        guard let window else {
            return frame
        }
        return window.convertToScreen(convert(frame, to: nil))
    }

    @discardableResult
    fileprivate func commitSelection(_ selection: CandidatePanelSelection) -> Bool {
        guard let interactionHandler else {
            return false
        }
        interactionHandler.candidatePanelContentDidCommit(selection)
        return true
    }

    fileprivate func commitAccessibilitySelection(
        _ selection: CandidatePanelSelection,
        renderGeneration: UInt64
    ) -> Bool {
        guard renderGeneration == accessibilityRenderGeneration else {
            return false
        }
        return commitSelection(selection)
    }

    private func textColor(for role: CandidatePanelVisualRole, isSelected: Bool, isEnabled: Bool) -> NSColor {
        panelAppearance.textColor(for: role, isSelected: isSelected, isEnabled: isEnabled)
    }

    private func shortcutColor(for role: CandidatePanelVisualRole, isSelected: Bool, isEnabled: Bool) -> NSColor {
        panelAppearance.shortcutColor(for: role, isSelected: isSelected, isEnabled: isEnabled)
    }
}

private struct CandidatePanelRowHitTarget {
    var frame: CGRect
    var selection: CandidatePanelSelection?
    var isEnabled: Bool
    var accessibilityLabel: String
    var isSelected: Bool
}

private final class CandidatePanelAccessibilityRow: NSAccessibilityElement {
    weak var owner: CandidatePanelContentView?
    let index: Int
    let rowFrame: NSRect
    let screenFrame: NSRect
    let label: String
    let selection: CandidatePanelSelection?
    let renderGeneration: UInt64
    let isEnabled: Bool
    let isSelected: Bool

    init(
        owner: CandidatePanelContentView,
        index: Int,
        frame: NSRect,
        screenFrame: NSRect,
        label: String,
        selection: CandidatePanelSelection?,
        renderGeneration: UInt64,
        isEnabled: Bool,
        isSelected: Bool
    ) {
        self.owner = owner
        self.index = index
        self.rowFrame = frame
        self.screenFrame = screenFrame
        self.label = label
        self.selection = selection
        self.renderGeneration = renderGeneration
        self.isEnabled = isEnabled
        self.isSelected = isSelected
        super.init()
    }

    override func accessibilityParent() -> Any? {
        owner
    }

    override func accessibilityRole() -> NSAccessibility.Role {
        isEnabled ? .button : .staticText
    }

    override func accessibilityLabel() -> String? {
        label
    }

    override func isAccessibilityEnabled() -> Bool {
        isEnabled
    }

    override func isAccessibilitySelected() -> Bool {
        isSelected
    }

    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityFrame() -> NSRect {
        screenFrame
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled,
              let selection else {
            return false
        }
        let expectedRenderGeneration = renderGeneration
        return MainActor.assumeIsolated { [weak owner] in
            owner?.commitAccessibilitySelection(
                selection,
                renderGeneration: expectedRenderGeneration
            ) ?? false
        }
    }
}
#endif
