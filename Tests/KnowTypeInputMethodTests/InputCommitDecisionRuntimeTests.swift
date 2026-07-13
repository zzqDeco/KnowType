import XCTest
import KnowTypeAI
import KnowTypeCore
@testable import KnowTypeInputMethod

final class InputCommitDecisionRuntimeTests: XCTestCase {
    private let runtime = InputCommitDecisionRuntime()

    func testIdleSpaceUsesDirectPassthroughPlan() {
        let context = makeContext(action: .space, rawInput: "", hasActiveTextComposition: false)

        XCTAssertEqual(runtime.commitPlan(context: context), .directPassthroughSpace)
    }

    func testCommitRawWithoutCompositionFinishesEmptyLifecycle() {
        let context = makeContext(action: .commitRaw, rawInput: "", hasActiveTextComposition: false)

        XCTAssertEqual(runtime.commitPlan(context: context), .finishEmptyRawCommit)
    }

    func testTabReadyAICommitsBeforeContinuationPolicy() {
        let ready = readyAI("AI 续写")
        let context = makeContext(
            action: .tab,
            rawInput: "ni",
            suggestion: suggestion(prefixes: [candidate("你")], continuations: [continuation("继续")]),
            aiRecommendationState: ready
        )

        XCTAssertEqual(runtime.resultPlan(context: context), .result(.commit("AI 续写")))
    }

    func testTabPendingAIFallsThroughToVisibleContinuation() {
        let context = makeContext(
            action: .tab,
            rawInput: "ni",
            suggestion: suggestion(prefixes: [candidate("你")], continuations: [continuation("继续")]),
            aiRecommendationState: .pending(requestID: UUID())
        )

        XCTAssertEqual(runtime.resultPlan(context: context), .result(.commit("你继续")))
    }

    func testTabSuppressesPartialComposition() {
        var buffer = CompositionBuffer()
        buffer.updateRawInput("nishi")
        buffer.apply(candidate("你", rawRange: KnowTypeCore.TextRange(start: 0, length: 2)))
        let context = makeContext(
            action: .tab,
            rawInput: "nishi",
            compositionBuffer: buffer,
            suggestion: suggestion(prefixes: [candidate("你是")], continuations: [continuation("继续")])
        )

        XCTAssertEqual(runtime.resultPlan(context: context), .result(.noAction))
    }

    func testTabWithoutVisibleContinuationIsNoActionWhenAsyncRefreshIsEnabled() {
        let context = makeContext(
            action: .tab,
            rawInput: "ni",
            suggestion: suggestion(prefixes: [candidate("你")], continuations: []),
            enablesAsyncSuggestionRefresh: true
        )

        XCTAssertEqual(runtime.resultPlan(context: context), .result(.noAction))
    }

    func testFullyResolvedCompositionTabCommitsContinuation() {
        var buffer = CompositionBuffer()
        buffer.updateRawInput("ni")
        buffer.apply(candidate("你", rawRange: KnowTypeCore.TextRange(start: 0, length: 2)))
        let context = makeContext(
            action: .tab,
            rawInput: "ni",
            compositionBuffer: buffer,
            suggestion: suggestion(prefixes: [candidate("你")], continuations: [continuation("继续")])
        )

        XCTAssertEqual(runtime.resultPlan(context: context), .result(.commit("你继续")))
    }

    func testSpaceSelectedAIRowCommitsReadyRecommendation() {
        let context = makeContext(
            action: .space,
            rawInput: "ni",
            selectedCandidate: InputCandidateSelection(text: "AI 续写", kind: .aiRecommendation),
            aiRecommendationState: readyAI("AI 续写")
        )

        XCTAssertEqual(runtime.resultPlan(context: context), .result(.commit("AI 续写")))
    }

    func testSpaceSelectedSegmentRequestsSegmentApplication() {
        let context = makeContext(
            action: .space,
            rawInput: "nishi",
            selectedCandidate: InputCandidateSelection(text: "你", kind: .segmentCandidate(index: 0))
        )

        XCTAssertEqual(
            runtime.resultPlan(context: context),
            .applySegmentCandidate(index: 0, commitIfFullyResolved: true)
        )
    }

