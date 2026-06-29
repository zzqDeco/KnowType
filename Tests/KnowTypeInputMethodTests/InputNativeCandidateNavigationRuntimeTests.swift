import KnowTypeAI
import KnowTypeCore
@testable import KnowTypeInputMethod
import XCTest

final class InputNativeCandidateNavigationRuntimeTests: XCTestCase {
    func testPanelSelectionMappingPreservesNativeIndexesAndAIRows() {
        let runtime = InputNativeCandidateNavigationRuntime()
        let viewModel = CandidatePanelViewModel(
            rawInput: "ni",
            prefixCandidates: [
                correction("你", source: ConversionCandidateSource.encode("rime-native", nativeIndex: 1)),
                correction("泥", source: ConversionCandidateSource.encode("rime-native", nativeIndex: 2)),
                correction("n", source: "local", rawRange: KnowTypeCore.TextRange(start: 0, length: 1))
            ],
            continuationCandidates: [
                ContinuationCandidate(text: "好", lengthLevel: .medium, confidence: 0.8, provider: "test")
            ],
            aiRecommendation: .ready(
                AIRecommendationCandidate(
                    prefixText: "你",
                    displayText: "你好",
                    confidence: 0.9,
                    provider: "test",
                    contextVersion: "v1"
                )
            )
        )

        XCTAssertEqual(
            runtime.inputCandidateSelection(for: .rawInput, in: viewModel),
            InputCandidateSelection(text: "ni", kind: .rawInput)
        )
        XCTAssertEqual(
            runtime.inputCandidateSelection(for: .prefixCandidate(0), in: viewModel),
            InputCandidateSelection(text: "你", kind: .prefixCandidate(index: 0), nativeCandidateIndex: 1)
        )
        XCTAssertEqual(
            runtime.inputCandidateSelection(for: .fullCandidate(1), in: viewModel),
            InputCandidateSelection(text: "泥", kind: .fullCandidate(index: 1), nativeCandidateIndex: 2)
        )
        XCTAssertEqual(
            runtime.inputCandidateSelection(for: .segmentCandidate(2), in: viewModel),
            InputCandidateSelection(text: "n", kind: .segmentCandidate(index: 2))
        )
        XCTAssertEqual(
            runtime.inputCandidateSelection(for: .continuationCandidate(0), in: viewModel),
            InputCandidateSelection(text: "好", kind: .continuationCandidate(index: 0))
        )
        XCTAssertEqual(
            runtime.inputCandidateSelection(for: .aiRecommendation, in: viewModel),
            InputCandidateSelection(text: "你好", kind: .aiRecommendation)
        )
    }

    func testDuplicateNativeCandidateTextRequiresStableSourceIndex() {
        let runtime = InputNativeCandidateNavigationRuntime()
        let recorder = TestNativeNavigationRecorder()
        var engine: any KnowTypeConversionEngine = TestNativeNavigationEngine(
            rawInput: "shi",
            pages: [["是", "是", "时"]],
            highlightedIndex: 0,
            recorder: recorder
        )

        XCTAssertNil(
            runtime.nativeCandidateIndex(
                for: InputCandidateSelection(text: "是", kind: .prefixCandidate(index: 0)),
                engine: engine
            )
        )
        XCTAssertEqual(
            runtime.nativeCandidateIndex(
                for: InputCandidateSelection(text: "是", kind: .prefixCandidate(index: 0), nativeCandidateIndex: 1),
                engine: engine
            ),
            1
        )

        let result = runtime.selectNativeCandidateIfNeeded(
            InputCandidateSelection(text: "是", kind: .prefixCandidate(index: 0), nativeCandidateIndex: 1),
            engine: &engine
        )
        XCTAssertTrue(result.handled)
        XCTAssertEqual(result.conversionResult?.commitText, "是")
        XCTAssertEqual(recorder.processedKeys, [.selectCandidateOnCurrentPage(1)])
    }

