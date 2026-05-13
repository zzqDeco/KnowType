import XCTest
@testable import KnowTypeCore

private struct StubProvider: LLMProvider {
    let providerName = "stub"
    let response: LLMResponse

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        response
    }
}

private actor RecordingContinuationProvider: LLMProvider {
    nonisolated let providerName = "recording-continuation"
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

final class PrefixContinuationEngineTests: XCTestCase {
    func testContinuationCropsRepeatedLockedPrefix() async {
        let provider = StubProvider(
            response: LLMResponse(candidates: [
                LLMCandidate(text: "我觉得这个方案还有进一步优化空间", confidence: 0.9)
            ])
        )
        let engine = PrefixContinuationEngine(provider: provider)
        let continuations = await engine.continuations(
            for: LockedPrefix(text: "我觉得这个方案", rawInput: "wo jue de zhege fagnan", candidateID: "test"),
            lengthLevel: .medium
        )

        XCTAssertEqual(continuations.first?.text, "还有进一步优化空间")
    }

    func testFallbackDoesNotBlockWhenProviderIsUnavailable() async {
        let engine = PrefixContinuationEngine()
        let continuations = await engine.continuations(
            for: LockedPrefix(text: "I think this approach", rawInput: "I thikn this approch", candidateID: "test"),
            lengthLevel: .medium
        )

        XCTAssertEqual(continuations.first?.text, "still needs more validation")
    }

    func testLevelZeroContinuationReturnsEmptyAndDoesNotCallProvider() async {
        let provider = RecordingContinuationProvider()
        let engine = PrefixContinuationEngine(provider: provider)
        let continuations = await engine.continuations(
            for: LockedPrefix(text: "support@example.com", rawInput: "support@example.com", candidateID: "test"),
            context: InputContext(rawInput: "support@example.com", locale: .mixed),
            lengthLevel: .medium
        )
        let requests = await provider.requests

        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(continuations.isEmpty)
    }

    func testNilContextLevelZeroLockedPrefixReturnsEmptyAndDoesNotCallProvider() async {
        let provider = RecordingContinuationProvider()
        let engine = PrefixContinuationEngine(provider: provider)

        let protectedPrefixes = [
            "https://example.com/search?q=KnowType",
            "support@example.com",
            "/Users/zq/project/KnowType",
            "docker ps",
            "kubectl get pods",
            "brew install foo",
            "pnpm install",
            "swift test > test.log",
            "let appBundleID = context.appBundleID"
        ]

        for prefix in protectedPrefixes {
            let continuations = await engine.continuations(
                for: LockedPrefix(text: prefix, rawInput: prefix, candidateID: "test"),
                context: nil,
                lengthLevel: .medium
            )

            XCTAssertTrue(continuations.isEmpty, "\(prefix) should not produce continuations")
        }

        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testProseCommandAndCodeKeywordsStillProduceContinuations() async {
        let provider = RecordingContinuationProvider()
        let engine = PrefixContinuationEngine(provider: provider)
        let prefixes = [
            "go to market plan",
            "make this easier",
            "I think A > B",
            "price is < expected",
            "I think we should import data",
            "let me know the plan"
        ]

        for prefix in prefixes {
            let continuations = await engine.continuations(
                for: LockedPrefix(text: prefix, rawInput: prefix, candidateID: "test"),
                context: InputContext(rawInput: prefix, locale: .enUS),
                lengthLevel: .medium
            )

            XCTAssertFalse(continuations.isEmpty, "\(prefix) should produce continuations")
        }

        let requests = await provider.requests
        XCTAssertEqual(requests.count, prefixes.count)
    }
}
