#if canImport(AppKit)
import AppKit
import KnowTypeCore
import XCTest
@testable import KnowTypeInputMethod

final class CandidatePanelWindowControllerTests: XCTestCase {
    @MainActor
    func testUpdateMovesExistingWindowWhenAnchorMoves() {
        let contentView = FakeCandidatePanelContentRenderer(fittingSize: NSSize(width: 220, height: 36))
        let window = FakeCandidatePanelWindow()
        let screenProvider = fakeScreenProvider()
        var factoryCallCount = 0
        var factoryContentViews: [NSView] = []
        let controller = CandidatePanelWindowController(
            screenProvider: screenProvider,
            contentView: contentView,
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
        let frontCount = window.orderFrontCount
        let outCount = window.orderOutCount
        let modelCount = contentView.models.count
        let factoryUsedContentView = factoryContentViews.first === contentView.appKitView

        XCTAssertEqual(factoryCallCount, 1)
        XCTAssertTrue(factoryUsedContentView)
        XCTAssertEqual(
            origins,
            [
                NSPoint(x: 100, y: 358),
                NSPoint(x: 160, y: 378)
            ]
        )
        XCTAssertEqual(frontCount, 2)
        XCTAssertEqual(outCount, 0)
        XCTAssertEqual(modelCount, 2)
    }

    func testPlacementAvoidsVisibleFrameEdges() {
        let screenProvider = FakeCandidatePanelScreenProvider(
            screens: [
                CandidateAnchorScreen(
                    identifier: "main",
                    frame: CGRect(x: 0, y: 0, width: 500, height: 500),
                    visibleFrame: CGRect(x: 50, y: 40, width: 400, height: 300)
                )
            ]
        )
        let contentSize = NSSize(width: 240, height: 36)

        XCTAssertEqual(
            CandidatePanelWindowPlacement.origin(
                for: CGRect(x: 20, y: 60, width: 0, height: 18),
                contentSize: contentSize,
                screenProvider: screenProvider
            ),
            NSPoint(x: 58, y: 84)
        )
        XCTAssertEqual(
            CandidatePanelWindowPlacement.origin(
                for: CGRect(x: 490, y: 390, width: 0, height: 18),
                contentSize: contentSize,
                screenProvider: screenProvider
            ),
            NSPoint(x: 202, y: 296)
        )
    }

    @MainActor
    func testUpdateOrdersOutForVisibleStateWithNoUsableAnchor() {
        let contentView = FakeCandidatePanelContentRenderer(fittingSize: NSSize(width: 220, height: 36))
        let window = FakeCandidatePanelWindow()
        var factoryCallCount = 0
        let controller = CandidatePanelWindowController(
            screenProvider: fakeScreenProvider(),
            contentView: contentView,
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
    }

    @MainActor
    func testHiddenStateOrdersOutExistingWindow() {
        let contentView = FakeCandidatePanelContentRenderer(fittingSize: NSSize(width: 220, height: 36))
        let window = FakeCandidatePanelWindow()
        var factoryCallCount = 0
        let controller = CandidatePanelWindowController(
            screenProvider: fakeScreenProvider(),
            contentView: contentView,
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
    func testLongCandidateContentSizeIsConstrainedBeforePlacement() {
        let contentView = FakeCandidatePanelContentRenderer(fittingSize: NSSize(width: 900, height: 80))
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
            makePanel: { _ in window }
        )

        controller.update(
            state: visibleState(anchor: CGRect(x: 650, y: 200, width: 0, height: 18)),
            locale: .zhCN
        )

        let contentSizes = window.contentSizes
        let origins = window.frameOrigins

        XCTAssertEqual(contentSizes, [CandidatePanelWindowSizing.maximumSize])
        XCTAssertEqual(origins, [NSPoint(x: 132, y: 150)])
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

    private func visibleState(anchor: CGRect) -> CandidatePanelState {
        CandidatePanelState(
            windowState: CandidatePanelWindowState(
                isVisible: true,
                anchorRect: anchor,
                viewModel: CandidatePanelViewModel(
                    rawInput: "candidate",
                    prefixCandidates: [],
                    continuationCandidates: []
                )
            )
        )
    }
}

private struct FakeCandidatePanelScreenProvider: ScreenGeometryProviding {
    var screens: [CandidateAnchorScreen]
}

@MainActor
private final class FakeCandidatePanelContentRenderer: CandidatePanelContentRendering {
    let appKitView = NSView()
    var fittingSize: NSSize
    private(set) var models: [CandidatePanelRenderModel] = []

    init(fittingSize: NSSize) {
        self.fittingSize = fittingSize
    }

    func update(model: CandidatePanelRenderModel) {
        models.append(model)
    }
}

@MainActor
private final class FakeCandidatePanelWindow: CandidatePanelWindowOperating {
    private(set) var contentSizes: [NSSize] = []
    private(set) var frameOrigins: [NSPoint] = []
    private(set) var orderFrontCount = 0
    private(set) var orderOutCount = 0

    func setContentSize(_ size: NSSize) {
        contentSizes.append(size)
    }

    func setFrameOrigin(_ point: NSPoint) {
        frameOrigins.append(point)
    }

    func orderFrontRegardless() {
        orderFrontCount += 1
    }

    func orderOut(_ sender: Any?) {
        orderOutCount += 1
    }
}
#endif
