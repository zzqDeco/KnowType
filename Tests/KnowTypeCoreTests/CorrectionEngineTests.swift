import XCTest
@testable import KnowTypeCore

private actor RecordingProvider: LLMProvider {
    nonisolated let providerName = "recording"
    private var recordedRequests: [LLMRequest] = []

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        recordedRequests.append(request)
        return LLMResponse(candidates: [
            LLMCandidate(text: "cloud should not be used", confidence: 1.0)
        ])
    }

    var requests: [LLMRequest] {
        recordedRequests
    }
}

final class CorrectionEngineTests: XCTestCase {
    func testPinyinCorrectionProducesAccuratePrefixCandidates() async {
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "wo jue de zhege fagnan", locale: .zhCN)
        )

        XCTAssertEqual(candidates.first?.text, "我觉得这个方案")
        XCTAssertTrue(candidates.map(\.text).contains("我觉得这个方法"))
        XCTAssertTrue(candidates.map(\.text).contains("我觉得这个方向"))
    }

    func testEnglishCorrectionPreservesSentenceShape() async {
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "I thikn this approch", locale: .enUS)
        )

        XCTAssertEqual(candidates.first?.text, "I think this approach")
    }

    func testMixedInputProtectsTechnicalTokens() async {
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "zhege api latnecy youdian gao", locale: .mixed)
        )

        XCTAssertEqual(candidates.first?.text, "这个 API latency 有点高")
    }

    func testTechnicalTokensArePreserved() async {
        let raw = "API JSON macOS InputMethodKit snake_case camelCase"
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: raw, locale: .enUS)
        )

        XCTAssertEqual(candidates.first?.text, raw)
    }

    func testLevelZeroInputsAreNotCorrected() async {
        let engine = CorrectionEngine()
        let path = "/Users/zq/project/KnowType"
        let candidates = await engine.correct(InputContext(rawInput: path, locale: .mixed))

        XCTAssertEqual(candidates.first?.text, path)
        XCTAssertEqual(candidates.first?.source, "local-protection")
        XCTAssertEqual(candidates.first?.correctionLevel, CorrectionLevel.none)
    }

    func testLevelZeroContentClassesRequireNoCorrection() {
        let protectedInputs = [
            "https://example.com/search?q=KnowType",
            "open https://example.com/search?q=KnowType",
            "support@example.com",
            "send this to support@example.com",
            "/Users/zq/project/KnowType",
            "open /Users/zq/project/KnowType",
            "~/Library/Input Methods",
            "git status --short",
            "swift test",
            "let appBundleID = context.appBundleID",
            "snake_case",
            "camelCase"
        ]

        for input in protectedInputs {
            XCTAssertTrue(
                TextProtection.requiresNoCorrection(input),
                "\(input) should be Level 0"
            )
        }
    }

    func testProtectedAppBundleIDsRequireNoCorrection() {
        let protectedApps = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.googlecode.iterm2.beta",
            "com.apple.dt.Xcode"
        ]

        for bundleID in protectedApps {
            XCTAssertTrue(
                TextProtection.requiresNoCorrection("wo jue de zhege fagnan", appBundleID: bundleID),
                "\(bundleID) should be Level 0"
            )
        }
    }

    func testLevelZeroCorrectionDoesNotCallProvider() async {
        let provider = RecordingProvider()
        let engine = CorrectionEngine(cloudProvider: provider)

        let candidates = await engine.correct(
            InputContext(rawInput: "git status --short", locale: .mixed)
        )
        let requests = await provider.requests

        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(candidates.first?.text, "git status --short")
        XCTAssertEqual(candidates.first?.source, "local-protection")
    }

    func testEmbeddedProtectedContentDoesNotCallProvider() async {
        let provider = RecordingProvider()
        let engine = CorrectionEngine(cloudProvider: provider)

        let candidates = await engine.correct(
            InputContext(rawInput: "open https://example.com/path?q=KnowType", locale: .mixed)
        )
        let requests = await provider.requests

        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(candidates.first?.text, "open https://example.com/path?q=KnowType")
        XCTAssertEqual(candidates.first?.source, "local-protection")
        XCTAssertEqual(candidates.first?.protectedRanges.first?.reason, "url")
    }
}
