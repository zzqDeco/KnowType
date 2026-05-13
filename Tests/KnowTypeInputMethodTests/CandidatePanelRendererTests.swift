import XCTest
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

    func testRendersChinesePanelWithSeparatePrefixAndContinuationRows() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "wo jue de zhege fangan",
            prefixCandidates: prefixCandidates,
            continuationCandidates: continuationCandidates
        )

        let rendered = CandidatePanelRenderer(locale: .zhCN).render(viewModel)

        XCTAssertEqual(
            rendered.rows.map(\.kind),
            [
                .sectionHeader,
                .rawInput,
                .sectionHeader,
                .prefixCandidate,
                .prefixCandidate,
                .sectionHeader,
                .continuationCandidate,
                .continuationCandidate
            ]
        )
        XCTAssertEqual(rendered.rows[0].text, "原始输入")
        XCTAssertEqual(rendered.rows[2].text, "锁定前缀")
        XCTAssertEqual(rendered.rows[5].text, "续写")
        XCTAssertEqual(rendered.rows[3].visualRole, .lockedPrefix)
        XCTAssertEqual(rendered.rows[4].visualRole, .lockedPrefix)
        XCTAssertEqual(rendered.rows[6].visualRole, .continuation)
        XCTAssertEqual(rendered.rows[7].visualRole, .continuation)
        XCTAssertEqual(rendered.rows[1].shortcutLabel, "0")
        XCTAssertEqual(rendered.rows[3].shortcutLabel, "1")
        XCTAssertEqual(rendered.rows[4].shortcutLabel, "2")
        XCTAssertEqual(rendered.rows[6].shortcutLabel, "Tab / Option+1")
        XCTAssertEqual(rendered.rows[7].shortcutLabel, "Option+2")
    }

    func testRendersEnglishLabelsForEnglishLocale() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "this is teh plan",
            prefixCandidates: [
                CorrectionCandidate(
                    text: "this is the plan",
                    source: "local",
                    confidence: 1.0,
                    correctionLevel: .light
                )
            ],
            continuationCandidates: [
                ContinuationCandidate(
                    text: "for the next milestone",
                    lengthLevel: .medium,
                    confidence: 0.9,
                    provider: "test"
                )
            ]
        )

        let rendered = CandidatePanelRenderer(locale: .enUS).render(viewModel)

        XCTAssertEqual(rendered.rows[0].text, "Raw Input")
        XCTAssertEqual(rendered.rows[2].text, "Locked Prefix")
        XCTAssertEqual(rendered.rows[4].text, "Continuation")
    }

    func testMarksSelectedContinuationRow() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "wo jue de zhege fangan",
            prefixCandidates: prefixCandidates,
            continuationCandidates: continuationCandidates
        )

        let rendered = CandidatePanelRenderer(locale: .zhCN).render(
            viewModel,
            selected: .continuationCandidate(1)
        )

        XCTAssertFalse(rendered.rows[3].isSelected)
        XCTAssertFalse(rendered.rows[6].isSelected)
        XCTAssertTrue(rendered.rows[7].isSelected)
    }

    func testOmitsContinuationSectionWhenEmpty() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "wo jue de zhege fangan",
            prefixCandidates: prefixCandidates,
            continuationCandidates: []
        )

        let rendered = CandidatePanelRenderer(locale: .zhCN).render(viewModel)

        XCTAssertFalse(rendered.rows.contains { $0.text == "续写" })
        XCTAssertFalse(rendered.rows.contains { $0.kind == .continuationCandidate })
        XCTAssertEqual(rendered.previewText, "我觉得这个方案")
    }

    func testPreviewStringUsesLockedPrefixAndFirstContinuation() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "wo jue de zhege fangan",
            prefixCandidates: prefixCandidates,
            continuationCandidates: continuationCandidates
        )

        let rendered = CandidatePanelRenderer(locale: .mixed).render(viewModel)

        XCTAssertEqual(rendered.previewText, "我觉得这个方案 | 还有进一步优化空间")
    }

    func testOptionShortcutLabelsMatchCommitActions() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "wo jue de zhege fangan",
            prefixCandidates: prefixCandidates,
            continuationCandidates: continuationCandidates
        )
        let rendered = CandidatePanelRenderer(locale: .mixed).render(viewModel)
        let controller = InputCompositionController()

        XCTAssertEqual(rendered.rows[6].shortcutLabel, "Tab / Option+1")
        XCTAssertEqual(rendered.rows[7].shortcutLabel, "Option+2")
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
}
