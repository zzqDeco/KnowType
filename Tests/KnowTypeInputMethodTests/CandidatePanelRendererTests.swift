import XCTest
import KnowTypeAI
import KnowTypeCore
@testable import KnowTypeInputMethod

final class CandidatePanelRendererTests: XCTestCase {
    private let prefixCandidates = [
        CorrectionCandidate(
            text: "我觉得这个方案",
            source: "local",
            confidence: 1.0,
            correctionLevel: .contextual
        ),
        CorrectionCandidate(
            text: "我觉得这套方案",
            source: "local",
            confidence: 0.8,
            correctionLevel: .contextual
        )
    ]

    private let continuationCandidates = [
        ContinuationCandidate(
            text: "还有进一步优化空间",
            lengthLevel: .medium,
            confidence: 0.9,
            provider: "test"
        ),
        ContinuationCandidate(
            text: "在落地成本上可能偏高",
            lengthLevel: .medium,
            confidence: 0.8,
            provider: "test"
        )
    ]

    func testRendersChinesePanelAsCompactNativeStyleRowsWithoutHeadersOrPreview() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "wo jue de zhege fangan",
            prefixCandidates: prefixCandidates,
            continuationCandidates: continuationCandidates
        )

        let rendered = CandidatePanelRenderer(locale: .zhCN).render(viewModel)

        XCTAssertEqual(
            rendered.rows.map(\.kind),
            [
                .prefixCandidate,
                .prefixCandidate,
                .continuationCandidate,
                .continuationCandidate
            ]
        )
        XCTAssertNil(rendered.previewText)
        XCTAssertEqual(rendered.rows[0].visualRole, .lockedPrefix)
        XCTAssertEqual(rendered.rows[1].visualRole, .lockedPrefix)
        XCTAssertEqual(rendered.rows[2].visualRole, .continuation)
        XCTAssertEqual(rendered.rows[3].visualRole, .continuation)
        XCTAssertEqual(rendered.rows[0].shortcutLabel, "1")
        XCTAssertEqual(rendered.rows[1].shortcutLabel, "2")
        XCTAssertEqual(rendered.rows[2].shortcutLabel, "⇥")
        XCTAssertEqual(rendered.rows[3].shortcutLabel, "⌥2")
        XCTAssertEqual(rendered.rows.map(\.selection), [
            .prefixCandidate(0),
            .prefixCandidate(1),
            .continuationCandidate(0),
            .continuationCandidate(1)
        ])
        XCTAssertTrue(rendered.rows.allSatisfy(\.isEnabled))
    }

    func testAIRecommendationRendersWithoutTakingNumberShortcut() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "wo jue de zhege fangan",
            prefixCandidates: prefixCandidates,
            continuationCandidates: [],
            aiRecommendation: .ready(
                AIRecommendationCandidate(
                    prefixText: "我觉得这个方案",
                    continuationText: "需要先验证核心假设",
                    displayText: "我觉得这个方案需要先验证核心假设",
                    confidence: 0.9,
                    provider: "test",
                    contextVersion: "v1"
                )
            )
        )

        let rendered = CandidatePanelRenderer(locale: .zhCN).render(viewModel)

        XCTAssertEqual(
            rendered.rows.map(\.kind),
            [.prefixCandidate, .aiRecommendation, .prefixCandidate]
        )
        XCTAssertEqual(rendered.rows.map(\.shortcutLabel), ["1", "⇥", "2"])
        XCTAssertEqual(rendered.rows[1].visualRole, .aiRecommendation)
        XCTAssertEqual(rendered.rows[1].accessibilityLabel, "AI 推荐，⇥，我觉得这个方案需要先验证核心假设")
    }

    func testPendingAIStatusIsRenderedButNotSelectable() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "wo jue de zhege fangan",
            prefixCandidates: prefixCandidates,
            continuationCandidates: [],
            aiRecommendation: .pending(requestID: UUID())
        )

        let rendered = CandidatePanelRenderer(locale: .zhCN).render(viewModel)

        XCTAssertEqual(rendered.rows.map(\.kind), [.prefixCandidate, .aiRecommendation, .prefixCandidate])
        XCTAssertEqual(rendered.rows.map(\.shortcutLabel), ["1", nil, "2"])
        XCTAssertEqual(rendered.rows[1].selection, nil)
        XCTAssertEqual(rendered.rows[1].text, "")
        XCTAssertFalse(rendered.rows[1].isEnabled)
        XCTAssertFalse(rendered.rows[1].isSelected)
        XCTAssertEqual(rendered.rows[1].accessory, .spinner)
        XCTAssertEqual(rendered.rows[1].accessibilityLabel, "AI 状态，AI 推荐中")
    }

    func testRendersRawInputOnlyWhenNoSuggestionsExist() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "this is teh plan",
            prefixCandidates: [],
            continuationCandidates: []
        )

        let rendered = CandidatePanelRenderer(locale: .enUS).render(viewModel)

        XCTAssertEqual(rendered.rows.map(\.kind), [.rawInput])
        XCTAssertEqual(rendered.rows[0].text, "this is teh plan")
        XCTAssertNil(rendered.rows[0].shortcutLabel)
    }

    func testRendersPreeditRowBeforeSuggestionsWithoutShortcut() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "ni",
            preeditDisplayText: "ni",
            prefixCandidates: prefixCandidates,
            continuationCandidates: []
        )

        let rendered = CandidatePanelRenderer(locale: .zhCN).render(viewModel)

        XCTAssertEqual(rendered.rows.map(\.kind), [.preedit, .prefixCandidate, .prefixCandidate])
        XCTAssertEqual(rendered.rows.map(\.shortcutLabel), [nil, "1", "2"])
        XCTAssertEqual(rendered.rows[0].text, "ni")
        XCTAssertNil(rendered.rows[0].selection)
        XCTAssertFalse(rendered.rows[0].isSelected)
        XCTAssertTrue(rendered.rows[0].isEnabled)
        XCTAssertEqual(rendered.rows[0].visualRole, .rawInput)
        XCTAssertEqual(rendered.rows[0].accessibilityLabel, "预编辑，ni")
    }

    func testRendersModeStatusBeforeCandidatesWithoutShortcut() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "ni",
            modeStatusText: "中 · 中文标点 · 半角",
            prefixCandidates: prefixCandidates,
            continuationCandidates: []
        )

        let rendered = CandidatePanelRenderer(locale: .zhCN).render(viewModel)

        XCTAssertEqual(rendered.rows.map(\.kind), [.modeStatus, .prefixCandidate, .prefixCandidate])
        XCTAssertEqual(rendered.rows.map(\.shortcutLabel), [nil, "1", "2"])
        XCTAssertEqual(rendered.rows[0].text, "中 · 中文标点 · 半角")
        XCTAssertEqual(rendered.rows[0].visualRole, .status)
        XCTAssertFalse(rendered.rows[0].isEnabled)
        XCTAssertEqual(rendered.rows[0].accessibilityLabel, "输入模式，中 · 中文标点 · 半角")
    }

    func testRendersSymbolCandidatesWithNumberShortcuts() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "",
            prefixCandidates: [],
            continuationCandidates: [],
            symbolCandidates: [
                InputSymbolCandidate(text: "、"),
                InputSymbolCandidate(text: "/"),
                InputSymbolCandidate(text: "／")
            ]
        )

        let rendered = CandidatePanelRenderer(locale: .zhCN).render(
            viewModel,
            selected: .symbolCandidate(1)
        )

        XCTAssertEqual(rendered.rows.map(\.kind), [.symbolCandidate, .symbolCandidate, .symbolCandidate])
        XCTAssertEqual(rendered.rows.map(\.shortcutLabel), ["1", "2", "3"])
        XCTAssertEqual(rendered.rows.map(\.text), ["、", "/", "／"])
        XCTAssertEqual(rendered.rows.map(\.selection), [.symbolCandidate(0), .symbolCandidate(1), .symbolCandidate(2)])
        XCTAssertTrue(rendered.rows[1].isSelected)
        XCTAssertEqual(rendered.rows[1].accessibilityLabel, "符号，2，/")
    }

    func testPreeditRowDoesNotConsumeCandidatePagingSlots() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "hou xuan",
            preeditDisplayText: "hou xuan",
            prefixCandidates: prefixCandidates(count: 12),
            continuationCandidates: []
        )

        let rendered = CandidatePanelRenderer(locale: .zhCN).render(
            viewModel,
            selected: .prefixCandidate(6),
            paging: CandidatePanelPagingState(currentPage: 1)
        )

        XCTAssertEqual(rendered.rows.first?.kind, .preedit)
        XCTAssertEqual(rendered.rows.dropFirst().map(\.text), ["候选7", "候选8", "候选9", "候选10", "候选11", "候选12"])
        XCTAssertEqual(rendered.rows.dropFirst().map(\.shortcutLabel), ["1", "2", "3", "4", "5", "6"])
        XCTAssertEqual(rendered.rows.count, 7)
    }

    func testMarksSelectedContinuationRow() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "wo jue de zhege fangan",
            prefixCandidates: [prefixCandidates[0]],
            continuationCandidates: continuationCandidates
        )

        let rendered = CandidatePanelRenderer(locale: .zhCN).render(
            viewModel,
            selected: .continuationCandidate(1)
        )

        XCTAssertFalse(rendered.rows[0].isSelected)
        XCTAssertFalse(rendered.rows[1].isSelected)
        XCTAssertTrue(rendered.rows[2].isSelected)
    }

    func testOmitsContinuationRowsWhenEmpty() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "wo jue de zhege fangan",
            prefixCandidates: prefixCandidates,
            continuationCandidates: []
        )

        let rendered = CandidatePanelRenderer(locale: .zhCN).render(viewModel)

        XCTAssertFalse(rendered.rows.contains { $0.kind == .continuationCandidate })
        XCTAssertEqual(rendered.rows.map(\.kind), [.prefixCandidate, .prefixCandidate])
        XCTAssertNil(rendered.previewText)
    }

    func testAllShortcutableCandidatesAreRendered() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "wo jue de zhege fangan",
            prefixCandidates: prefixCandidates + [
                CorrectionCandidate(text: "我觉得这个方向", source: "local", confidence: 0.7, correctionLevel: .contextual),
                CorrectionCandidate(text: "我觉得这个方法", source: "local", confidence: 0.6, correctionLevel: .contextual)
            ],
            continuationCandidates: continuationCandidates + [
                ContinuationCandidate(
                    text: "但是需要更多测试数据",
                    lengthLevel: .medium,
                    confidence: 0.7,
                    provider: "test"
                ),
                ContinuationCandidate(
                    text: "可以先做小范围验证",
                    lengthLevel: .medium,
                    confidence: 0.6,
                    provider: "test"
                )
            ]
        )

        let rendered = CandidatePanelRenderer(locale: .mixed).render(viewModel)

        XCTAssertEqual(rendered.rows.filter { $0.kind == .prefixCandidate }.count, 4)
        XCTAssertEqual(rendered.rows.filter { $0.kind == .continuationCandidate }.count, 2)
        XCTAssertEqual(rendered.rows.map(\.shortcutLabel), ["1", "2", "3", "4", "⇥", "⌥2"])
        XCTAssertEqual(rendered.rows.suffix(2).map(\.visualRole), [.continuation, .continuation])
    }

    func testRendersOnlyVisiblePageRows() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "hou xuan",
            prefixCandidates: prefixCandidates(count: 12),
            continuationCandidates: []
        )

        let rendered = CandidatePanelRenderer(locale: .zhCN).render(
            viewModel,
            selected: .prefixCandidate(6),
            paging: CandidatePanelPagingState(currentPage: 1)
        )

        XCTAssertEqual(rendered.rows.count, 6)
        XCTAssertEqual(rendered.rows.map(\.text), ["候选7", "候选8", "候选9", "候选10", "候选11", "候选12"])
        XCTAssertEqual(rendered.rows.map(\.shortcutLabel), ["1", "2", "3", "4", "5", "6"])
        XCTAssertTrue(rendered.rows[0].isSelected)
    }

    func testRendererInfersVisiblePageFromSelectionWhenPagingIsOmitted() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "hou xuan",
            prefixCandidates: prefixCandidates(count: 12),
            continuationCandidates: []
        )

        let rendered = CandidatePanelRenderer(locale: .zhCN).render(
            viewModel,
            selected: .prefixCandidate(10)
        )

        XCTAssertEqual(rendered.rows.map(\.text), ["候选7", "候选8", "候选9", "候选10", "候选11", "候选12"])
        XCTAssertTrue(rendered.rows[4].isSelected)
    }

    func testContinuationShortcutLabelsStayGlobalAcrossPages() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "continue",
            prefixCandidates: [],
            continuationCandidates: (0..<11).map {
                ContinuationCandidate(
                    text: "续写\($0 + 1)",
                    lengthLevel: .medium,
                    confidence: 0.9,
                    provider: "test"
                )
            }
        )

        let rendered = CandidatePanelRenderer(locale: .mixed).render(
            viewModel,
            selected: .continuationCandidate(9),
            paging: CandidatePanelPagingState(currentPage: 1)
        )

        XCTAssertEqual(rendered.rows.map(\.text), ["续写7", "续写8", "续写9", "续写10", "续写11"])
        XCTAssertEqual(rendered.rows.map(\.shortcutLabel), ["⌥7", "⌥8", "⌥9", nil, nil])
        XCTAssertTrue(rendered.rows[3].isSelected)
    }

    func testOptionShortcutLabelsMatchCommitActions() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "wo jue de zhege fangan",
            prefixCandidates: prefixCandidates,
            continuationCandidates: continuationCandidates
        )
        let rendered = CandidatePanelRenderer(locale: .mixed).render(viewModel)
        let controller = InputCompositionController()

        XCTAssertEqual(rendered.rows[2].shortcutLabel, "⇥")
        XCTAssertEqual(rendered.rows[3].shortcutLabel, "⌥2")
        XCTAssertEqual(
            controller.handle(
                action: .tab,
                prefixCandidates: prefixCandidates,
                continuationCandidates: continuationCandidates,
                originalText: viewModel.rawInput
            ),
            .commit("我觉得这个方案还有进一步优化空间")
        )
        XCTAssertEqual(
            controller.handle(
                action: .optionNumber(1),
                prefixCandidates: prefixCandidates,
                continuationCandidates: continuationCandidates,
                originalText: viewModel.rawInput
            ),
            .commit("我觉得这个方案还有进一步优化空间")
        )
        XCTAssertEqual(
            controller.handle(
                action: .optionNumber(2),
                prefixCandidates: prefixCandidates,
                continuationCandidates: continuationCandidates,
                originalText: viewModel.rawInput
            ),
            .commit("我觉得这个方案在落地成本上可能偏高")
        )
    }

    private func prefixCandidates(count: Int) -> [CorrectionCandidate] {
        (0..<count).map {
            CorrectionCandidate(
                text: "候选\($0 + 1)",
                source: "local",
                confidence: 1.0,
                correctionLevel: .contextual
            )
        }
    }
}
