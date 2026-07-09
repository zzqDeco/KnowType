import XCTest
import CoreGraphics
import KnowTypeAI
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

    func testPlacementPreferenceIsStoredInVisibleWindowState() {
        var state = CandidatePanelState()

        state.update(
            rawInput: "wo jue",
            suggestion: nil,
            anchorRect: CGRect(x: 10, y: 20, width: 1, height: 18),
            placementPreference: .preferVisualAbove
        )

        XCTAssertEqual(state.windowState.placementPreference, .preferVisualAbove)
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

    func testPreeditRowDoesNotBecomeSelectionOrShortcutTarget() {
        var state = CandidatePanelState()

        state.update(
            rawInput: "ni",
            suggestion: suggestion(prefixTexts: ["你", "呢"]),
            preeditDisplayText: "ni"
        )
        let rendered = CandidatePanelRenderer(locale: .zhCN).render(
            state.windowState.viewModel,
            selected: state.windowState.selection,
            paging: state.windowState.paging
        )

        XCTAssertTrue(state.windowState.isVisible)
        XCTAssertEqual(state.windowState.viewModel.preeditDisplayText, "ni")
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(0))
        XCTAssertEqual(rendered.rows.map(\.kind), [.preedit, .prefixCandidate, .prefixCandidate])
        XCTAssertEqual(rendered.rows.map(\.shortcutLabel), [nil, "1", "2"])
        XCTAssertEqual(state.selectVisiblePrefixCandidate(shortcutNumber: 1), .prefixCandidate(0))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(0))
    }

    func testClearingModeStatusPreservesCompositionRows() {
        var state = CandidatePanelState()

        state.update(
            rawInput: "ni",
            suggestion: suggestion(prefixTexts: ["你", "呢"]),
            preeditDisplayText: "ni",
            modeStatusText: "中 · 中文标点 · 半角"
        )

        XCTAssertTrue(state.clearModeStatusText())
        XCTAssertNil(state.windowState.viewModel.modeStatusText)
        XCTAssertEqual(state.windowState.viewModel.preeditDisplayText, "ni")
        XCTAssertEqual(state.windowState.viewModel.prefixCandidates.map(\.text), ["你", "呢"])
        XCTAssertTrue(state.windowState.isVisible)
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(0))
    }

    func testPreeditOnlyStateIsVisibleWithoutSelectableRawFallback() {
        var state = CandidatePanelState()

        state.update(rawInput: "n", suggestion: nil, preeditDisplayText: "n")
        let rendered = CandidatePanelRenderer(locale: .zhCN).render(
            state.windowState.viewModel,
            selected: state.windowState.selection,
            paging: state.windowState.paging
        )

        XCTAssertTrue(state.windowState.isVisible)
        XCTAssertNil(state.windowState.selection)
        XCTAssertEqual(rendered.rows.map(\.kind), [.preedit])
        XCTAssertFalse(state.moveSelection(.down))
        XCTAssertNil(state.selectVisiblePrefixCandidate(shortcutNumber: 1))
    }

    func testVisibleShortcutSkipsReadyAIRecommendationForNumberSelection() {
        var state = CandidatePanelState()
        state.update(
            rawInput: "nihao",
            suggestion: suggestion(prefixTexts: ["你好", "你号"]),
            aiRecommendation: .ready(
                AIRecommendationCandidate(
                    prefixText: "你好",
                    continuationText: "继续推进",
                    displayText: "你好继续推进",
                    confidence: 0.9,
                    provider: "test",
                    contextVersion: "v1"
                )
            )
        )

        XCTAssertEqual(state.selectVisiblePrefixCandidate(shortcutNumber: 2), .prefixCandidate(1))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(1))
    }

    func testVisibleShortcutSkipsNonReadyAIStatusRows() {
        var state = CandidatePanelState()
        state.update(
            rawInput: "nihao",
            suggestion: suggestion(prefixTexts: ["你好", "你号"]),
            aiRecommendation: .pending(requestID: UUID())
        )
        let rendered = CandidatePanelRenderer(locale: .zhCN).render(
            state.windowState.viewModel,
            selected: state.windowState.selection,
            paging: state.windowState.paging
        )

        XCTAssertEqual(rendered.rows.map(\.shortcutLabel), ["1", nil, "2"])
        XCTAssertEqual(state.selectVisiblePrefixCandidate(shortcutNumber: 2), .prefixCandidate(1))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(1))
    }

    func testPendingAIWithoutCandidatesDoesNotSelectHiddenRawFallback() {
        var state = CandidatePanelState()
        state.update(
            rawInput: "nihao",
            suggestion: nil,
            aiRecommendation: .pending(requestID: UUID())
        )
        let rendered = CandidatePanelRenderer(locale: .zhCN).render(
            state.windowState.viewModel,
            selected: state.windowState.selection,
            paging: state.windowState.paging
        )

        XCTAssertTrue(state.windowState.isVisible)
        XCTAssertNil(state.windowState.selection)
        XCTAssertEqual(rendered.rows.map(\.kind), [.aiRecommendation])
        XCTAssertEqual(rendered.rows.map(\.selection), [nil])
    }

    func testReadyAIWithoutCandidatesDoesNotBecomeDefaultSelection() {
        var state = CandidatePanelState()
        state.update(
            rawInput: "nihao",
            suggestion: nil,
            aiRecommendation: .ready(
                AIRecommendationCandidate(
                    prefixText: "",
                    continuationText: nil,
                    displayText: "继续推进",
                    confidence: 0.9,
                    provider: "test",
                    contextVersion: "v1"
                )
            )
        )
        let rendered = CandidatePanelRenderer(locale: .zhCN).render(
            state.windowState.viewModel,
            selected: state.windowState.selection,
            paging: state.windowState.paging
        )

        XCTAssertTrue(state.windowState.isVisible)
        XCTAssertNil(state.windowState.selection)
        XCTAssertEqual(rendered.rows.map(\.kind), [.aiRecommendation])
        XCTAssertEqual(rendered.rows.map(\.selection), [.aiRecommendation])
        XCTAssertFalse(rendered.rows[0].isSelected)
    }

    func testReadyAIReplacedByPendingKeepsAIRowWithoutSelectingIt() {
        var state = CandidatePanelState()
        let initialSuggestion = suggestion(prefixTexts: ["你好", "你号"])
        state.update(
            rawInput: "nihao",
            suggestion: initialSuggestion,
            aiRecommendation: .ready(
                AIRecommendationCandidate(
                    prefixText: "你好",
                    continuationText: "继续推进",
                    displayText: "你好继续推进",
                    confidence: 0.9,
                    provider: "test",
                    contextVersion: "v1"
                )
            )
        )
        let readyRows = CandidatePanelRenderer(locale: .zhCN).render(
            state.windowState.viewModel,
            selected: state.windowState.selection,
            paging: state.windowState.paging
        ).rows

        state.update(
            rawInput: "nihaoa",
            suggestion: initialSuggestion,
            aiRecommendation: .pending(requestID: UUID())
        )
        let pendingRows = CandidatePanelRenderer(locale: .zhCN).render(
            state.windowState.viewModel,
            selected: state.windowState.selection,
            paging: state.windowState.paging
        ).rows

        XCTAssertEqual(readyRows.map(\.kind), [.prefixCandidate, .aiRecommendation, .prefixCandidate])
        XCTAssertEqual(pendingRows.map(\.kind), [.prefixCandidate, .aiRecommendation, .prefixCandidate])
        XCTAssertEqual(pendingRows[1].selection, nil)
        XCTAssertEqual(pendingRows[1].accessory, .spinner)
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(0))
    }

    func testNavigationSkipsNonReadyAIStatusRows() {
        var state = CandidatePanelState()
        state.update(
            rawInput: "nihao",
            suggestion: suggestion(prefixTexts: ["你好", "你号"]),
            aiRecommendation: .unavailable(reason: "AI 暂不可用")
        )

        XCTAssertEqual(state.windowState.selection, .prefixCandidate(0))
        XCTAssertTrue(state.moveSelection(.down))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(1))
        XCTAssertTrue(state.moveSelection(.up))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(0))
    }

    func testSelectVisibleRowAcceptsOnlyVisibleEnabledRows() {
        var state = CandidatePanelState()
        state.update(
            rawInput: "candidate",
            suggestion: multiPagePrefixSuggestion(count: 12)
        )

        XCTAssertTrue(state.selectVisibleRow(.prefixCandidate(5)))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(5))
        XCTAssertFalse(state.selectVisibleRow(.prefixCandidate(6)))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(5))
    }

    func testVisibleShortcutIgnoresLegacyContinuationRowsWithoutNumberLabels() {
        var state = CandidatePanelState()
        state.update(
            rawInput: "wo jue de",
            suggestion: suggestion(
                prefixTexts: ["我觉得", "我觉的"],
                continuationTexts: ["还有进一步优化空间", "需要继续确认"]
            )
        )
        let rendered = CandidatePanelRenderer(locale: .zhCN).render(
            state.windowState.viewModel,
            selected: state.windowState.selection,
            paging: state.windowState.paging
        )

        XCTAssertEqual(rendered.rows.map(\.shortcutLabel), ["1", "2", "⇥", "⌥2"])
        XCTAssertNil(state.selectVisiblePrefixCandidate(shortcutNumber: 3))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(0))
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
        XCTAssertEqual(state.windowState.selection, .continuationCandidate(0))
    }

    func testPageDownAndPageUpPreserveVisibleRowOffset() {
        var state = CandidatePanelState()
        state.update(rawInput: "candidate", suggestion: multiPagePrefixSuggestion(count: 12))

        XCTAssertEqual(state.windowState.paging, CandidatePanelPagingState(currentPage: 0))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(0))

        XCTAssertTrue(state.moveSelection(.pageDown))
        XCTAssertEqual(state.windowState.paging, CandidatePanelPagingState(currentPage: 1))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(6))

        XCTAssertTrue(state.moveSelection(.down))
        XCTAssertEqual(state.windowState.paging, CandidatePanelPagingState(currentPage: 1))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(7))

        XCTAssertTrue(state.moveSelection(.pageUp))
        XCTAssertEqual(state.windowState.paging, CandidatePanelPagingState(currentPage: 0))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(1))
    }

    func testConfiguredPageSizeAndLayoutModeAreStoredInWindowState() {
        var state = CandidatePanelState()
        state.update(
            rawInput: "candidate",
            suggestion: multiPagePrefixSuggestion(count: 12),
            pageSize: 6,
            layoutMode: .verticalPreferred
        )

        XCTAssertEqual(state.windowState.paging, CandidatePanelPagingState(currentPage: 0, pageSize: 6))
        XCTAssertEqual(state.windowState.layoutMode, .verticalPreferred)

        XCTAssertTrue(state.moveSelection(.pageDown))
        XCTAssertEqual(state.windowState.paging, CandidatePanelPagingState(currentPage: 1, pageSize: 6))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(6))
    }

    func testPageDownClampsPreservedOffsetOnShortLastPage() {
        var state = CandidatePanelState()
        state.update(rawInput: "candidate", suggestion: multiPagePrefixSuggestion(count: 10))

        for _ in 0..<5 {
            XCTAssertTrue(state.moveSelection(.down))
        }
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(5))

        XCTAssertTrue(state.moveSelection(.pageDown))
        XCTAssertEqual(state.windowState.paging, CandidatePanelPagingState(currentPage: 1))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(9))
    }

    func testArrowNavigationCrossesPageBoundariesOnlyAtPageEdges() {
        var state = CandidatePanelState()
        state.update(rawInput: "candidate", suggestion: multiPagePrefixSuggestion(count: 12))

        for _ in 0..<5 {
            XCTAssertTrue(state.moveSelection(.down))
        }
        XCTAssertEqual(state.windowState.paging, CandidatePanelPagingState(currentPage: 0))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(5))

        XCTAssertTrue(state.moveSelection(.down))
        XCTAssertEqual(state.windowState.paging, CandidatePanelPagingState(currentPage: 1))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(6))

        XCTAssertTrue(state.moveSelection(.up))
        XCTAssertEqual(state.windowState.paging, CandidatePanelPagingState(currentPage: 0))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(5))
    }

    func testPageNavigationAtBoundsPreservesSelection() {
        var state = CandidatePanelState()
        state.update(rawInput: "candidate", suggestion: multiPagePrefixSuggestion(count: 12))

        XCTAssertTrue(state.moveSelection(.down))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(1))

        XCTAssertTrue(state.moveSelection(.pageUp))
        XCTAssertEqual(state.windowState.paging, CandidatePanelPagingState(currentPage: 0))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(1))

        XCTAssertTrue(state.moveSelection(.pageDown))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(7))

        XCTAssertTrue(state.moveSelection(.pageDown))
        XCTAssertEqual(state.windowState.paging, CandidatePanelPagingState(currentPage: 1))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(7))
    }

    func testSelectionAndPagePersistAcrossSameInputUpdateWhenRowStillExists() {
        var state = CandidatePanelState()
        state.update(rawInput: "candidate", suggestion: multiPagePrefixSuggestion(count: 12))
        XCTAssertTrue(state.moveSelection(.pageDown))
        XCTAssertTrue(state.moveSelection(.down))

        state.update(rawInput: "candidate", suggestion: multiPagePrefixSuggestion(count: 12))

        XCTAssertEqual(state.windowState.paging, CandidatePanelPagingState(currentPage: 1))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(7))
    }

    func testSelectionResetsWhenSameRawInputPrefixAtIndexChanges() {
        var state = CandidatePanelState()
        state.update(
            rawInput: "candidate",
            suggestion: suggestion(prefixTexts: ["候选1", "候选2"])
        )
        XCTAssertEqual(state.selectVisiblePrefixCandidate(shortcutNumber: 2), .prefixCandidate(1))

        state.update(
            rawInput: "candidate",
            suggestion: suggestion(prefixTexts: ["云端候选", "候选1", "候选2"])
        )

        XCTAssertEqual(state.windowState.selection, .prefixCandidate(0))
    }

    func testContinuationSelectionResetsWhenSameRawInputCandidateAtIndexChanges() {
        var state = CandidatePanelState()
        state.update(
            rawInput: "",
            suggestion: suggestion(prefixTexts: [], continuationTexts: ["延续1", "延续2"])
        )
        XCTAssertTrue(state.moveSelection(.down))
        XCTAssertEqual(state.windowState.selection, .continuationCandidate(1))

        state.update(
            rawInput: "",
            suggestion: suggestion(prefixTexts: [], continuationTexts: ["延续1", "云端延续"])
        )

        XCTAssertEqual(state.windowState.selection, .continuationCandidate(0))
    }

    func testVisibleShortcutSelectsCandidateOnCurrentPage() {
        var state = CandidatePanelState()
        state.update(rawInput: "candidate", suggestion: multiPagePrefixSuggestion(count: 12))
        XCTAssertTrue(state.moveSelection(.pageDown))

        XCTAssertEqual(
            state.selectVisiblePrefixCandidate(shortcutNumber: 2),
            .prefixCandidate(7)
        )
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(7))
        XCTAssertEqual(state.windowState.paging, CandidatePanelPagingState(currentPage: 1))
    }

    func testVisibleShortcutIgnoresUnavailableRowsAndHiddenPanel() {
        var state = CandidatePanelState()

        XCTAssertNil(state.selectVisiblePrefixCandidate(shortcutNumber: 1))

        state.update(rawInput: "candidate", suggestion: multiPagePrefixSuggestion(count: 2))
        XCTAssertNil(state.selectVisiblePrefixCandidate(shortcutNumber: 3))
        XCTAssertNil(state.selectVisiblePrefixCandidate(shortcutNumber: 0))
        XCTAssertEqual(state.windowState.selection, .prefixCandidate(0))
    }

    func testMoveSelectionUsesRawInputOnlyWhenNoSuggestionsAreVisible() {
        var state = CandidatePanelState()
        state.update(rawInput: "raw", suggestion: nil)

        XCTAssertTrue(state.moveSelection(.down))
        XCTAssertEqual(state.windowState.selection, .rawInput)
    }

    func testMoveSelectionReturnsFalseWhenPanelHasNoRows() {
        var state = CandidatePanelState()

        XCTAssertFalse(state.moveSelection(.down))
        XCTAssertNil(state.windowState.selection)
    }

    func testUndisplayableUpdateHidesPanelButKeepsPendingViewModel() {
        var state = CandidatePanelState()

        state.update(
            rawInput: "wo jue de",
            suggestion: suggestion(),
            anchorRect: .zero,
            isDisplayable: false
        )

        XCTAssertFalse(state.windowState.isVisible)
        XCTAssertNil(state.windowState.selection)
        XCTAssertEqual(state.windowState.viewModel.rawInput, "wo jue de")
        XCTAssertEqual(state.windowState.viewModel.prefixCandidates.count, 2)
        XCTAssertEqual(state.windowState.paging, CandidatePanelPagingState())
        XCTAssertFalse(state.moveSelection(.down))
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

    private func multiPagePrefixSuggestion(count: Int) -> SuggestionResponse {
        SuggestionResponse(
            prefixCandidates: (0..<count).map {
                CorrectionCandidate(
                    text: "候选\($0 + 1)",
                    source: "local",
                    confidence: 1.0,
                    correctionLevel: .contextual
                )
            },
            lockedPrefix: nil,
            continuationCandidates: [],
            latencyMs: 2
        )
    }

    private func suggestion(
        prefixTexts: [String],
        continuationTexts: [String] = []
    ) -> SuggestionResponse {
        let prefixCandidates = prefixTexts.map {
            CorrectionCandidate(
                text: $0,
                source: "local",
                confidence: 1.0,
                correctionLevel: .contextual
            )
        }
        return SuggestionResponse(
            prefixCandidates: prefixCandidates,
            lockedPrefix: prefixCandidates.first.map {
                LockedPrefix(text: $0.text, rawInput: "candidate", candidateID: "local")
            },
            continuationCandidates: continuationTexts.map {
                ContinuationCandidate(
                    text: $0,
                    lengthLevel: .medium,
                    confidence: 0.8,
                    provider: "test"
                )
            },
            latencyMs: 2
        )
    }
}
