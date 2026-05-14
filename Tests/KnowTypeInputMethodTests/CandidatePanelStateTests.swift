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
                .prefixCandidate,
                .prefixCandidate,
                .continuationCandidate,
                .continuationCandidate
            ]
        )
        XCTAssertEqual(rendered.rows[0].visualRole, .lockedPrefix)
        XCTAssertEqual(rendered.rows[2].visualRole, .continuation)
        XCTAssertTrue(rendered.rows[0].isSelected)
        XCTAssertFalse(rendered.rows[2].isSelected)
    }

    func testDefaultSelectionPrefersFirstPrefixOverRawAndContinuation() {
        var state = CandidatePanelState()

        state.update(rawInput: "wo jue de", suggestion: suggestion())

        XCTAssertEqual(state.windowState.selection, .prefixCandidate(0))
    }

    func testMoveSelectionNavigatesVisibleSuggestionRows() {
        var state = CandidatePanelState()
        state.update(rawInput: "wo jue de", suggestion: suggestion())

        XCTAssertTrue(state.moveSelection(.down))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(1))

        XCTAssertTrue(state.moveSelection(.right))
        XCTAssertEqual(state.windowState.selection, .continuationCandidate(0))

        XCTAssertTrue(state.moveSelection(.down))
        XCTAssertEqual(state.windowState.selection, .continuationCandidate(1))

        XCTAssertTrue(state.moveSelection(.pageDown))
        XCTAssertEqual(state.windowState.selection, .continuationCandidate(1))

        XCTAssertTrue(state.moveSelection(.up))
        XCTAssertEqual(state.windowState.selection, .continuationCandidate(0))

        XCTAssertTrue(state.moveSelection(.pageUp))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(0))
    }

    func testMoveSelectionUsesRawInputOnlyWhenNoSuggestionsAreVisible() {
        var state = CandidatePanelState()
        state.update(rawInput: "raw", suggestion: nil)

        XCTAssertTrue(state.moveSelection(.down))
        XCTAssertEqual(state.windowState.selection, .rawInput)
    }

    func testPageNavigationShowsNextPrefixCandidateSlice() {
        var state = CandidatePanelState()
        state.update(rawInput: "ni", suggestion: pagedSuggestion())

        let firstPage = CandidatePanelRenderer(locale: .zhCN).render(
            state.windowState.viewModel,
            selected: state.windowState.selection,
            pageStart: state.windowState.pageStart,
            pageSize: state.windowState.pageSize
        )
        XCTAssertEqual(firstPage.rows.map(\.text), (1...9).map { "候选\($0)" })
        XCTAssertEqual(firstPage.rows.map(\.shortcutLabel), (1...9).map(String.init))

        XCTAssertTrue(state.moveSelection(.pageDown))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(9))
        XCTAssertEqual(state.windowState.pageStart, 9)
        XCTAssertEqual(state.selectionForShortcutNumber(2), .prefixCandidate(10))

        let secondPage = CandidatePanelRenderer(locale: .zhCN).render(
            state.windowState.viewModel,
            selected: state.windowState.selection,
            pageStart: state.windowState.pageStart,
            pageSize: state.windowState.pageSize
        )
        XCTAssertEqual(secondPage.rows.map(\.text), ["候选10", "候选11"])
        XCTAssertEqual(secondPage.rows.map(\.shortcutLabel), ["1", "2"])
    }

    func testSameRawInputRefreshKeepsVisiblePageAndSelection() {
        var state = CandidatePanelState()
        state.update(rawInput: "ni", suggestion: pagedSuggestion())
        XCTAssertTrue(state.moveSelection(.pageDown))

        state.update(rawInput: "ni", suggestion: pagedSuggestion())

        XCTAssertEqual(state.windowState.selection, .prefixCandidate(9))
        XCTAssertEqual(state.windowState.pageStart, 9)
    }

    func testChangedRawInputResetsCandidatePage() {
        var state = CandidatePanelState()
        state.update(rawInput: "ni", suggestion: pagedSuggestion())
        XCTAssertTrue(state.moveSelection(.pageDown))

        state.update(rawInput: "nish", suggestion: pagedSuggestion())

        XCTAssertEqual(state.windowState.selection, .prefixCandidate(0))
        XCTAssertEqual(state.windowState.pageStart, 0)
    }

    func testMoveSelectionReturnsFalseWhenPanelHasNoRows() {
        var state = CandidatePanelState()

        XCTAssertFalse(state.moveSelection(.down))
        XCTAssertNil(state.windowState.selection)
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

    private func pagedSuggestion() -> SuggestionResponse {
        let prefixCandidates = (1...11).map { index in
            CorrectionCandidate(
                text: "候选\(index)",
                source: "local",
                confidence: 1.0 - Double(index) * 0.01,
                correctionLevel: .contextual
            )
        }
        return SuggestionResponse(
            prefixCandidates: prefixCandidates,
            lockedPrefix: LockedPrefix(
                text: "候选1",
                rawInput: "ni",
                candidateID: "local"
            ),
            continuationCandidates: [],
            latencyMs: 1
        )
    }
}