    func testSpaceSelectedContinuationUsesSessionCommitPolicy() {
        let context = makeContext(
            action: .space,
            rawInput: "ni",
            suggestion: suggestion(prefixes: [candidate("你")], continuations: [continuation("继续")]),
            selectedCandidate: InputCandidateSelection(text: "继续", kind: .continuationCandidate(index: 0))
        )

        XCTAssertEqual(runtime.resultPlan(context: context), .result(.commit("你继续")))
    }

    func testSpaceNativeSelectedPrefixWithKnownIndexSelectsBeforeSpace() {
        let selected = InputCandidateSelection(text: "你", kind: .fullCandidate(index: 0), nativeCandidateIndex: 0)
        let context = makeContext(
            action: .space,
            rawInput: "ni",
            selectedCandidate: selected,
            isNativeActive: true,
            selectedCandidateShouldSelectBeforeSpace: true,
            selectedCandidateHasNativeIndex: true
        )

        XCTAssertEqual(runtime.commitPlan(context: context), .selectNativeCandidateBeforeSpace(selected))
    }

    func testSpaceNativeSelectedPrefixWithoutStableIndexFallsBackToNumberSelection() {
        let selected = InputCandidateSelection(text: "你", kind: .fullCandidate(index: 0))
        let context = makeContext(
            action: .space,
            rawInput: "ni",
            suggestion: suggestion(prefixes: [candidate("你")], continuations: []),
            selectedCandidate: selected,
            isNativeActive: true,
            selectedCandidateShouldSelectBeforeSpace: false,
            selectedCandidateHasNativeIndex: false
        )

        XCTAssertEqual(runtime.resultPlan(context: context), .selectNativeCandidateForCommit(selected))
    }

    func testOptionOneOnlyAcceptsReadyAI() {
        let idleContext = makeContext(action: .optionNumber(1), rawInput: "ni", aiRecommendationState: .idle)
        let readyContext = makeContext(
            action: .optionNumber(1),
            rawInput: "ni",
            aiRecommendationState: readyAI("AI 续写")
        )

        XCTAssertEqual(runtime.resultPlan(context: idleContext), .result(.noAction))
        XCTAssertEqual(runtime.resultPlan(context: readyContext), .result(.commit("AI 续写")))
    }

    func testNumberSelectionPlansRawAIAndNativeRows() {
        let raw = InputCandidateSelection(text: "ni", kind: .rawInput)
        let ai = InputCandidateSelection(text: "AI 续写", kind: .aiRecommendation)
        let native = InputCandidateSelection(text: "你", kind: .fullCandidate(index: 0), nativeCandidateIndex: 0)
        let context = makeContext(
            action: .space,
            rawInput: "ni",
            aiRecommendationState: readyAI("AI 续写"),
            isNativeActive: true
        )

        XCTAssertEqual(runtime.numberSelectionPlan(selection: raw, context: context), .result(.commit("ni")))
        XCTAssertEqual(runtime.numberSelectionPlan(selection: ai, context: context), .result(.commit("AI 续写")))
        XCTAssertEqual(runtime.numberSelectionPlan(selection: native, context: context), .selectNativeCandidateForCommit(native))
    }

    func testPrefixLearningDecisionSkipsAIAndUsesPrefixOrContinuationSource() {
        let suggestion = suggestion(prefixes: [candidate("你"), candidate("泥")], continuations: [continuation("继续")])

        XCTAssertTrue(runtime.shouldSkipPrefixLearning(action: .tab, aiRecommendationState: readyAI("AI 续写")))
        XCTAssertNil(
            runtime.selectedPrefixTextForLearning(
                selectedCandidate: InputCandidateSelection(text: "AI 续写", kind: .aiRecommendation),
                panelSelection: nil,
                suggestion: suggestion
            )
        )
        XCTAssertEqual(
            runtime.selectedPrefixTextForLearning(
                selectedCandidate: InputCandidateSelection(text: "泥", kind: .prefixCandidate(index: 1)),
                panelSelection: nil,
                suggestion: suggestion
            ),
            "泥"
        )
        XCTAssertEqual(
            runtime.selectedPrefixTextForLearning(
                selectedCandidate: InputCandidateSelection(text: "继续", kind: .continuationCandidate(index: 0)),
                panelSelection: nil,
                suggestion: suggestion
            ),
            "你"
        )
    }

