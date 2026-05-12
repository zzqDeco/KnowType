import XCTest
@testable import KnowTypeCore

private struct StubProvider: LLMProvider {
    let providerName = "stub"
    let response: LLMResponse

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        response
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
}
