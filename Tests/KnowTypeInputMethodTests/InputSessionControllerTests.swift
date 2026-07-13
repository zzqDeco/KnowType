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

private actor ThrowingRecordingProvider: LLMProvider {
    nonisolated let providerName = "throwing"
    private var recordedRequests: [LLMRequest] = []

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        recordedRequests.append(request)
        throw NSError(domain: "KnowTypeTests", code: 1)
    }

    var requests: [LLMRequest] {
        recordedRequests
    }
}

private actor ManualSuggestionLoader {
    private var continuations: [String: CheckedContinuation<SuggestionResponse, Never>] = [:]

    func load(_ context: InputContext) async -> SuggestionResponse {
        await withCheckedContinuation { continuation in
            continuations[context.rawInput] = continuation
        }
    }

    func resume(rawInput: String, with suggestion: SuggestionResponse) {
        continuations.removeValue(forKey: rawInput)?.resume(returning: suggestion)
    }

    func hasPending(rawInput: String) -> Bool {
        continuations[rawInput] != nil
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
        XCTAssertEqual(state.mode, .candidate)
        XCTAssertEqual(state.rawInput, "wo jue de zhege fagnan")
        XCTAssertEqual(state.latestSuggestion, expected)
        XCTAssertEqual(state.latestSuggestionRawInput, "wo jue de zhege fagnan")
        XCTAssertEqual(state.selectedPrefixIndex, 0)
        XCTAssertNil(state.selectedContinuationIndex)
    }

    func testUpdatePassesUserSelectionHistoryToSuggestionLoader() async {
        let controller = InputSessionController { context in
            XCTAssertEqual(context.userSelectionHistory, ["方法", "方向"])
            return Self.makeSuggestion()
        }

        _ = await controller.update(
            rawInput: "fangan",
            locale: .zhCN,
            userSelectionHistory: ["方法", "方向"]
        )
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

    func testSelectedNonFirstPrefixDoesNotReuseFirstPrefixContinuations() async {
        let controller = InputSessionController { _ in
            Self.makeSuggestion()
        }
        await controller.update(rawInput: "wo jue de zhege fagnan")
        await controller.selectPrefix(index: 1)

        let tabResult = await controller.handle(action: .tab)
        let optionResult = await controller.handle(action: .optionNumber(1))

        XCTAssertEqual(tabResult, .commit("我觉得这个方法"))
        XCTAssertEqual(optionResult, .commit("我觉得这个方法"))
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

    func testOptionNumberCommitsRequestedContinuation() async {
        let controller = InputSessionController { _ in
            Self.makeSuggestion()
        }
        await controller.update(rawInput: "wo jue de zhege fagnan")

        let continuationResult = await controller.handle(action: .optionNumber(1))
        let secondContinuationResult = await controller.handle(action: .optionNumber(2))
        let state = await controller.state

        XCTAssertEqual(continuationResult, .commit("我觉得这个方案还有进一步优化空间"))
        XCTAssertEqual(secondContinuationResult, .commit("我觉得这个方案在落地成本上可能偏高"))
        XCTAssertEqual(state.selectedContinuationIndex, 1)
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

        XCTAssertEqual(spaceResult, .noAction)
        XCTAssertEqual(tabResult, .noAction)
        XCTAssertEqual(optionNumberResult, .noAction)
        XCTAssertEqual(optionZeroResult, .noAction)
    }

    func testCommitPolicyCanAvoidSynchronousFallbackWhileSuggestionIsPending() {
        let result = InputSessionCommitPolicy.result(
            for: .space,
            rawInput: "wojue",
            suggestion: nil,
            suggestionRawInput: nil,
            locale: .zhCN,
            traditionalInputEngine: TraditionalInputEngine(),
            allowsSynchronousFallback: false
        )

        XCTAssertEqual(result, .noAction)
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
        let state = await controller.state
        XCTAssertEqual(state.mode, .ascii)

        let tabResult = await controller.handle(action: .tab)
        XCTAssertEqual(tabResult, .commit("/Users/zq/project/KnowType"))
    }

    func testProtectedAppBundleClearsContinuationsAndDoesNotCallProvider() async {
        let provider = RecordingProvider()
        let controller = InputSessionController(provider: provider)

        let suggestion = await controller.update(
            rawInput: "wo jue de zhege fagnan",
            appBundleID: "com.apple.dt.Xcode",
            locale: .zhCN
        )
        let requests = await provider.requests

        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(suggestion.prefixCandidates.first?.text, "wo jue de zhege fagnan")
        XCTAssertEqual(suggestion.prefixCandidates.first?.source, "local-protection")
        XCTAssertTrue(suggestion.continuationCandidates.isEmpty)
    }

    func testLevelZeroURLAndCommandInputsClearContinuationsAndDoNotCallProvider() async {
        let provider = RecordingProvider()
        let controller = InputSessionController(provider: provider)

        let urlSuggestion = await controller.update(
            rawInput: "https://example.com/path?q=KnowType",
            locale: .mixed
        )
        let commandSuggestion = await controller.update(
            rawInput: "swift test",
            locale: .mixed
        )
        let requests = await provider.requests

        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(urlSuggestion.continuationCandidates.isEmpty)
        XCTAssertEqual(urlSuggestion.prefixCandidates.first?.text, "https://example.com/path?q=KnowType")
        XCTAssertTrue(commandSuggestion.continuationCandidates.isEmpty)
        XCTAssertEqual(commandSuggestion.prefixCandidates.first?.text, "swift test")
    }

    func testPipelineLevelZeroSkipsCorrectionButCanAskProviderForContinuation() async {
        let provider = RecordingProvider()
        let pipeline = SessionSuggestionPipeline(provider: provider)

        let suggestion = await pipeline.suggestions(
            for: InputContext(
                rawInput: "dev@example.com",
                appBundleID: "com.googlecode.iterm2",
                locale: .mixed
            )
        )
        let requests = await provider.requests

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.task, .continuation)
        XCTAssertEqual(suggestion.prefixCandidates.first?.source, "local-protection")
        XCTAssertFalse(suggestion.continuationCandidates.isEmpty)
    }

    func testProviderFailureDoesNotBlockLocalPrefixSubmission() async {
        let provider = ThrowingRecordingProvider()
        let controller = InputSessionController(provider: provider)

        let suggestion = await controller.update(
            rawInput: "wo jue de zhege fagnan",
            appBundleID: nil,
            locale: .zhCN
        )
        let result = await controller.handle(action: .space)
        let requests = await provider.requests

        XCTAssertFalse(requests.isEmpty)
        XCTAssertEqual(suggestion.prefixCandidates.first?.text, "我觉得这个方案")
        XCTAssertTrue(suggestion.continuationCandidates.isEmpty)
        XCTAssertEqual(result, .commit("我觉得这个方案"))
    }

    func testStaleUpdateCannotOverwriteNewerInputState() async throws {
        let loader = ManualSuggestionLoader()
        let controller = InputSessionController { context in
            await loader.load(context)
        }

        async let first = controller.update(rawInput: "first")
        while await !loader.hasPending(rawInput: "first") {
            try await Task.sleep(for: .milliseconds(1))
        }

        async let second = controller.update(rawInput: "second")
        while await !loader.hasPending(rawInput: "second") {
            try await Task.sleep(for: .milliseconds(1))
        }

        let secondSuggestion = Self.makeSuggestion(prefixes: [
            CorrectionCandidate(
                text: "second prefix",
                source: "test",
                confidence: 1.0,
                correctionLevel: .light
            )
        ])
        let firstSuggestion = Self.makeSuggestion(prefixes: [
            CorrectionCandidate(
                text: "first prefix",
                source: "test",
                confidence: 1.0,
                correctionLevel: .light
            )
        ])

        await loader.resume(rawInput: "second", with: secondSuggestion)
        _ = await second
        await loader.resume(rawInput: "first", with: firstSuggestion)
        _ = await first

        let state = await controller.state
        XCTAssertEqual(state.mode, .candidate)
        XCTAssertEqual(state.rawInput, "second")
        XCTAssertEqual(state.latestSuggestion?.prefixCandidates.first?.text, "second prefix")
    }

    func testPendingUpdateUsesAIPendingModeUntilLatestSuggestionPublishes() async throws {
        let loader = ManualSuggestionLoader()
        let controller = InputSessionController { context in
            await loader.load(context)
        }

        async let update = controller.update(rawInput: "wo jue de zhege fagnan")
        while await !loader.hasPending(rawInput: "wo jue de zhege fagnan") {
            try await Task.sleep(for: .milliseconds(1))
        }

        var state = await controller.state
        XCTAssertEqual(state.mode, .aiPending)
        XCTAssertEqual(state.rawInput, "wo jue de zhege fagnan")
        XCTAssertNil(state.latestSuggestion)
        let pendingCommitResult = await controller.handle(action: .space)
        XCTAssertEqual(pendingCommitResult, .noAction)

        await loader.resume(rawInput: "wo jue de zhege fagnan", with: Self.makeSuggestion())
        _ = await update

        state = await controller.state
        XCTAssertEqual(state.mode, .candidate)
    }

    func testNonEmptySuggestionWithoutCandidatesUsesComposingMode() async {
        let controller = InputSessionController { _ in
            Self.makeSuggestion(prefixes: [], continuations: [])
        }

        await controller.update(rawInput: "x")
        let state = await controller.state

        XCTAssertEqual(state.mode, .composing)
        XCTAssertEqual(state.rawInput, "x")
    }

    func testResetClearsExplicitSessionMode() async {
        let controller = InputSessionController { _ in
            Self.makeSuggestion()
        }
        await controller.update(rawInput: "wo jue de zhege fagnan")

        await controller.reset()
        let state = await controller.state

        XCTAssertEqual(state.mode, .empty)
        XCTAssertEqual(state.rawInput, "")
        XCTAssertNil(state.latestSuggestion)
    }

    func testSessionCommitPolicyHandlesNativeCandidateSelectionAndFallbacks() {
        let suggestion = Self.makeSuggestion()

        let selectedPrefix = InputSessionCommitPolicy.result(
            for: .tab,
            rawInput: "wo jue de zhege fagnan",
            suggestion: suggestion,
            suggestionRawInput: "wo jue de zhege fagnan",
            selectedCandidate: .prefixCandidate(index: 1),
            locale: .zhCN
        )
        let selectedContinuation = InputSessionCommitPolicy.result(
            for: .space,
            rawInput: "wo jue de zhege fagnan",
            suggestion: suggestion,
            suggestionRawInput: "wo jue de zhege fagnan",
            selectedCandidate: .continuationCandidate(index: 1),
            locale: .zhCN
        )
        let staleFallback = InputSessionCommitPolicy.result(
            for: .space,
            rawInput: "wo jue de zhege fagnan",
            suggestion: suggestion,
            suggestionRawInput: "stale",
            locale: .zhCN,
            traditionalInputEngine: TraditionalInputEngine()
        )

        XCTAssertEqual(selectedPrefix, .commit("我觉得这个方法"))
        XCTAssertEqual(selectedContinuation, .commit("我觉得这个方案在落地成本上可能偏高"))
        XCTAssertEqual(staleFallback, .commit("我觉得这个方案"))
    }

    func testCandidateNumberPolicyMatchesNativeNumberSelectionRules() {
        let suggestion = Self.makeSuggestion()

        let rawResult = InputSessionCommitPolicy.resultForCandidateNumber(
            0,
            rawInput: "wo jue de zhege fagnan",
            suggestion: suggestion,
            suggestionRawInput: "wo jue de zhege fagnan"
        )
        let prefixResult = InputSessionCommitPolicy.resultForCandidateNumber(
            2,
            rawInput: "wo jue de zhege fagnan",
            suggestion: suggestion,
            suggestionRawInput: "wo jue de zhege fagnan"
        )
        let staleResult = InputSessionCommitPolicy.resultForCandidateNumber(
            1,
            rawInput: "wo jue de zhege fagnan",
            suggestion: suggestion,
            suggestionRawInput: "stale"
        )

        XCTAssertEqual(rawResult, .commit("wo jue de zhege fagnan"))
        XCTAssertEqual(prefixResult, .commit("我觉得这个方法"))
        XCTAssertNil(staleResult)
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
