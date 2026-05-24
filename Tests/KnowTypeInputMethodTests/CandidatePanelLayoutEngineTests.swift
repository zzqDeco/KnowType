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
        XCTAssertEqual(plan?.panelSize.width, 362)
        XCTAssertEqual(plan?.panelSize.height, 34)
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
        XCTAssertEqual(plan?.panelSize.width, 596)
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
        XCTAssertEqual(plan?.panelSize.width, 285)
        XCTAssertEqual(plan?.panelSize.height, 174)
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
            screenProvider: screenProvider(width: 800, height: 210)
        )

        XCTAssertEqual(plan?.orientation, .vertical)
        XCTAssertEqual(plan?.items.count, 9)
        XCTAssertEqual(plan?.items.map(\.rowIndex), Array(0..<9))
        XCTAssertEqual(plan?.items.first?.frame.height, 20)
        XCTAssertEqual(plan?.itemSpacing, 0.75)
        XCTAssertLessThanOrEqual(plan?.panelSize.height ?? .infinity, 194)
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
        XCTAssertEqual(plan?.items.first?.textWidthLimit, 525)
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
        XCTAssertEqual(topRight?.panelOrigin, CGPoint(x: 198, y: 298))
    }

    func testHorizontalLayoutUsesMeasuredShortcutWidthWithoutReservedSlot() {
        let engine = engine(defaultTextWidth: 32, defaultShortcutWidth: 8)

        let plan = engine.layout(
            model: renderModel(rowCount: 4),
            anchorRect: CGRect(x: 100, y: 400, width: 0, height: 18),
            screenProvider: screenProvider()
        )

        XCTAssertEqual(plan?.orientation, .horizontal)
        XCTAssertEqual(plan?.items.first?.frame.width, 55)
        XCTAssertEqual(plan?.items.first?.shortcutLabelWidth, 8)
        XCTAssertEqual(plan?.items.first?.textWidthLimit, 32)
    }

    func testRowsWithoutShortcutDoNotReserveShortcutSlot() {
        let engine = engine(defaultTextWidth: 32, defaultShortcutWidth: 8)
        let shortcutLabels: [String?] = [nil, nil, nil, nil]

        let plan = engine.layout(
            model: renderModel(shortcutLabels: shortcutLabels),
            anchorRect: CGRect(x: 100, y: 400, width: 0, height: 18),
            screenProvider: screenProvider()
        )

        XCTAssertEqual(plan?.orientation, .horizontal)
        XCTAssertEqual(plan?.items.first?.frame.width, 44)
        XCTAssertEqual(plan?.items.first?.shortcutLabelWidth, 0)
        XCTAssertEqual(plan?.items.first?.textWidthLimit, 32)
    }

    func testVerticalLayoutAlignsOnlyRowsWithShortcutToPageMaxShortcutWidth() {
        let engine = CandidatePanelLayoutEngine(
            configuration: CandidatePanelLayoutConfiguration(layoutMode: .verticalPreferred),
            textMeasurer: FixedCandidatePanelTextMeasurer(
                defaultTextWidth: 40,
                defaultShortcutWidth: 8,
                shortcutWidths: [
                    "1": 8,
                    "10": 16
                ]
            )
        )

        let plan = engine.layout(
            model: renderModel(shortcutLabels: ["1", nil, "10"]),
            anchorRect: CGRect(x: 100, y: 400, width: 0, height: 18),
            screenProvider: screenProvider()
        )

        XCTAssertEqual(plan?.orientation, .vertical)
        XCTAssertEqual(plan?.items.map(\.shortcutLabelWidth), [16, 0, 16])
        XCTAssertEqual(plan?.items.map(\.textWidthLimit), [179, 198, 179])
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

    private func engine(defaultTextWidth: CGFloat, defaultShortcutWidth: CGFloat = 10) -> CandidatePanelLayoutEngine {
        CandidatePanelLayoutEngine(
            textMeasurer: FixedCandidatePanelTextMeasurer(
                defaultTextWidth: defaultTextWidth,
                defaultShortcutWidth: defaultShortcutWidth
            )
        )
    }

    private func renderModel(rowCount: Int) -> CandidatePanelRenderModel {
        renderModel(shortcutLabels: (1...rowCount).map { "\($0)" })
    }

    private func renderModel(shortcutLabels: [String?]) -> CandidatePanelRenderModel {
        CandidatePanelRenderModel(
            title: "KnowType",
            previewText: nil,
            rows: shortcutLabels.enumerated().map { index, shortcutLabel in
                CandidatePanelRenderRow(
                    kind: .prefixCandidate,
                    shortcutLabel: shortcutLabel,
                    text: "candidate-\(index + 1)",
                    isSelected: index == 0,
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
    var shortcutWidths: [String: CGFloat] = [:]

    func textWidth(for row: CandidatePanelRenderRow) -> CGFloat {
        defaultTextWidth
    }

    func shortcutWidth(for label: String) -> CGFloat {
        shortcutWidths[label] ?? defaultShortcutWidth
    }
}

private struct LayoutEngineScreenProvider: ScreenGeometryProviding {
    var screens: [CandidateAnchorScreen]
}
