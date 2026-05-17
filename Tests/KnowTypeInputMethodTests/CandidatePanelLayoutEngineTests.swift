import CoreGraphics
import KnowTypeCore
import XCTest
@testable import KnowTypeInputMethod

final class CandidatePanelLayoutEngineTests: XCTestCase {
    func testSixShortCandidatesUseHorizontalLayout() {
        let engine = engine(defaultTextWidth: 32)

        let plan = engine.layout(
            model: renderModel(rowCount: 6),
            anchorRect: CGRect(x: 100, y: 400, width: 0, height: 18),
            screenProvider: screenProvider()
        )

        XCTAssertEqual(plan?.orientation, .horizontal)
        XCTAssertEqual(plan?.items.count, 6)
        XCTAssertEqual(plan?.panelSize.width, 428)
        XCTAssertEqual(plan?.panelSize.height, 38)
        XCTAssertEqual(plan?.items.map(\.rowIndex), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(plan?.items.map(\.isTruncated), Array(repeating: false, count: 6))
    }

    func testFourMediumPhraseCandidatesStayHorizontalWhenTheyFit() {
        let engine = engine(defaultTextWidth: 120)

        let plan = engine.layout(
            model: renderModel(rowCount: 4),
            anchorRect: CGRect(x: 100, y: 400, width: 0, height: 18),
            screenProvider: screenProvider(width: 1_000)
        )

        XCTAssertEqual(plan?.orientation, .horizontal)
        XCTAssertEqual(plan?.items.count, 4)
        XCTAssertEqual(plan?.panelSize.width, 640)
        XCTAssertEqual(plan?.items.map(\.isTruncated), Array(repeating: false, count: 4))
    }

    func testLongCandidatesSwitchToVerticalWhenFourCannotFit() {
        let engine = engine(defaultTextWidth: 250)

        let plan = engine.layout(
            model: renderModel(rowCount: 6),
            anchorRect: CGRect(x: 100, y: 400, width: 0, height: 18),
            screenProvider: screenProvider()
        )

        XCTAssertEqual(plan?.orientation, .vertical)
        XCTAssertEqual(plan?.panelSize.width, 296)
        XCTAssertEqual(plan?.panelSize.height, 186)
        XCTAssertEqual(plan?.items.map(\.isTruncated), Array(repeating: false, count: 6))
    }

    func testMoreThanSixRowsUseVerticalLayoutWithoutDroppingCandidates() {
        let engine = engine(defaultTextWidth: 32)

        let plan = engine.layout(
            model: renderModel(rowCount: 9),
            anchorRect: CGRect(x: 100, y: 400, width: 0, height: 18),
            screenProvider: screenProvider()
        )

        XCTAssertEqual(plan?.orientation, .vertical)
        XCTAssertEqual(plan?.items.count, 9)
        XCTAssertEqual(plan?.items.map(\.rowIndex), Array(0..<9))
    }

    func testVerticalLayoutCompressesRowsToVisibleFrameHeightWithoutDroppingCandidates() {
        let engine = engine(defaultTextWidth: 32)

        let plan = engine.layout(
            model: renderModel(rowCount: 9),
            anchorRect: CGRect(x: 100, y: 120, width: 0, height: 18),
            screenProvider: screenProvider(width: 800, height: 200)
        )

        XCTAssertEqual(plan?.orientation, .vertical)
        XCTAssertEqual(plan?.items.count, 9)
        XCTAssertEqual(plan?.items.map(\.rowIndex), Array(0..<9))
        XCTAssertEqual(plan?.items.first?.frame.height, 18)
        XCTAssertEqual(plan?.itemSpacing, 1.75)
        XCTAssertLessThanOrEqual(plan?.panelSize.height ?? .infinity, 184)
    }

    func testLayoutReturnsNilWhenVisibleFrameCannotFitOneRow() {
        let engine = engine(defaultTextWidth: 32)

        let plan = engine.layout(
            model: renderModel(rowCount: 6),
            anchorRect: CGRect(x: 100, y: 20, width: 0, height: 18),
            screenProvider: screenProvider(width: 800, height: 30)
        )

        XCTAssertNil(plan)
    }

    func testVerticalLayoutTruncatesOnlyAfterMaximumWidth() {
        let engine = engine(defaultTextWidth: 900)

        let plan = engine.layout(
            model: renderModel(rowCount: 6),
            anchorRect: CGRect(x: 100, y: 400, width: 0, height: 18),
            screenProvider: screenProvider()
        )

        XCTAssertEqual(plan?.orientation, .vertical)
        XCTAssertEqual(plan?.panelSize.width, 560)
        XCTAssertEqual(plan?.items.map(\.isTruncated), Array(repeating: true, count: 6))
        XCTAssertEqual(plan?.items.first?.textWidthLimit, 514)
    }

    func testLayoutAvoidsVisibleFrameEdges() {
        let engine = engine(defaultTextWidth: 32)
        let provider = LayoutEngineScreenProvider(
            screens: [
                CandidateAnchorScreen(
                    identifier: "main",
                    frame: CGRect(x: 0, y: 0, width: 500, height: 500),
                    visibleFrame: CGRect(x: 50, y: 40, width: 400, height: 300)
                )
            ]
        )

        let bottomLeft = engine.layout(
            model: renderModel(rowCount: 4),
            anchorRect: CGRect(x: 20, y: 60, width: 0, height: 18),
            screenProvider: provider
        )
        let topRight = engine.layout(
            model: renderModel(rowCount: 4),
            anchorRect: CGRect(x: 490, y: 390, width: 0, height: 18),
            screenProvider: provider
        )

        XCTAssertEqual(bottomLeft?.panelOrigin, CGPoint(x: 58, y: 84))
        XCTAssertEqual(topRight?.panelOrigin, CGPoint(x: 154, y: 294))
    }

    func testLayoutReturnsNilForInvalidAnchor() {
        let engine = engine(defaultTextWidth: 32)

        let plan = engine.layout(
            model: renderModel(rowCount: 4),
            anchorRect: .zero,
            screenProvider: screenProvider()
        )

        XCTAssertNil(plan)
    }

    private func engine(defaultTextWidth: CGFloat) -> CandidatePanelLayoutEngine {
        CandidatePanelLayoutEngine(
            textMeasurer: FixedCandidatePanelTextMeasurer(defaultTextWidth: defaultTextWidth)
        )
    }

    private func renderModel(rowCount: Int) -> CandidatePanelRenderModel {
        CandidatePanelRenderModel(
            title: "KnowType",
            previewText: nil,
            rows: (1...rowCount).map { index in
                CandidatePanelRenderRow(
                    kind: .prefixCandidate,
                    shortcutLabel: "\(index)",
                    text: "candidate-\(index)",
                    isSelected: index == 1,
                    visualRole: .lockedPrefix
                )
            }
        )
    }

    private func screenProvider(width: CGFloat = 800, height: CGFloat = 760) -> LayoutEngineScreenProvider {
        LayoutEngineScreenProvider(
            screens: [
                CandidateAnchorScreen(
                    identifier: "main",
                    frame: CGRect(x: 0, y: 0, width: width, height: height),
                    visibleFrame: CGRect(x: 0, y: 0, width: width, height: height)
                )
            ]
        )
    }
}

private struct FixedCandidatePanelTextMeasurer: CandidatePanelTextMeasuring {
    var defaultTextWidth: CGFloat
    var defaultShortcutWidth: CGFloat = 10

    func textWidth(for row: CandidatePanelRenderRow) -> CGFloat {
        defaultTextWidth
    }

    func shortcutWidth(for label: String) -> CGFloat {
        defaultShortcutWidth
    }
}

private struct LayoutEngineScreenProvider: ScreenGeometryProviding {
    var screens: [CandidateAnchorScreen]
}
