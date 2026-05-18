import XCTest
import KnowTypeCore
@testable import KnowTypeInputMethod

final class MVPAcceptanceTests: XCTestCase {
    func testChineseCorrectionAndTabContinuationFlow() async {
        let pipeline = InputMethodPipeline()
        let response = await pipeline.suggestions(
            for: InputContext(rawInput: "wo jue de zhege fagnan", locale: .zhCN)
        )
        let controller = InputCompositionController()
        let result = controller.handle(
            action: .tab,
            prefixCandidates: response.prefixCandidates,
            continuationCandidates: response.continuationCandidates,
            originalText: "wo jue de zhege fagnan"
        )

        XCTAssertEqual(response.lockedPrefix?.text, "我觉得这个方案")
        XCTAssertEqual(result, .commit("我觉得这个方案还有进一步优化空间"))
    }

    func testChineseCorrectionSupportsContinuousPinyinInput() async {
        let pipeline = InputMethodPipeline()
        let response = await pipeline.suggestions(
            for: InputContext(rawInput: "wojuedezhegefagnan", locale: .zhCN)
        )
        let controller = InputCompositionController()
        let result = controller.handle(
            action: .space,
            prefixCandidates: response.prefixCandidates,
            continuationCandidates: response.continuationCandidates,
            originalText: "wojuedezhegefagnan"
        )

        XCTAssertEqual(response.lockedPrefix?.text, "我觉得这个方案")
        XCTAssertEqual(result, .commit("我觉得这个方案"))
    }

    func testLocalImmediateSuggestionsCanDeferContinuationsWhenProviderIsConfigured() {
        let response = InputMethodPipeline.localSuggestions(
            for: InputContext(rawInput: "wo jue de zhege fagnan", locale: .zhCN),
            includeFallbackContinuations: false
        )

        XCTAssertEqual(response.lockedPrefix?.text, "我觉得这个方案")
        XCTAssertFalse(response.prefixCandidates.isEmpty)
        XCTAssertTrue(response.continuationCandidates.isEmpty)
    }

    func testRuntimePreferencesCanDisableLocalFallbackContinuations() {
        let response = InputMethodPipeline.localSuggestions(
            for: InputContext(rawInput: "wo jue de zhege fagnan", locale: .zhCN),
            includeFallbackContinuations: true,
            runtimePreferences: InputMethodRuntimePreferences(localContinuationEnabledWhenNoProvider: false)
        )

        XCTAssertEqual(response.lockedPrefix?.text, "我觉得这个方案")
        XCTAssertFalse(response.prefixCandidates.isEmpty)
        XCTAssertTrue(response.continuationCandidates.isEmpty)
    }

    func testAsyncPipelineKeepsLocalFallbackWhenCloudContinuationIsDisabledWithoutProvider() async {
        let pipeline = InputMethodPipeline(
            runtimePreferences: InputMethodRuntimePreferences(
                cloudContinuationEnabled: false,
                localContinuationEnabledWhenNoProvider: true
            )
        )

        let response = await pipeline.suggestions(
            for: InputContext(rawInput: "wo jue de zhege fagnan", locale: .zhCN)
        )

        XCTAssertEqual(response.lockedPrefix?.text, "我觉得这个方案")
        XCTAssertFalse(response.prefixCandidates.isEmpty)
        XCTAssertEqual(response.continuationCandidates.first?.text, "还有进一步优化空间")
    }

    func testAsyncPipelineHonorsDisabledLocalFallbackWithoutProvider() async {
        let pipeline = InputMethodPipeline(
            runtimePreferences: InputMethodRuntimePreferences(localContinuationEnabledWhenNoProvider: false)
        )

        let response = await pipeline.suggestions(
            for: InputContext(rawInput: "wo jue de zhege fagnan", locale: .zhCN)
        )

        XCTAssertEqual(response.lockedPrefix?.text, "我觉得这个方案")
        XCTAssertFalse(response.prefixCandidates.isEmpty)
        XCTAssertTrue(response.continuationCandidates.isEmpty)
    }

