import XCTest
import KnowTypeCore
@testable import KnowTypeInputMethod

private actor RecordingProvider: LLMProvider {
    nonisolated let providerName = "recording"
    private var recordedRequests: [LLMRequest] = []

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        recordedRequests.append(request)
        return LLMResponse(candidates: [
            LLMCandidate(text: "should not be used", confidence: 1.0)
        ])
    }

    var requests: [LLMRequest] {
        recordedRequests
    }
}

final class InputSessionControllerTests: XCTestCase {
    func testRawInputUpdateStoresSuggestionsAndResetsSelection() async {
        let expected = Self.makeSuggestion()
        let controller = InputSessionController { context in
            XCTAssertEqual(context.rawInput, "wo jue de zhege fagnan")
            XCTAssertEqual(context.appBundleID, "com.example.Editor")
            XCTAssertEqual(context.locale, .zhCN)
            return expected
        }

        let suggestion = await controller.update(
            rawInput: "wo jue de zhege fagnan",
            appBundleID: "com.example.Editor",
            locale: .zhCN
        )
        let state = await controller.state

        XCTAssertEqual(suggestion, expected)
        XCTAssertEqual(state.rawInput, "wo jue de zhege fagnan")
        XCTAssertEqual(state.latestSuggestion, expected)
        XCTAssertEqual(state.selectedPrefixIndex, 0)
        XCTAssertNil(state.selectedContinuationIndex)
        XCTAssertFalse(state.polishRequested)
    }

    func testPrefixSelectionUsesSelectedPrefixAndChecksBounds() async {
        let controller = InputSessionController { _ in
            Self.makeSuggestion()
        }
        await controller.update(rawInput: "wo jue de zhege fagnan")

        let negativeSelection = await controller.selectPrefix(index: -1)
        let outOfBoundsSelection = await controller.selectPrefix(index: 99)
        let validSelection = await controller.selectPrefix(index: 1)

        let result = await controller.handle(action: .space)
        let state = await controller.state

        XCTAssertFalse(negativeSelection)
        XCTAssertFalse(outOfBoundsSelection)
        XCTAssertTrue(validSelection)
        XCTAssertEqual(result, .commit("我觉得这个方法"))
        XCTAssertEqual(state.selectedPrefixIndex, 1)
    }

    func testContinuationSelectionUsesSelectedContinuationAndChecksBounds() async {
        let controller = InputSessionController { _ in
            Self.makeSuggestion()
        }
        await controller.update(rawInput: "wo jue de zhege fagnan")

        let negativeSelection = await controller.selectContinuation(index: -1)
        let outOfBoundsSelection = await controller.selectContinuation(index: 99)
        let validSelection = await controller.selectContinuation(index: 1)

        let result = await controller.handle(action: .tab)
        let state = await controller.state

        XCTAssertFalse(negativeSelection)
        XCTAssertFalse(outOfBoundsSelection)
        XCTAssertTrue(validSelection)
        XCTAssertEqual(result, .commit("我觉得这个方案在落地成本上可能偏高"))
        XCTAssertEqual(state.selectedContinuationIndex, 1)
    }

    func testOptionNumberCommitsRequestedContinuationAndOptionRMarksPolishRequested() async {
        let controller = InputSessionController { _ in
            Self.makeSuggestion()
        }
        await controller.update(rawInput: "wo jue de zhege fagnan")

        let continuationResult = await controller.handle(action: .optionNumber(1))
        var state = await controller.state

        XCTAssertEqual(continuationResult, .commit("我觉得这个方案在落地成本上可能偏高"))
        XCTAssertEqual(state.selectedContinuationIndex, 1)
        XCTAssertFalse(state.polishRequested)

        let polishResult = await controller.handle(action: .optionR)
        state = await controller.state

        XCTAssertEqual(polishResult, .polishRequested("wo jue de zhege fagnan"))
        XCTAssertTrue(state.polishRequested)
    }

    func testEmptyStateReturnsNoAction() async {
        let controller = InputSessionController { _ in
            Self.makeSuggestion(prefixes: [], continuations: [])
        }

        let noSuggestionResult = await controller.handle(action: .space)
        XCTAssertEqual(noSuggestionResult, .noAction)

        await controller.update(rawInput: "")

        let spaceResult = await controller.handle(action: .space)
        let tabResult = await controller.handle(action: .tab)
        let optionNumberResult = await controller.handle(action: .optionNumber(1))
        let optionZeroResult = await controller.handle(action: .optionNumber(0))
        let optionRResult = await controller.handle(action: .optionR)

        XCTAssertEqual(spaceResult, .noAction)
        XCTAssertEqual(tabResult, .noAction)
        XCTAssertEqual(optionNumberResult, .noAction)
        XCTAssertEqual(optionZeroResult, .noAction)
        XCTAssertEqual(optionRResult, .noAction)
    }

    func testLevelZeroInputUsesNoProviderPath() async {
        let provider = RecordingProvider()
        let controller = InputSessionController(provider: provider)

        let suggestion = await controller.update(
            rawInput: "/Users/zq/project/KnowType",
            appBundleID: nil,
            locale: .mixed
        )
        let requests = await provider.requests

        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(suggestion.prefixCandidates.first?.text, "/Users/zq/project/KnowType")
        XCTAssertEqual(suggestion.prefixCandidates.first?.source, "local-protection")
        XCTAssertEqual(suggestion.prefixCandidates.first?.correctionLevel, CorrectionLevel.none)
        XCTAssertTrue(suggestion.continuationCandidates.isEmpty)

        let tabResult = await controller.handle(action: .tab)
        XCTAssertEqual(tabResult, .commit("/Users/zq/project/KnowType"))
    }

    private static func makeSuggestion(
        prefixes: [CorrectionCandidate]? = nil,
        continuations: [ContinuationCandidate]? = nil
    ) -> SuggestionResponse {
        let prefixCandidates = prefixes ?? [
            CorrectionCandidate(
                text: "我觉得这个方案",
                source: "test",
                confidence: 1.0,
                correctionLevel: .contextual
            ),
            CorrectionCandidate(
                text: "我觉得这个方法",
                source: "test",
                confidence: 0.8,
                correctionLevel: .contextual
            )
        ]
        return SuggestionResponse(
            prefixCandidates: prefixCandidates,
            lockedPrefix: prefixCandidates.first.map {
                LockedPrefix(
                    text: $0.text,
                    rawInput: "wo jue de zhege fagnan",
                    candidateID: $0.source
                )
            },
            continuationCandidates: continuations ?? [
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
            ],
            latencyMs: 1
        )
    }
}
