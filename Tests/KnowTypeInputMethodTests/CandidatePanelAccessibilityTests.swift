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
        XCTAssertEqual(children[1].accessibilityLabel(), "AI 状态，AI 推荐中")
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

    func testCommitOnlySymbolPreviewAndSelectionAreVoiceOverReadable() throws {
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
                    text: "/",
                    isSelected: false,
                    isEnabled: false,
                    visualRole: .rawInput,
                    accessibilityLabel: "预编辑，/"
                ),
                CandidatePanelRenderRow(
                    kind: .symbolCandidate,
                    selection: .symbolCandidate(0),
                    shortcutLabel: "1",
                    text: "、",
                    isSelected: false,
                    visualRole: .symbolCandidate,
                    accessibilityLabel: "符号，1，、"
                ),
                CandidatePanelRenderRow(
                    kind: .symbolCandidate,
                    selection: .symbolCandidate(1),
                    shortcutLabel: "2",
                    text: "/",
                    isSelected: true,
                    visualRole: .symbolCandidate,
                    accessibilityLabel: "符号，2，/"
                )
            ]
        )

        view.update(model: model, layoutPlan: verticalLayoutPlan())

        let children = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])
        let selected = try XCTUnwrap(view.accessibilitySelectedChildren() as? [NSAccessibilityElement])
        XCTAssertEqual(children.map { $0.accessibilityLabel() }, ["预编辑，/", "符号，1，、", "符号，2，/"])
        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(selected.first?.accessibilityLabel(), "符号，2，/")
        XCTAssertTrue(children[2].isAccessibilitySelected())
    }

    func testEnabledAccessibilityPressCommitsExactSelection() throws {
        let view = CandidatePanelContentView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 73),
            appearance: .snapshotLight
        )
        let interactionHandler = AccessibilityInteractionRecorder()
        view.interactionHandler = interactionHandler
        view.update(model: accessibilityModel(selectedIndex: 0), layoutPlan: verticalLayoutPlan())

        let children = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])

        XCTAssertTrue(children[2].accessibilityPerformPress())
        XCTAssertEqual(interactionHandler.committedSelections, [.prefixCandidate(1)])
    }

    func testStaleAccessibilityRowDoesNotCommitReusedSelectionIndex() throws {
        let view = CandidatePanelContentView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 73),
            appearance: .snapshotLight
        )
        let interactionHandler = AccessibilityInteractionRecorder()
        view.interactionHandler = interactionHandler
        view.update(model: accessibilityModel(selectedIndex: 0), layoutPlan: verticalLayoutPlan())
        let staleChildren = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])
        let staleRow = staleChildren[2]
        XCTAssertEqual(staleRow.accessibilityLabel(), "2，我觉得这套方案")

        view.update(
            model: accessibilityModel(
                selectedIndex: 0,
                firstText: "新的第一项",
                secondText: "新的第二项"
            ),
            layoutPlan: verticalLayoutPlan()
        )
        let freshChildren = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])
        let freshRow = freshChildren[2]

        XCTAssertFalse(staleRow.accessibilityPerformPress())
        XCTAssertTrue(interactionHandler.committedSelections.isEmpty)
        XCTAssertEqual(freshRow.accessibilityLabel(), "2，新的第二项")
        XCTAssertTrue(freshRow.accessibilityPerformPress())
        XCTAssertEqual(interactionHandler.committedSelections, [.prefixCandidate(1)])
    }

    func testDisabledAccessibilityRowDoesNotPress() throws {
        let view = CandidatePanelContentView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 73),
            appearance: .snapshotLight
        )
        let interactionHandler = AccessibilityInteractionRecorder()
        view.interactionHandler = interactionHandler
        view.update(model: accessibilityModel(selectedIndex: 0), layoutPlan: verticalLayoutPlan())

        let children = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])

        XCTAssertFalse(children[1].accessibilityPerformPress())
        XCTAssertTrue(interactionHandler.committedSelections.isEmpty)
    }

    private func accessibilityModel(
        selectedIndex: Int,
        firstText: String = "我觉得这个方案",
        secondText: String = "我觉得这套方案"
    ) -> CandidatePanelRenderModel {
        CandidatePanelRenderModel(
            title: "KnowType",
            previewText: nil,
            rows: [
                CandidatePanelRenderRow(
                    kind: .prefixCandidate,
                    selection: .prefixCandidate(0),
                    shortcutLabel: "1",
                    text: firstText,
                    isSelected: selectedIndex == 0,
                    visualRole: .lockedPrefix
                ),
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
                ),
                CandidatePanelRenderRow(
                    kind: .prefixCandidate,
                    selection: .prefixCandidate(1),
                    shortcutLabel: "2",
                    text: secondText,
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

@MainActor
private final class AccessibilityInteractionRecorder: CandidatePanelContentInteractionHandling {
    private(set) var committedSelections: [CandidatePanelSelection] = []

    func candidatePanelContentDidHover(_ selection: CandidatePanelSelection) {}

    func candidatePanelContentDidCommit(_ selection: CandidatePanelSelection) {
        committedSelections.append(selection)
    }

    func candidatePanelContentDidScroll(_ navigation: InputCandidateNavigation) {}
}
#endif