    func testRuntimePreferencesCanDisableCloudContinuations() async {
        let provider = RecordingMVPProvider()
        let pipeline = InputMethodPipeline(
            provider: provider,
            runtimePreferences: InputMethodRuntimePreferences(cloudContinuationEnabled: false)
        )

        let response = await pipeline.suggestions(
            for: InputContext(rawInput: "wo jue de zhege fagnan", locale: .zhCN)
        )

        XCTAssertEqual(response.lockedPrefix?.text, "我觉得这个方案")
        XCTAssertFalse(response.prefixCandidates.isEmpty)
        XCTAssertTrue(response.continuationCandidates.isEmpty)
        let tasks = await provider.currentTasks()
        XCTAssertFalse(tasks.contains(.continuation))
    }

    func testMixedInputKeepsTechnicalTokensAndCommitsContinuation() async {
        let pipeline = InputMethodPipeline()
        let response = await pipeline.suggestions(
            for: InputContext(rawInput: "zhege api latnecy youdian gao", locale: .mixed)
        )
        let controller = InputCompositionController()
        let result = controller.handle(
            action: .tab,
            prefixCandidates: response.prefixCandidates,
            continuationCandidates: response.continuationCandidates,
            originalText: "zhege api latnecy youdian gao"
        )

        XCTAssertEqual(response.lockedPrefix?.text, "这个 API latency 有点高")
        XCTAssertEqual(result, .commit("这个 API latency 有点高需要进一步排查接口链路耗时"))
    }

    func testLatencyFallbackRequiresTechnicalTokenBoundary() {
        XCTAssertTrue(PrefixContinuationEngine.hasTechnicalLatencySignal("这个 API latency 有点高"))
        XCTAssertTrue(PrefixContinuationEngine.hasTechnicalLatencySignal("接口延迟有点高"))
        XCTAssertFalse(PrefixContinuationEngine.hasTechnicalLatencySignal("这个 rapid prototype"))
        XCTAssertFalse(PrefixContinuationEngine.hasTechnicalLatencySignal("这个 capital 开销"))
    }

    func testEnglishCorrectionAndFallbackContinuationFlow() async {
        let pipeline = InputMethodPipeline()
        let response = await pipeline.suggestions(
            for: InputContext(rawInput: "I thikn this approch", locale: .enUS)
        )
        let controller = InputCompositionController()
        let result = controller.handle(
            action: .tab,
            prefixCandidates: response.prefixCandidates,
            continuationCandidates: response.continuationCandidates,
            originalText: "I thikn this approch"
        )

        XCTAssertEqual(response.lockedPrefix?.text, "I think this approach")
        XCTAssertEqual(result, .commit("I think this approach still needs more validation"))
    }

    func testLevelZeroPathDoesNotRewriteOrRequireContinuation() async {
        let path = "/Users/zq/project/KnowType"
        let pipeline = InputMethodPipeline()
        let response = await pipeline.suggestions(
            for: InputContext(rawInput: path, locale: .mixed)
        )
        let controller = InputCompositionController()
        let result = controller.handle(
            action: .space,
            prefixCandidates: response.prefixCandidates,
            continuationCandidates: response.continuationCandidates,
            originalText: path
        )

        XCTAssertEqual(response.lockedPrefix?.text, path)
        XCTAssertEqual(result, .commit(path))
    }

    func testPolishIsExplicitOnly() async {
        let pipeline = InputMethodPipeline()
        let response = await pipeline.suggestions(
            for: InputContext(rawInput: "wo jue de zhege fagnan", locale: .zhCN)
        )
        let controller = InputCompositionController()
        let result = controller.handle(
            action: .optionR,
            prefixCandidates: response.prefixCandidates,
            continuationCandidates: response.continuationCandidates,
            originalText: "我觉得这个接口慢"
        )

        XCTAssertEqual(result, .polishRequested("我觉得这个接口慢"))
    }
}

private actor RecordingMVPProvider: LLMProvider {
    nonisolated let providerName = "recording-mvp"
    private var tasks: [LLMTask] = []

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        tasks.append(request.task)
        return LLMResponse(candidates: [
            LLMCandidate(text: "provider continuation")
        ])
    }

    func currentTasks() -> [LLMTask] {
        tasks
    }
}
