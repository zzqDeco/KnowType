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

    func testMixedInputKeepsTechnicalTokensAndCommitsContinuation() async {
        let pipeline = InputMethodPipeline()
        let response = await pipeline.suggestions(
            for: InputContext(rawInput: "zhege api latnecy youdian gao", locale: .mixed)
        )
        let controller = InputCompositionController()
        let result = controller.handle(
            action: .optionNumber(1),
            prefixCandidates: response.prefixCandidates,
            continuationCandidates: response.continuationCandidates,
            originalText: "zhege api latnecy youdian gao"
        )

        XCTAssertEqual(response.lockedPrefix?.text, "这个 API latency 有点高")
        XCTAssertEqual(result, .commit("这个 API latency 有点高需要进一步排查接口链路耗时"))
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
