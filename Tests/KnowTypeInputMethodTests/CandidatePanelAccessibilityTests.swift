#if canImport(AppKit)
import AppKit
import XCTest
@testable import KnowTypeInputMethod

@MainActor
final class CandidatePanelAccessibilityTests: XCTestCase {
    func testRowsExposeAccessibilityLabelsRolesAndSelectedChildren() throws {
        let view = CandidatePanelContentView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 73),
            appearance: .snapshotLight
        )
        view.update(model: accessibilityModel(selectedIndex: 0), layoutPlan: verticalLayoutPlan())

        let children = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])
        let selectedChildren = try XCTUnwrap(view.accessibilitySelectedChildren() as? [NSAccessibilityElement])

        XCTAssertEqual(children.count, 3)
        XCTAssertEqual(children[0].accessibilityRole(), .button)
        XCTAssertEqual(children[0].accessibilityLabel(), "1，我觉得这个方案")
        XCTAssertTrue(children[0].isAccessibilityEnabled())
        XCTAssertTrue(children[0].isAccessibilitySelected())
        XCTAssertEqual(children[1].accessibilityRole(), .staticText)
        XCTAssertEqual(children[1].accessibilityLabel(), "AI 状态，AI 推荐中...")
        XCTAssertFalse(children[1].isAccessibilityEnabled())
        XCTAssertFalse(children[1].isAccessibilitySelected())
        XCTAssertEqual(children[2].accessibilityRole(), .button)
        XCTAssertEqual(children[2].accessibilityLabel(), "2，我觉得这套方案")
        XCTAssertTrue(children[2].isAccessibilityEnabled())
        XCTAssertFalse(children[2].isAccessibilitySelected())
        XCTAssertEqual(selectedChildren.count, 1)
        XCTAssertEqual(selectedChildren.first?.accessibilityLabel(), "1，我觉得这个方案")
    }

    func testSelectedAccessibilityChildFollowsUpdatedSelection() throws {
        let view = CandidatePanelContentView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 73),
            appearance: .snapshotLight
        )

        view.update(model: accessibilityModel(selectedIndex: 0), layoutPlan: verticalLayoutPlan())
        XCTAssertEqual(
            (view.accessibilitySelectedChildren() as? [NSAccessibilityElement])?.first?.accessibilityLabel(),
            "1，我觉得这个方案"
        )

        view.update(model: accessibilityModel(selectedIndex: 2), layoutPlan: verticalLayoutPlan())

        let selectedChildren = try XCTUnwrap(view.accessibilitySelectedChildren() as? [NSAccessibilityElement])
        XCTAssertEqual(selectedChildren.count, 1)
        XCTAssertEqual(selectedChildren.first?.accessibilityLabel(), "2，我觉得这套方案")
        XCTAssertTrue(selectedChildren.first?.isAccessibilitySelected() == true)
    }

    func testPreeditRowExposesStaticAccessibilityEvenWhenReadable() throws {
        let view = CandidatePanelContentView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 73),
            appearance: .snapshotLight
        )
        let model = CandidatePanelRenderModel(
            title: "KnowType",
            previewText: nil,
            rows: [
                CandidatePanelRenderRow(
                    kind: .preedit,
                    selection: nil,
                    shortcutLabel: nil,
                    text: "ni",
                    isSelected: false,
                    isEnabled: true,
                    visualRole: .rawInput,
                    accessibilityLabel: "预编辑，ni"
                ),
                CandidatePanelRenderRow(
                    kind: .prefixCandidate,
                    selection: .prefixCandidate(0),
                    shortcutLabel: "1",
                    text: "你",
                    isSelected: true,
                    visualRole: .lockedPrefix
                )
            ]
        )

        view.update(model: model, layoutPlan: verticalLayoutPlan())

        let children = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children[0].accessibilityRole(), .staticText)
        XCTAssertEqual(children[0].accessibilityLabel(), "预编辑，ni")
        XCTAssertFalse(children[0].isAccessibilityEnabled())
        XCTAssertFalse(children[0].isAccessibilitySelected())
        XCTAssertEqual(children[1].accessibilityRole(), .button)
        XCTAssertEqual(children[1].accessibilityLabel(), "1，你")
    }

    private func accessibilityModel(selectedIndex: Int) -> CandidatePanelRenderModel {
        CandidatePanelRenderModel(
            title: "KnowType",
            previewText: nil,
            rows: [
                CandidatePanelRenderRow(
                    kind: .prefixCandidate,
                    selection: .prefixCandidate(0),
                    shortcutLabel: "1",
                    text: "我觉得这个方案",
                    isSelected: selectedIndex == 0,
                    visualRole: .lockedPrefix
                ),
                CandidatePanelRenderRow(
                    kind: .aiRecommendation,
                    selection: nil,
                    shortcutLabel: nil,
                    text: "AI 推荐中...",
                    isSelected: false,
                    isEnabled: false,
                    visualRole: .aiRecommendation
                ),
                CandidatePanelRenderRow(
                    kind: .prefixCandidate,
                    selection: .prefixCandidate(1),
                    shortcutLabel: "2",
                    text: "我觉得这套方案",
                    isSelected: selectedIndex == 2,
                    visualRole: .lockedPrefix
                )
            ]
        )
    }

    private func verticalLayoutPlan() -> CandidatePanelLayoutPlan {
        CandidatePanelLayoutPlan(
            orientation: .vertical,
            verticalPlacement: .visualBelowCaret,
            panelSize: CGSize(width: 320, height: 73),
            panelOrigin: .zero,
            contentInsets: CandidatePanelLayoutInsets(top: 5, left: 6, bottom: 5, right: 6),
            itemSpacing: 3,
            items: [
                CandidatePanelLayoutItem(
                    rowIndex: 0,
                    frame: CGRect(x: 6, y: 5, width: 308, height: 19),
                    textWidthLimit: 260,
                    isTruncated: false
                ),
                CandidatePanelLayoutItem(
                    rowIndex: 1,
                    frame: CGRect(x: 6, y: 27, width: 308, height: 19),
                    textWidthLimit: 260,
                    isTruncated: false
                ),
                CandidatePanelLayoutItem(
                    rowIndex: 2,
                    frame: CGRect(x: 6, y: 49, width: 308, height: 19),
                    textWidthLimit: 260,
                    isTruncated: false
                )
            ]
        )
    }
}
#endif
