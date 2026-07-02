#if canImport(AppKit)
import AppKit
import KnowTypeCore
import XCTest
@testable import KnowTypeInputMethod

final class CandidatePanelWindowControllerTests: XCTestCase {
    func testNativeWindowConfigurationUsesPopupNonactivatingCandidatePanelLevel() {
        let configuration = CandidatePanelWindowConfiguration.native

        XCTAssertTrue(configuration.styleMask.contains(.borderless))
        XCTAssertTrue(configuration.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(configuration.level, .popUpMenu)
        XCTAssertTrue(configuration.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(configuration.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(configuration.collectionBehavior.contains(.ignoresCycle))
        XCTAssertTrue(configuration.isFloatingPanel)
        XCTAssertTrue(configuration.worksWhenModal)
        XCTAssertFalse(configuration.hidesOnDeactivate)
    }

    @MainActor
    func testPendingAIContentRowRendersFixedSpinnerAccessory() throws {
        let contentView = CandidatePanelContentView(appearance: .native)
        let renderModel = CandidatePanelRenderModel(
            title: "候选",
            previewText: nil,
            rows: [
                CandidatePanelRenderRow(
                    kind: .aiRecommendation,
                    selection: nil,
                    shortcutLabel: nil,
                    text: "",
                    isSelected: false,
                    isEnabled: false,
                    visualRole: .aiRecommendation,
                    accessory: .spinner,
                    accessibilityLabel: "AI 状态，AI 推荐中"
                )
            ]
        )
        let layoutPlan = CandidatePanelLayoutPlan(
            orientation: .vertical,
            verticalPlacement: .visualBelowCaret,
            panelSize: CGSize(width: 220, height: 34),
            panelOrigin: .zero,
            contentInsets: CandidatePanelLayoutInsets(top: 4, left: 5, bottom: 4, right: 5),
            itemSpacing: 2,
            items: [
                CandidatePanelLayoutItem(
                    rowIndex: 0,
                    frame: CGRect(x: 5, y: 4, width: 210, height: 26),
                    textWidthLimit: 180,
                    isTruncated: false
                )
            ]
        )

        contentView.update(model: renderModel, layoutPlan: layoutPlan)

        let indicators = contentView.allDescendants().compactMap { $0 as? NSProgressIndicator }
        let labels = contentView.allDescendants().compactMap { $0 as? NSTextField }
        let indicator = try XCTUnwrap(indicators.first)
        XCTAssertEqual(indicators.count, 1)
        XCTAssertTrue(labels.isEmpty)
        XCTAssertEqual(indicator.style, .spinning)
        XCTAssertEqual(indicator.controlSize, .small)
        XCTAssertTrue(indicator.isIndeterminate)
        XCTAssertTrue(indicator.isDisplayedWhenStopped)
        XCTAssertTrue(indicator.constraints.contains { $0.constant == 12 })
    }

    @MainActor
    func testUpdateMovesExistingWindowWhenAnchorMoves() {
        let contentView = FakeCandidatePanelContentRenderer()
        let window = FakeCandidatePanelWindow()
        let screenProvider = fakeScreenProvider()
        var factoryCallCount = 0
        var factoryContentViews: [NSView] = []
        let controller = CandidatePanelWindowController(
            screenProvider: screenProvider,
            contentView: contentView,
            layoutEngine: layoutEngine(),
            makePanel: { view in
                factoryCallCount += 1
                factoryContentViews.append(view)
                return window
            }
        )

        controller.update(
            state: visibleState(anchor: CGRect(x: 100, y: 400, width: 0, height: 18)),
            locale: .zhCN
        )
        controller.update(
            state: visibleState(anchor: CGRect(x: 160, y: 420, width: 0, height: 18)),
            locale: .zhCN
        )

        let origins = window.frameOrigins
        let contentSizes = window.contentSizes
        let frontCount = window.orderFrontCount
        let outCount = window.orderOutCount
        let modelCount = contentView.models.count
        let factoryUsedContentView = factoryContentViews.first === contentView.appKitView

        XCTAssertEqual(factoryCallCount, 1)
        XCTAssertTrue(factoryUsedContentView)
        XCTAssertEqual(
            origins,
            [
                NSPoint(x: 100, y: 360),
                NSPoint(x: 160, y: 380)
            ]
        )
        XCTAssertEqual(contentSizes, [NSSize(width: 220, height: 34), NSSize(width: 220, height: 34)])
        XCTAssertEqual(frontCount, 2)
        XCTAssertEqual(outCount, 0)
        XCTAssertEqual(modelCount, 2)
    }

    @MainActor
    func testUpdateHonorsVisualAbovePlacementPreference() {
        let contentView = FakeCandidatePanelContentRenderer()
        let window = FakeCandidatePanelWindow()
        let controller = CandidatePanelWindowController(
            screenProvider: fakeScreenProvider(),
            contentView: contentView,
            layoutEngine: layoutEngine(),
            makePanel: { _ in window }
        )

        controller.update(
            state: visibleState(
                anchor: CGRect(x: 100, y: 400, width: 0, height: 18),
                placementPreference: .preferVisualAbove
            ),
            locale: .zhCN
        )

        XCTAssertEqual(window.frameOrigins, [NSPoint(x: 100, y: 424)])
        XCTAssertEqual(contentView.layoutPlans.last?.verticalPlacement, .visualAboveCaret)
    }

    func testPlacementAvoidsVisibleFrameEdges() {
        let engine = layoutEngine()
        let screenProvider = FakeCandidatePanelScreenProvider(
            screens: [
                CandidateAnchorScreen(
                    identifier: "main",
                    frame: CGRect(x: 0, y: 0, width: 500, height: 500),
                    visibleFrame: CGRect(x: 50, y: 40, width: 400, height: 300)
                )
            ]
        )

        XCTAssertEqual(
            engine.layout(
                model: rawRenderModel(),
                anchorRect: CGRect(x: 20, y: 60, width: 0, height: 18),
                screenProvider: screenProvider
            )?.panelOrigin,
            NSPoint(x: 58, y: 84)
        )
        XCTAssertEqual(
            engine.layout(
                model: rawRenderModel(),
                anchorRect: CGRect(x: 490, y: 390, width: 0, height: 18),
                screenProvider: screenProvider
            )?.panelOrigin,
            NSPoint(x: 222, y: 298)
        )
    }

    func testPlacementUsesValidatedScreenForCaretJustOutsideSecondaryDisplayFrame() {
        let engine = layoutEngine()
        let screenProvider = FakeCandidatePanelScreenProvider(
            screens: [
                CandidateAnchorScreen(
                    identifier: "main",
                    frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                    visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
                ),
                CandidateAnchorScreen(
                    identifier: "secondary",
                    frame: CGRect(x: 1_000, y: 0, width: 800, height: 600),
                    visibleFrame: CGRect(x: 1_000, y: 0, width: 800, height: 600)
                )
            ]
        )

        XCTAssertEqual(
            engine.layout(
                model: rawRenderModel(),
                anchorRect: CGRect(x: 999, y: 300, width: 0, height: 18),
                screenProvider: screenProvider
            )?.panelOrigin,
            NSPoint(x: 1_008, y: 260)
        )
    }

    @MainActor
    func testUpdateOrdersOutForVisibleStateWithNoUsableAnchor() {
        let contentView = FakeCandidatePanelContentRenderer()
        let window = FakeCandidatePanelWindow()
        var factoryCallCount = 0
        let controller = CandidatePanelWindowController(
            screenProvider: fakeScreenProvider(),
            contentView: contentView,
            layoutEngine: layoutEngine(),
            makePanel: { _ in
                factoryCallCount += 1
                return window
            }
        )

        controller.update(state: visibleState(anchor: .zero), locale: .enUS)

        let frontCount = window.orderFrontCount
        let outCount = window.orderOutCount
        let origins = window.frameOrigins

        XCTAssertEqual(factoryCallCount, 1)
        XCTAssertEqual(frontCount, 0)
        XCTAssertEqual(outCount, 1)
        XCTAssertEqual(origins, [])
        XCTAssertEqual(contentView.models, [])
    }

    @MainActor
    func testHiddenStateOrdersOutExistingWindow() {
        let contentView = FakeCandidatePanelContentRenderer()
        let window = FakeCandidatePanelWindow()
        var factoryCallCount = 0
        let controller = CandidatePanelWindowController(
            screenProvider: fakeScreenProvider(),
            contentView: contentView,
            layoutEngine: layoutEngine(),
            makePanel: { _ in
                factoryCallCount += 1
                return window
            }
        )

        controller.update(
            state: visibleState(anchor: CGRect(x: 100, y: 400, width: 0, height: 18)),
            locale: .mixed
        )
        controller.update(state: CandidatePanelState(), locale: .mixed)

        let frontCount = window.orderFrontCount
        let outCount = window.orderOutCount

        XCTAssertEqual(factoryCallCount, 1)
        XCTAssertEqual(frontCount, 1)
        XCTAssertEqual(outCount, 1)
    }

    @MainActor
    func testMatchingVisibleStateUsesFastPathWhileWindowIsOrderedVisible() {
        let contentView = FakeCandidatePanelContentRenderer()
        let window = FakeCandidatePanelWindow()
        let controller = CandidatePanelWindowController(
            screenProvider: fakeScreenProvider(),
            contentView: contentView,
            layoutEngine: layoutEngine(),
            makePanel: { _ in window }
        )
        let state = visibleState(anchor: CGRect(x: 100, y: 400, width: 0, height: 18))

        controller.update(state: state, locale: .zhCN)
        controller.update(state: state, locale: .zhCN)

        XCTAssertEqual(window.orderFrontCount, 2)
        XCTAssertEqual(window.orderOutCount, 0)
        XCTAssertEqual(window.contentSizes.count, 1)
        XCTAssertEqual(contentView.models.count, 1)
    }

    @MainActor
    func testLayoutFailureClearsPresentationCacheBeforeMatchingStateReturns() {
        let contentView = FakeCandidatePanelContentRenderer()
        let window = FakeCandidatePanelWindow()
        let screenProvider = MutableCandidatePanelScreenProvider(screens: fakeScreens())
        let controller = CandidatePanelWindowController(
            screenProvider: screenProvider,
            contentView: contentView,
            layoutEngine: layoutEngine(),
            makePanel: { _ in window }
        )
        let state = visibleState(anchor: CGRect(x: 100, y: 400, width: 0, height: 18))

        controller.update(state: state, locale: .zhCN)
        screenProvider.screens = []
        controller.update(state: state, locale: .zhCN)
        screenProvider.screens = fakeScreens()
        controller.update(state: state, locale: .zhCN)

        XCTAssertEqual(window.orderFrontCount, 2)
        XCTAssertEqual(window.orderOutCount, 1)
        XCTAssertEqual(window.contentSizes.count, 2)
        XCTAssertEqual(contentView.models.count, 2)
    }

    @MainActor
    func testHiddenStateClearsPresentationCacheBeforeMatchingStateReturns() {
        let contentView = FakeCandidatePanelContentRenderer()
        let window = FakeCandidatePanelWindow()
        let controller = CandidatePanelWindowController(
            screenProvider: fakeScreenProvider(),
            contentView: contentView,
            layoutEngine: layoutEngine(),
            makePanel: { _ in window }
        )
        let state = visibleState(anchor: CGRect(x: 100, y: 400, width: 0, height: 18))

        controller.update(state: state, locale: .zhCN)
        controller.update(state: CandidatePanelState(), locale: .zhCN)
        controller.update(state: state, locale: .zhCN)

        XCTAssertEqual(window.orderFrontCount, 2)
        XCTAssertEqual(window.orderOutCount, 1)
        XCTAssertEqual(window.contentSizes.count, 2)
        XCTAssertEqual(contentView.models.count, 2)
    }

    @MainActor
    func testStaleVisibleFrameAfterHiddenFrameDoesNotReopenPanel() {
        let contentView = FakeCandidatePanelContentRenderer()
        let window = FakeCandidatePanelWindow()
        let controller = CandidatePanelWindowController(
            screenProvider: fakeScreenProvider(),
            contentView: contentView,
            layoutEngine: layoutEngine(),
            makePanel: { _ in window }
        )
        let visibleFrame = panelFrame(
            generation: 1,
            state: visibleState(anchor: CGRect(x: 100, y: 400, width: 0, height: 18))
        )
        let hiddenFrame = panelFrame(generation: 2, state: CandidatePanelState(), reason: .compositionEnded)

        controller.apply(frame: visibleFrame, locale: .zhCN)
        controller.apply(frame: hiddenFrame, locale: .zhCN)
        controller.apply(frame: visibleFrame, locale: .zhCN)

        XCTAssertEqual(window.orderFrontCount, 1)
        XCTAssertEqual(window.orderOutCount, 1)
        XCTAssertEqual(window.contentSizes.count, 1)
        XCTAssertEqual(contentView.models.count, 1)
    }

    @MainActor
    func testNewVisibleFrameAfterHiddenFrameCanReopenPanel() {
        let contentView = FakeCandidatePanelContentRenderer()
        let window = FakeCandidatePanelWindow()
        let controller = CandidatePanelWindowController(
            screenProvider: fakeScreenProvider(),
            contentView: contentView,
            layoutEngine: layoutEngine(),
            makePanel: { _ in window }
        )
        let visibleState = visibleState(anchor: CGRect(x: 100, y: 400, width: 0, height: 18))

        controller.apply(frame: panelFrame(generation: 1, state: visibleState), locale: .zhCN)
        controller.apply(
            frame: panelFrame(generation: 2, state: CandidatePanelState(), reason: .compositionEnded),
            locale: .zhCN
        )
        controller.apply(frame: panelFrame(generation: 3, state: visibleState), locale: .zhCN)

        XCTAssertEqual(window.orderFrontCount, 2)
        XCTAssertEqual(window.orderOutCount, 1)
        XCTAssertEqual(window.contentSizes.count, 2)
        XCTAssertEqual(contentView.models.count, 2)
    }

    @MainActor
    func testSameGenerationVisibleFrameUsesFastPathWhilePanelIsVisible() {
        let contentView = FakeCandidatePanelContentRenderer()
        let window = FakeCandidatePanelWindow()
        let controller = CandidatePanelWindowController(
            screenProvider: fakeScreenProvider(),
            contentView: contentView,
            layoutEngine: layoutEngine(),
            makePanel: { _ in window }
        )
        let visibleFrame = panelFrame(
            generation: 1,
            state: visibleState(anchor: CGRect(x: 100, y: 400, width: 0, height: 18))
        )

        controller.apply(frame: visibleFrame, locale: .zhCN)
        controller.apply(frame: visibleFrame, locale: .zhCN)

        XCTAssertEqual(window.orderFrontCount, 2)
        XCTAssertEqual(window.orderOutCount, 0)
        XCTAssertEqual(window.contentSizes.count, 1)
        XCTAssertEqual(contentView.models.count, 1)
    }

    @MainActor
    func testLongCandidatesUseMeasuredVerticalLayoutBeforePlacement() {
        let contentView = FakeCandidatePanelContentRenderer()
        let window = FakeCandidatePanelWindow()
        let screenProvider = FakeCandidatePanelScreenProvider(
            screens: [
                CandidateAnchorScreen(
                    identifier: "main",
                    frame: CGRect(x: 0, y: 0, width: 700, height: 400),
                    visibleFrame: CGRect(x: 0, y: 0, width: 700, height: 400)
                )
            ]
        )
        let controller = CandidatePanelWindowController(
            screenProvider: screenProvider,
            contentView: contentView,
            layoutEngine: layoutEngine(defaultTextWidth: 250),
            makePanel: { _ in window }
        )

        controller.update(
            state: visibleState(
                anchor: CGRect(x: 650, y: 200, width: 0, height: 18),
                prefixTexts: [
                    "候选一很长",
                    "候选二很长",
                    "候选三很长",
                    "候选四很长",
                    "候选五很长",
                    "候选六很长"
                ]
            ),
            locale: .zhCN
        )

        let contentSizes = window.contentSizes
        let origins = window.frameOrigins
        let layoutPlans = contentView.layoutPlans

        XCTAssertEqual(contentSizes, [NSSize(width: 285, height: 174)])
        XCTAssertEqual(origins, [NSPoint(x: 407, y: 20)])
        XCTAssertEqual(layoutPlans.map(\.orientation), [.vertical])
        XCTAssertEqual(layoutPlans.first?.items.map(\.isTruncated), Array(repeating: false, count: 6))
    }

    @MainActor
    func testPagedStateLayoutsOnlyCurrentVisibleRows() {
        let contentView = FakeCandidatePanelContentRenderer()
        let window = FakeCandidatePanelWindow()
        let controller = CandidatePanelWindowController(
            screenProvider: fakeScreenProvider(),
            contentView: contentView,
            layoutEngine: layoutEngine(defaultTextWidth: 32),
            makePanel: { _ in window }
        )
        let candidates = (1...9).map { "候选\($0)" }

        controller.update(
            state: visibleState(
                anchor: CGRect(x: 100, y: 400, width: 0, height: 18),
                prefixTexts: candidates,
                paging: CandidatePanelPagingState(currentPage: 1, pageSize: 4)
            ),
            locale: .zhCN
        )

        XCTAssertEqual(contentView.models.first?.rows.map(\.text), Array(candidates[4..<8]))
        XCTAssertEqual(contentView.layoutPlans.first?.items.count, 4)
        XCTAssertEqual(contentView.layoutPlans.first?.orientation, .horizontal)
    }

    @MainActor
    func testAdaptivePagedStateUsesSixVisibleRowsAndKeepsShortCandidatesHorizontal() {
        let contentView = FakeCandidatePanelContentRenderer()
        let window = FakeCandidatePanelWindow()
        let controller = CandidatePanelWindowController(
            screenProvider: fakeScreenProvider(),
            contentView: contentView,
            layoutEngine: layoutEngine(defaultTextWidth: 32),
            makePanel: { _ in window }
        )
        let candidates = (1...9).map { "候选\($0)" }

        controller.update(
            state: visibleState(
                anchor: CGRect(x: 100, y: 400, width: 0, height: 18),
                prefixTexts: candidates,
                paging: CandidatePanelPagingState(pageSize: 6),
                layoutMode: .adaptive
            ),
            locale: .zhCN
        )

        XCTAssertEqual(contentView.models.first?.rows.map(\.text), Array(candidates[0..<6]))
        XCTAssertEqual(contentView.layoutPlans.first?.items.count, 6)
        XCTAssertEqual(contentView.layoutPlans.first?.orientation, .horizontal)
    }

    @MainActor
    func testVerticalPreferredPagedStateKeepsNineRowsVertical() {
        let contentView = FakeCandidatePanelContentRenderer()
        let window = FakeCandidatePanelWindow()
        let controller = CandidatePanelWindowController(
            screenProvider: fakeScreenProvider(),
            contentView: contentView,
            layoutEngine: layoutEngine(defaultTextWidth: 32),
            makePanel: { _ in window }
        )
        let candidates = (1...9).map { "候选\($0)" }

        controller.update(
            state: visibleState(
                anchor: CGRect(x: 100, y: 400, width: 0, height: 18),
                prefixTexts: candidates,
                paging: CandidatePanelPagingState(pageSize: 9),
                layoutMode: .verticalPreferred
            ),
            locale: .zhCN
        )

        XCTAssertEqual(contentView.models.first?.rows.map(\.text), candidates)
        XCTAssertEqual(contentView.layoutPlans.first?.items.count, 9)
        XCTAssertEqual(contentView.layoutPlans.first?.orientation, .vertical)
    }

    @MainActor
    func testWindowResizesBeforeContentViewLaysOutMeasuredRows() {
        let operationLog = CandidatePanelWindowOperationLog()
        let contentView = FakeCandidatePanelContentRenderer(operationLog: operationLog)
        let window = FakeCandidatePanelWindow(operationLog: operationLog)
        let controller = CandidatePanelWindowController(
            screenProvider: fakeScreenProvider(),
            contentView: contentView,
            layoutEngine: layoutEngine(defaultTextWidth: 120),
            makePanel: { _ in window }
        )

        controller.update(
            state: visibleState(
                anchor: CGRect(x: 100, y: 400, width: 0, height: 18),
                prefixTexts: ["候选1", "候选2", "候选3", "候选4"]
            ),
            locale: .zhCN
        )

        XCTAssertEqual(operationLog.events, ["setContentSize", "setFrameOrigin", "contentUpdate", "orderFront"])
    }

    @MainActor
    func testContentInteractionsForwardToDelegate() {
        let contentView = FakeCandidatePanelContentRenderer()
        let window = FakeCandidatePanelWindow()
        let interactionHandler = FakeCandidatePanelInteractionHandler()
        let controller = CandidatePanelWindowController(
            screenProvider: fakeScreenProvider(),
            contentView: contentView,
            layoutEngine: layoutEngine(),
            makePanel: { _ in window },
            interactionHandler: interactionHandler
        )

        contentView.interactionHandler?.candidatePanelContentDidHover(.prefixCandidate(1))
        contentView.interactionHandler?.candidatePanelContentDidCommit(.aiRecommendation)
        contentView.interactionHandler?.candidatePanelContentDidScroll(.pageDown)

        XCTAssertEqual(interactionHandler.hoveredSelections, [.prefixCandidate(1)])
        XCTAssertEqual(interactionHandler.committedSelections, [.aiRecommendation])
        XCTAssertEqual(interactionHandler.scrollNavigations, [.pageDown])
        XCTAssertNotNil(controller)
    }

    private func fakeScreenProvider() -> FakeCandidatePanelScreenProvider {
        FakeCandidatePanelScreenProvider(screens: fakeScreens())
    }

    private func fakeScreens() -> [CandidateAnchorScreen] {
        [
            CandidateAnchorScreen(
                identifier: "main",
                frame: CGRect(x: 0, y: 0, width: 800, height: 800),
                visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 760)
            )
        ]
    }

    private func visibleState(
        anchor: CGRect,
        prefixTexts: [String] = [],
        paging: CandidatePanelPagingState = CandidatePanelPagingState(),
        layoutMode: CandidatePanelLayoutMode = .adaptive,
        placementPreference: CandidatePanelPlacementPreference = .automatic
    ) -> CandidatePanelState {
        CandidatePanelState(
            windowState: CandidatePanelWindowState(
                isVisible: true,
                anchorRect: anchor,
                viewModel: CandidatePanelViewModel(
                    rawInput: "candidate",
                    prefixCandidates: prefixTexts.map {
                        CorrectionCandidate(
                            text: $0,
                            source: "test",
                            confidence: 1,
                            correctionLevel: .light
                        )
                    },
                    continuationCandidates: []
                ),
                paging: paging,
                layoutMode: layoutMode,
                placementPreference: placementPreference
            )
        )
    }

    private func rawRenderModel() -> CandidatePanelRenderModel {
        CandidatePanelRenderModel(
            title: "KnowType",
            previewText: nil,
            rows: [
                CandidatePanelRenderRow(
                    kind: .rawInput,
                    shortcutLabel: nil,
                    text: "candidate",
                    isSelected: false,
                    visualRole: .rawInput
                )
            ]
        )
    }

    private func panelFrame(
        generation: Int,
        state: CandidatePanelState,
        reason: CandidatePanelVisibilityReason = .compositionActive
    ) -> CandidatePanelFrame {
        CandidatePanelFrame(
            presentationGeneration: generation,
            compositionID: 1,
            rawRevision: 1,
            rawLength: state.windowState.viewModel.rawInput.count,
            panelModel: state,
            anchorSource: state.windowState.anchorSource,
            visibilityReason: reason
        )
    }

    private func layoutEngine(defaultTextWidth: CGFloat = 60) -> CandidatePanelLayoutEngine {
        CandidatePanelLayoutEngine(
            textMeasurer: WindowControllerCandidatePanelTextMeasurer(defaultTextWidth: defaultTextWidth)
        )
    }
}

private struct FakeCandidatePanelScreenProvider: ScreenGeometryProviding {
    var screens: [CandidateAnchorScreen]
}

private final class MutableCandidatePanelScreenProvider: ScreenGeometryProviding {
    var screens: [CandidateAnchorScreen]

    init(screens: [CandidateAnchorScreen]) {
        self.screens = screens
    }
}

@MainActor
private final class FakeCandidatePanelContentRenderer: CandidatePanelContentRendering {
    let appKitView = NSView()
    weak var interactionHandler: CandidatePanelContentInteractionHandling?
    private(set) var models: [CandidatePanelRenderModel] = []
    private(set) var layoutPlans: [CandidatePanelLayoutPlan] = []
    private let operationLog: CandidatePanelWindowOperationLog?

    init(operationLog: CandidatePanelWindowOperationLog? = nil) {
        self.operationLog = operationLog
    }

    func update(model: CandidatePanelRenderModel, layoutPlan: CandidatePanelLayoutPlan) {
        operationLog?.events.append("contentUpdate")
        models.append(model)
        layoutPlans.append(layoutPlan)
    }
}

private struct WindowControllerCandidatePanelTextMeasurer: CandidatePanelTextMeasuring {
    var defaultTextWidth: CGFloat
    var defaultShortcutWidth: CGFloat = 10

    func textWidth(for row: CandidatePanelRenderRow) -> CGFloat {
        defaultTextWidth
    }

    func shortcutWidth(for label: String) -> CGFloat {
        defaultShortcutWidth
    }
}

@MainActor
private final class FakeCandidatePanelWindow: CandidatePanelWindowOperating {
    private(set) var contentSizes: [NSSize] = []
    private(set) var frameOrigins: [NSPoint] = []
    private(set) var orderFrontCount = 0
    private(set) var orderOutCount = 0
    private let operationLog: CandidatePanelWindowOperationLog?

    init(operationLog: CandidatePanelWindowOperationLog? = nil) {
        self.operationLog = operationLog
    }

    func setContentSize(_ size: NSSize) {
        operationLog?.events.append("setContentSize")
        contentSizes.append(size)
    }

    func setFrameOrigin(_ point: NSPoint) {
        operationLog?.events.append("setFrameOrigin")
        frameOrigins.append(point)
    }

    func orderFrontRegardless() {
        operationLog?.events.append("orderFront")
        orderFrontCount += 1
    }

    func orderOut(_ sender: Any?) {
        operationLog?.events.append("orderOut")
        orderOutCount += 1
    }
}

private final class CandidatePanelWindowOperationLog {
    var events: [String] = []
}

private extension NSView {
    func allDescendants() -> [NSView] {
        subviews + subviews.flatMap { $0.allDescendants() }
    }
}

private final class FakeCandidatePanelInteractionHandler: CandidatePanelInteractionHandling {
    private(set) var hoveredSelections: [CandidatePanelSelection] = []
    private(set) var committedSelections: [CandidatePanelSelection] = []
    private(set) var scrollNavigations: [InputCandidateNavigation] = []

    func candidatePanelDidHover(_ selection: CandidatePanelSelection) {
        hoveredSelections.append(selection)
    }

    func candidatePanelDidCommit(_ selection: CandidatePanelSelection) {
        committedSelections.append(selection)
    }

    func candidatePanelDidScroll(_ navigation: InputCandidateNavigation) {
        scrollNavigations.append(navigation)
    }
}
#endif