    func testHoverHighlightRefreshesPresentationWithoutCommit() {
        let runtime = InputNativeCandidateNavigationRuntime()
        let recorder = TestNativeNavigationRecorder()
        var engine: any KnowTypeConversionEngine = TestNativeNavigationEngine(
            rawInput: "ni",
            pages: [["你", "呢"]],
            highlightedIndex: 0,
            recorder: recorder
        )

        let result = runtime.highlightSelectionIfNeeded(
            InputCandidateSelection(text: "呢", kind: .prefixCandidate(index: 1), nativeCandidateIndex: 1),
            engine: &engine
        )

        XCTAssertTrue(result.handled)
        XCTAssertNil(result.conversionResult)
        XCTAssertEqual(
            result.effects,
            [InputNativeCandidateNavigationEffect.refreshNativeHighlightPresentation]
        )
        XCTAssertEqual(engine.snapshot.highlightedIndex, 1)
        XCTAssertEqual(recorder.processedKeys, [.highlightCandidateOnCurrentPage(1)])
    }

    func testPagingSymbolDoesNotConsumeWhenSnapshotDoesNotChange() {
        let runtime = InputNativeCandidateNavigationRuntime()
        let recorder = TestNativeNavigationRecorder()
        var engine: any KnowTypeConversionEngine = TestNativeNavigationEngine(
            rawInput: "ni",
            pages: [["你", "呢"]],
            highlightedIndex: 0,
            recorder: recorder
        )

        let result = runtime.moveNativeCandidatePage(
            forPagingSymbol: "=",
            rawInput: "ni",
            engine: &engine
        )

        XCTAssertFalse(result.handled)
        XCTAssertEqual(result.effects, [] as [InputNativeCandidateNavigationEffect])
        XCTAssertEqual(recorder.processedKeys, [.pageDown])
    }

    func testArrowNavigationPagesAtBoundaryAndHighlightsNewPageStartAndEnd() {
        let runtime = InputNativeCandidateNavigationRuntime()
        let recorder = TestNativeNavigationRecorder()
        var engine: any KnowTypeConversionEngine = TestNativeNavigationEngine(
            rawInput: "ni",
            pages: [["你", "呢"], ["尼", "泥"]],
            highlightedIndex: 1,
            recorder: recorder
        )

        let pageDown = runtime.moveNativeCandidateSelection(.down, rawInput: "ni", engine: &engine)

        XCTAssertTrue(pageDown.handled)
        XCTAssertEqual(
            pageDown.effects,
            [
                InputNativeCandidateNavigationEffect.publishLocalSuggestion,
                InputNativeCandidateNavigationEffect.refreshNativeHighlightPresentation
            ]
        )
        XCTAssertEqual(engine.snapshot.pageNumber, 1)
        XCTAssertEqual(engine.snapshot.highlightedIndex, 0)
        XCTAssertEqual(recorder.processedKeys, [.pageDown, .highlightCandidateOnCurrentPage(0)])

        recorder.processedKeys.removeAll()

        let pageUp = runtime.moveNativeCandidateSelection(.up, rawInput: "ni", engine: &engine)

        XCTAssertTrue(pageUp.handled)
        XCTAssertEqual(
            pageUp.effects,
            [
                InputNativeCandidateNavigationEffect.publishLocalSuggestion,
                InputNativeCandidateNavigationEffect.refreshNativeHighlightPresentation
            ]
        )
        XCTAssertEqual(engine.snapshot.pageNumber, 0)
        XCTAssertEqual(engine.snapshot.highlightedIndex, 1)
        XCTAssertEqual(recorder.processedKeys, [.pageUp, .highlightCandidateOnCurrentPage(1)])
    }

    func testHiddenPanelNumberSelectionConsumesOutOfRangeWithoutAppending() {
        let runtime = InputNativeCandidateNavigationRuntime()
        let recorder = TestNativeNavigationRecorder()
        var engine: any KnowTypeConversionEngine = TestNativeNavigationEngine(
            rawInput: "ni",
            pages: [["你", "呢"]],
            highlightedIndex: 0,
            recorder: recorder
        )

        let result = runtime.selectCandidateOnCurrentPage(9, engine: &engine)

        XCTAssertTrue(result.handled)
        XCTAssertNil(result.conversionResult)
        XCTAssertEqual(recorder.processedKeys, [])
    }

