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
                .continuationCandidate
            ]
        )
        XCTAssertNil(rendered.previewText)
        XCTAssertEqual(rendered.rows[0].visualRole, .lockedPrefix)
        XCTAssertEqual(rendered.rows[1].visualRole, .lockedPrefix)
        XCTAssertEqual(rendered.rows[2].visualRole, .continuation)
        XCTAssertEqual(rendered.rows[0].shortcutLabel, "1")
        XCTAssertEqual(rendered.rows[1].shortcutLabel, "2")
        XCTAssertEqual(rendered.rows[2].shortcutLabel, "⇥")
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

    func testContinuationsExpandWhenPrefixCandidatesAreSparse() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "wo jue de zhege fangan",
            prefixCandidates: [prefixCandidates[0]],
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

        XCTAssertEqual(
            rendered.rows.map(\.kind),
            [
                .prefixCandidate,
                .continuationCandidate,
                .continuationCandidate,
                .continuationCandidate
            ]
        )
        XCTAssertEqual(rendered.rows.map(\.shortcutLabel), ["1", "⇥", "⌥2", "⌥3"])
        XCTAssertEqual(rendered.rows.dropFirst().map(\.visualRole), [.continuation, .continuation, .continuation])
    }

    func testContinuationRowsAreMutedAndLimitedWhenPrefixCandidatesArePrimary() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "wo jue de zhege fangan",
            prefixCandidates: prefixCandidates,
            continuationCandidates: continuationCandidates
        )

        let rendered = CandidatePanelRenderer(locale: .mixed).render(viewModel)

        XCTAssertEqual(rendered.rows.filter { $0.kind == .continuationCandidate }.count, 1)
        XCTAssertEqual(rendered.rows.last?.visualRole, .continuation)
        XCTAssertEqual(rendered.rows.last?.shortcutLabel, "⇥")
    }

    func testOptionShortcutLabelsMatchCommitActions() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "wo jue de zhege fangan",
            prefixCandidates: prefixCandidates,
            continuationCandidates: continuationCandidates
        )
        let rendered = CandidatePanelRenderer(locale: .mixed).render(viewModel)
        let expandedRendered = CandidatePanelRenderer(locale: .mixed).render(
            CandidatePanelViewModel(
                rawInput: viewModel.rawInput,
                prefixCandidates: [prefixCandidates[0]],
                continuationCandidates: continuationCandidates
            )
        )
        let controller = InputCompositionController()

        XCTAssertEqual(rendered.rows[2].shortcutLabel, "⇥")
        XCTAssertEqual(expandedRendered.rows[1].shortcutLabel, "⇥")
        XCTAssertEqual(expandedRendered.rows[2].shortcutLabel, "⌥2")
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
