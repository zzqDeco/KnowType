import XCTest
import CoreGraphics
import KnowTypeCore
@testable import KnowTypeInputMethod

final class CandidatePanelStateTests: XCTestCase {
    func testRawInputOnlyStateIsVisibleAndSelectsRawInput() {
        var state = CandidatePanelState()

        state.update(rawInput: "wo jue", suggestion: nil, anchorRect: CGRect(x: 10, y: 20, width: 1, height: 18))

        XCTAssertTrue(state.windowState.isVisible)
        XCTAssertEqual(state.windowState.anchorRect, CGRect(x: 10, y: 20, width: 1, height: 18))
        XCTAssertEqual(state.windowState.viewModel.rawInput, "wo jue")
        XCTAssertTrue(state.windowState.viewModel.prefixCandidates.isEmpty)
        XCTAssertTrue(state.windowState.viewModel.continuationCandidates.isEmpty)
        XCTAssertEqual(state.windowState.selection, .rawInput)
    }

    func testSuggestionStateSeparatesPrefixAndContinuationRows() {
        var state = CandidatePanelState()

        state.update(rawInput: "wo jue de", suggestion: suggestion())
        let rendered = CandidatePanelRenderer(locale: .zhCN).render(
            state.windowState.viewModel,
            selected: state.windowState.selection
        )

        XCTAssertTrue(state.windowState.isVisible)
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
        XCTAssertEqual(rendered.rows[3].visualRole, .lockedPrefix)
        XCTAssertEqual(rendered.rows[6].visualRole, .continuation)
        XCTAssertTrue(rendered.rows[3].isSelected)
        XCTAssertFalse(rendered.rows[6].isSelected)
    }

    func testDefaultSelectionPrefersFirstPrefixOverRawAndContinuation() {
        var state = CandidatePanelState()

        state.update(rawInput: "wo jue de", suggestion: suggestion())

        XCTAssertEqual(state.windowState.selection, .prefixCandidate(0))
    }

    func testDefaultSelectionFallsBackToFirstContinuationWhenSuggestionHasNoPrefixOrRawInput() {
        var state = CandidatePanelState()

        state.update(
            rawInput: "",
            suggestion: SuggestionResponse(
                prefixCandidates: [],
                lockedPrefix: nil,
                continuationCandidates: [
                    ContinuationCandidate(
                        text: "continues from the protected prefix",
                        lengthLevel: .medium,
                        confidence: 0.8,
                        provider: "test"
                    )
                ],
                latencyMs: 3
            )
        )

        XCTAssertTrue(state.windowState.isVisible)
        XCTAssertEqual(state.windowState.selection, .continuationCandidate(0))
    }

    func testEmptyUpdateHidesPanel() {
        var state = CandidatePanelState()

        state.update(rawInput: "", suggestion: nil)

        XCTAssertFalse(state.windowState.isVisible)
        XCTAssertNil(state.windowState.selection)
        XCTAssertEqual(state.windowState.viewModel.rawInput, "")
        XCTAssertTrue(state.windowState.viewModel.prefixCandidates.isEmpty)
        XCTAssertTrue(state.windowState.viewModel.continuationCandidates.isEmpty)
    }

    func testHideResetsWindowState() {
        var state = CandidatePanelState()
        state.update(
            rawInput: "wo jue de",
            suggestion: suggestion(),
            anchorRect: CGRect(x: 5, y: 6, width: 7, height: 8)
        )

        state.hide()

        XCTAssertEqual(state.windowState, CandidatePanelWindowState())
    }

    private func suggestion() -> SuggestionResponse {
        let prefixCandidates = [
            CorrectionCandidate(
                text: "我觉得",
                source: "local",
                confidence: 1.0,
                correctionLevel: .contextual
            ),
            CorrectionCandidate(
                text: "我觉着",
                source: "local",
                confidence: 0.8,
                correctionLevel: .contextual
            )
        ]
        return SuggestionResponse(
            prefixCandidates: prefixCandidates,
            lockedPrefix: LockedPrefix(
                text: "我觉得",
                rawInput: "wo jue de",
                candidateID: "local"
            ),
            continuationCandidates: [
                ContinuationCandidate(
                    text: "这个方案还有优化空间",
                    lengthLevel: .medium,
                    confidence: 0.9,
                    provider: "test"
                ),
                ContinuationCandidate(
                    text: "这件事需要再评估",
                    lengthLevel: .medium,
                    confidence: 0.7,
                    provider: "test"
                )
            ],
            latencyMs: 5
        )
    }
}