    func testPreferredNativeHighlightUsesCurrentNativeSnapshot() {
        let runtime = InputNativeCandidateNavigationRuntime()
        let engine = TestNativeNavigationEngine(
            rawInput: "ni",
            pages: [["你", "呢"]],
            highlightedIndex: 1
        )
        let suggestion = SuggestionResponse(
            prefixCandidates: [
                correction(
                    "你",
                    source: ConversionCandidateSource.encode("rime-native", nativeIndex: 0),
                    rawRange: KnowTypeCore.TextRange(start: 0, length: 2)
                ),
                correction(
                    "呢",
                    source: ConversionCandidateSource.encode("rime-native", nativeIndex: 1),
                    rawRange: KnowTypeCore.TextRange(start: 0, length: 1)
                )
            ],
            lockedPrefix: nil,
            continuationCandidates: [],
            latencyMs: 1
        )

        XCTAssertEqual(
            runtime.nativeHighlightedSelection(suggestion: suggestion, rawInput: "ni", engine: engine),
            .segmentCandidate(1)
        )
    }

    private func correction(
        _ text: String,
        source: String,
        rawRange: KnowTypeCore.TextRange? = nil
    ) -> CorrectionCandidate {
        CorrectionCandidate(
            text: text,
            source: source,
            confidence: 1,
            correctionLevel: .contextual,
            rawRange: rawRange
        )
    }
}

private final class TestNativeNavigationRecorder: @unchecked Sendable {
    var processedKeys: [ConversionEngineKey] = []
}

private struct TestNativeNavigationEngine: KnowTypeConversionEngine {
    var isNativeActive = true
    let recorder: TestNativeNavigationRecorder
    private var rawInput: String
    private var pages: [[String]]
    private var currentPage: Int
    private var highlightedIndex: Int

    init(
        rawInput: String,
        pages: [[String]],
        currentPage: Int = 0,
        highlightedIndex: Int = 0,
        recorder: TestNativeNavigationRecorder = TestNativeNavigationRecorder()
    ) {
        self.rawInput = rawInput
        self.pages = pages
        self.currentPage = currentPage
        self.highlightedIndex = highlightedIndex
        self.recorder = recorder
    }

    var snapshot: ConversionEngineSnapshot {
        makeSnapshot()
    }

    mutating func reset() {
        rawInput = ""
        currentPage = 0
        highlightedIndex = 0
    }

    mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        recorder.processedKeys.append(key)
        switch key {
        case .selectCandidateOnCurrentPage(let index), .selectCandidate(let index):
            guard currentCandidates.indices.contains(index) else {
                return ConversionEngineResult(handled: false, snapshot: snapshot)
            }
            let commit = currentCandidates[index]
            return ConversionEngineResult(handled: true, commitText: commit, snapshot: snapshot)
        case .highlightCandidateOnCurrentPage(let index):
            guard currentCandidates.indices.contains(index) else {
                return ConversionEngineResult(handled: false, snapshot: snapshot)
            }
            highlightedIndex = index
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .pageDown:
            guard currentPage < pages.count - 1 else {
                return ConversionEngineResult(handled: true, snapshot: snapshot)
            }
            currentPage += 1
            highlightedIndex = 0
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .pageUp:
            guard currentPage > 0 else {
                return ConversionEngineResult(handled: true, snapshot: snapshot)
            }
            currentPage -= 1
            highlightedIndex = 0
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .text(let text):
            rawInput += text
            currentPage = 0
            highlightedIndex = 0
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .deleteBackward:
            if !rawInput.isEmpty {
                rawInput.removeLast()
            }
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .space, .commitComposition:
            guard currentCandidates.indices.contains(highlightedIndex) else {
                return ConversionEngineResult(handled: false, snapshot: snapshot)
            }
            return ConversionEngineResult(
                handled: true,
                commitText: currentCandidates[highlightedIndex],
                snapshot: snapshot
            )
        }
    }

    private var currentCandidates: [String] {
        guard pages.indices.contains(currentPage) else {
            return []
        }
        return pages[currentPage]
    }

    private func makeSnapshot() -> ConversionEngineSnapshot {
        guard !rawInput.isEmpty else {
            return ConversionEngineSnapshot(engineName: "native-navigation-test")
        }
        return ConversionEngineSnapshot(
            rawInput: rawInput,
            preedit: rawInput,
            candidates: currentCandidates.enumerated().map { index, text in
                ConversionEngineCandidate(
                    text: text,
                    index: index,
                    source: ConversionCandidateSource.encode("native-navigation-test", nativeIndex: index)
                )
            },
            highlightedIndex: highlightedIndex,
            pageSize: max(currentCandidates.count, 1),
            pageNumber: currentPage,
            isLastPage: currentPage >= pages.count - 1,
            engineName: "native-navigation-test"
        )
    }
}
