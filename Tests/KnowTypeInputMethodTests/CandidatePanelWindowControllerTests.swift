#if canImport(AppKit)
import AppKit
import KnowTypeCore
import XCTest
@testable import KnowTypeInputMethod

final class CandidatePanelWindowControllerTests: XCTestCase {
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
                NSPoint(x: 100, y: 354),
                NSPoint(x: 160, y: 374)
            ]
        )
        XCTAssertEqual(contentSizes, [NSSize(width: 220, height: 40), NSSize(width: 220, height: 40)])
        XCTAssertEqual(frontCount, 2)
        XCTAssertEqual(outCount, 0)
        XCTAssertEqual(modelCount, 2)
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
            NSPoint(x: 222, y: 292)
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
            NSPoint(x: 1_008, y: 254)
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

        XCTAssertEqual(contentSizes, [NSSize(width: 305, height: 205)])
        XCTAssertEqual(origins, [NSPoint(x: 387, y: 187)])
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

        XCTAssertEqual(operationLog.events, ["setContentSize", "contentUpdate", "setFrameOrigin", "orderFront"])
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
        FakeCandidatePanelScreenProvider(
            screens: [
                CandidateAnchorScreen(
                    identifier: "main",
                    frame: CGRect(x: 0, y: 0, width: 800, height: 800),
                    visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 760)
                )
            ]
        )
    }

    private func visibleState(
        anchor: CGRect,
        prefixTexts: [String] = [],
        paging: CandidatePanelPagingState = CandidatePanelPagingState(),
        layoutMode: CandidatePanelLayoutMode = .adaptive
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
                layoutMode: layoutMode
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

    private func layoutEngine(defaultTextWidth: CGFloat = 60) -> CandidatePanelLayoutEngine {
        CandidatePanelLayoutEngine(
            textMeasurer: WindowControllerCandidatePanelTextMeasurer(defaultTextWidth: defaultTextWidth)
        )
    }
}

private struct FakeCandidatePanelScreenProvider: ScreenGeometryProviding {
    var screens: [CandidateAnchorScreen]
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