    private func makeContext(
        action: InputAction,
        rawInput: String,
        compositionBuffer: CompositionBuffer? = nil,
        suggestion: SuggestionResponse? = nil,
        selectedCandidate: InputCandidateSelection? = nil,
        panelSelection: CandidatePanelSelection? = nil,
        panelIsVisible: Bool = true,
        aiRecommendationState: AIRecommendationState = .idle,
        hasActiveTextComposition: Bool? = nil,
        enablesAsyncSuggestionRefresh: Bool = true,
        isNativeActive: Bool = false,
        selectedCandidateShouldSelectBeforeSpace: Bool = false,
        selectedCandidateHasNativeIndex: Bool = false
    ) -> InputCommitDecisionContext {
        var buffer = compositionBuffer ?? CompositionBuffer()
        if compositionBuffer == nil {
            buffer.updateRawInput(rawInput)
        }
        let suggestionSnapshot = InputSuggestionStateSnapshot(suggestion: suggestion, rawInput: suggestion == nil ? nil : rawInput)
        return InputCommitDecisionContext(
            action: action,
            rawInput: rawInput,
            compositionBuffer: buffer,
            suggestionSnapshot: suggestionSnapshot,
            commitSuggestionSnapshot: InputSuggestionCommitSnapshot(
                suggestion: suggestion,
                rawInput: suggestion == nil ? nil : rawInput,
                usesPendingFallback: false
            ),
            selectedCandidate: selectedCandidate,
            panelSelection: panelSelection,
            panelIsVisible: panelIsVisible,
            aiRecommendationState: aiRecommendationState,
            hasActiveTextComposition: hasActiveTextComposition ?? !rawInput.isEmpty,
            enablesAsyncSuggestionRefresh: enablesAsyncSuggestionRefresh,
            isNativeActive: isNativeActive,
            selectedCandidateShouldSelectBeforeSpace: selectedCandidateShouldSelectBeforeSpace,
            selectedCandidateHasNativeIndex: selectedCandidateHasNativeIndex,
            appBundleID: "com.example.Editor",
            locale: .mixed,
            runtimePreferences: .standard
        )
    }

    private func suggestion(
        prefixes: [CorrectionCandidate],
        continuations: [ContinuationCandidate]
    ) -> SuggestionResponse {
        SuggestionResponse(
            prefixCandidates: prefixes,
            lockedPrefix: prefixes.first.map {
                LockedPrefix(text: $0.text, rawInput: "ni", candidateID: $0.source)
            },
            continuationCandidates: continuations,
            latencyMs: 0
        )
    }

    private func candidate(
        _ text: String,
        rawRange: KnowTypeCore.TextRange? = KnowTypeCore.TextRange(start: 0, length: 2),
        source: String = "rime:0"
    ) -> CorrectionCandidate {
        CorrectionCandidate(
            text: text,
            source: source,
            confidence: 1,
            correctionLevel: .contextual,
            rawRange: rawRange
        )
    }

    private func continuation(_ text: String) -> ContinuationCandidate {
        ContinuationCandidate(
            text: text,
            lengthLevel: .medium,
            confidence: 1,
            provider: "test"
        )
    }

    private func readyAI(_ text: String) -> AIRecommendationState {
        .ready(
            AIRecommendationCandidate(
                prefixText: "",
                continuationText: text,
                displayText: text,
                confidence: 1,
                provider: "test",
                contextVersion: "test"
            )
        )
    }
}
