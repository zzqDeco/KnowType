import XCTest
import KnowTypeAI
import KnowTypeCore
@testable import KnowTypeInputMethod

final class CandidatePanelRowBuilderTests: XCTestCase {
    func testBuildRowsSeparatesFixedPreeditFromPageableCandidateRows() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "ni",
            preeditDisplayText: "ni",
            prefixCandidates: [
                prefix("你"),
                prefix("呢")
            ],
            continuationCandidates: [
                ContinuationCandidate(
                    text: "继续推进",
                    lengthLevel: .medium,
                    confidence: 0.9,
                    provider: "test"
                )
            ],
            aiRecommendation: .ready(
                AIRecommendationCandidate(
                    prefixText: "你",
                    continuationText: "继续推进",
                    displayText: "你继续推进",
                    confidence: 0.9,
                    provider: "test",
                    contextVersion: "v1"
                )
            )
        )

        let rows = CandidatePanelRowBuilder().buildRows(in: viewModel)
        let fixedKinds: [CandidatePanelRowKind] = rows.fixedRows.map(\.kind)
        let fixedSelections: [CandidatePanelSelection?] = rows.fixedRows.map(\.selection)
        let pageableKinds: [CandidatePanelRowKind] = rows.pageableRows.map(\.kind)
        let pageableSelections: [CandidatePanelSelection?] = rows.pageableRows.map(\.selection)
        let numberShortcutEligibility: [Bool] = rows.pageableRows.map(\.isNumberShortcutEligible)

        XCTAssertEqual(fixedKinds, [.preedit])
        XCTAssertEqual(fixedSelections, [nil])
        XCTAssertEqual(
            pageableKinds,
            [.prefixCandidate, .aiRecommendation, .prefixCandidate, .continuationCandidate]
        )
        XCTAssertEqual(
            pageableSelections,
            [.prefixCandidate(0), .aiRecommendation, .prefixCandidate(1), .continuationCandidate(0)]
        )
        XCTAssertEqual(
            numberShortcutEligibility,
            [true, false, true, false]
        )
        XCTAssertEqual(CandidatePanelRowBuilder().defaultSelection(in: viewModel), .prefixCandidate(0))
    }

    func testPreeditOnlyAndDisabledStatusRowsDoNotCreateSelectionTargets() {
        let preeditOnly = CandidatePanelViewModel(
            rawInput: "n",
            preeditDisplayText: "n",
            prefixCandidates: [],
            continuationCandidates: []
        )
        let pendingAI = CandidatePanelViewModel(
            rawInput: "n",
            prefixCandidates: [],
            continuationCandidates: [],
            aiRecommendation: .pending(requestID: UUID())
        )
        let builder = CandidatePanelRowBuilder()

        let preeditKinds: [CandidatePanelRowKind] = builder.buildRows(in: preeditOnly).fixedRows.map(\.kind)
        XCTAssertEqual(preeditKinds, [.preedit])
        XCTAssertTrue(builder.buildRows(in: preeditOnly).pageableRows.isEmpty)
        XCTAssertNil(builder.defaultSelection(in: preeditOnly))

        let pendingRows = builder.buildRows(in: pendingAI)
        let pendingKinds: [CandidatePanelRowKind] = pendingRows.pageableRows.map(\.kind)
        let pendingSelections: [CandidatePanelSelection?] = pendingRows.pageableRows.map(\.selection)
        XCTAssertEqual(pendingKinds, [.aiRecommendation])
        XCTAssertEqual(pendingSelections, [nil])
        XCTAssertEqual(pendingRows.pageableRows[0].text, "")
        XCTAssertFalse(pendingRows.pageableRows[0].isEnabled)
        XCTAssertEqual(pendingRows.pageableRows[0].accessory, .spinner)
        XCTAssertEqual(pendingRows.pageableRows[0].accessibilityLabel, "AI 状态，AI 推荐中")
        XCTAssertNil(builder.defaultSelection(in: pendingAI))
    }

    func testReadyAIOnlyRowIsNotDefaultSelection() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "api",
            prefixCandidates: [],
            continuationCandidates: [],
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

        let rows = CandidatePanelRowBuilder().buildRows(in: viewModel)
        let selections: [CandidatePanelSelection?] = rows.pageableRows.map(\.selection)

        XCTAssertEqual(selections, [.aiRecommendation])
        XCTAssertTrue(rows.pageableRows[0].isEnabled)
        XCTAssertNil(CandidatePanelRowBuilder().defaultSelection(in: viewModel))
    }

    func testModeStatusIsFixedDisabledRowWithoutSelectionTarget() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "",
            modeStatusText: "中 · 中文标点 · 半角",
            prefixCandidates: [],
            continuationCandidates: []
        )

        let rows = CandidatePanelRowBuilder().buildRows(in: viewModel)

        XCTAssertEqual(rows.fixedRows.map(\.kind), [.modeStatus])
        XCTAssertEqual(rows.fixedRows[0].text, "中 · 中文标点 · 半角")
        XCTAssertEqual(rows.fixedRows[0].visualRole, .status)
        XCTAssertEqual(rows.fixedRows[0].accessibilityLabel, "输入模式，中 · 中文标点 · 半角")
        XCTAssertFalse(rows.fixedRows[0].isEnabled)
        XCTAssertNil(rows.fixedRows[0].selection)
        XCTAssertTrue(rows.pageableRows.isEmpty)
        XCTAssertNil(CandidatePanelRowBuilder().defaultSelection(in: viewModel))
    }

    func testSymbolCandidateRowsAreSelectableAndShortcutEligible() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "",
            prefixCandidates: [],
            continuationCandidates: [],
            symbolCandidates: [
                InputSymbolCandidate(text: "、"),
                InputSymbolCandidate(text: "/")
            ]
        )

        let rows = CandidatePanelRowBuilder().buildRows(in: viewModel)

        XCTAssertEqual(rows.pageableRows.map(\.kind), [.symbolCandidate, .symbolCandidate])
        XCTAssertEqual(rows.pageableRows.map(\.selection), [.symbolCandidate(0), .symbolCandidate(1)])
        XCTAssertEqual(rows.pageableRows.map(\.text), ["、", "/"])
        XCTAssertEqual(rows.pageableRows.map(\.visualRole), [.symbolCandidate, .symbolCandidate])
        XCTAssertEqual(rows.pageableRows.map(\.isNumberShortcutEligible), [true, true])
        XCTAssertEqual(CandidatePanelRowBuilder().defaultSelection(in: viewModel), .symbolCandidate(0))
    }

    func testPrefixSelectionUsesRawRangeShape() {
        let viewModel = CandidatePanelViewModel(
            rawInput: "nihao",
            prefixCandidates: [
                prefix("你好", rawRange: KnowTypeCore.TextRange(start: 0, length: 5)),
                prefix("好", rawRange: KnowTypeCore.TextRange(start: 2, length: 3))
            ],
            continuationCandidates: []
        )

        let rows = CandidatePanelRowBuilder().buildRows(in: viewModel)
        let selections: [CandidatePanelSelection?] = rows.pageableRows.map(\.selection)

        XCTAssertEqual(selections, [.fullCandidate(0), .segmentCandidate(1)])
        XCTAssertTrue(
            CandidatePanelRowBuilder().hasVisibleNumberShortcut(.fullCandidate(0), in: viewModel)
        )
        XCTAssertTrue(
            CandidatePanelRowBuilder().hasVisibleNumberShortcut(.segmentCandidate(1), in: viewModel)
        )
    }

    private func prefix(_ text: String, rawRange: KnowTypeCore.TextRange? = nil) -> CorrectionCandidate {
        CorrectionCandidate(
            text: text,
            source: "local",
            confidence: 1.0,
            correctionLevel: .contextual,
            rawRange: rawRange
        )
    }
}
