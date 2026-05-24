import XCTest
@testable import KnowTypeCore

private struct StubProvider: LLMProvider {
    let providerName = "stub"
    let response: LLMResponse

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        response
    }
}

private struct ThrowingProvider: LLMProvider {
    let providerName = "throwing"

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        throw NSError(domain: "KnowTypeTests", code: 1)
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

    func testDetailedSanitizerReportsRejectionAndRepairReasons() {
        XCTAssertEqual(
            PrefixContinuationEngine.sanitizeContinuationDetailed(
                "我觉得这个方案还有进一步优化空间",
                lockedPrefix: "我觉得这个方案"
            ),
            ContinuationSanitizationResult(
                text: "还有进一步优化空间",
                reason: .repeatedPrefixRepaired
            )
        )
        XCTAssertEqual(
            PrefixContinuationEngine.sanitizeContinuationDetailed("我觉得这个方案", lockedPrefix: "我觉得这个方案"),
            ContinuationSanitizationResult(text: nil, reason: .sameAsPrefix)
        )
        XCTAssertEqual(
            PrefixContinuationEngine.sanitizeContinuationDetailed("   ", lockedPrefix: "我觉得这个方案"),
            ContinuationSanitizationResult(text: nil, reason: .empty)
        )
        XCTAssertEqual(
            PrefixContinuationEngine.sanitizeContinuationDetailed(
                "我觉得这个方案，我觉得这个方案还有问题",
                lockedPrefix: "我觉得这个方案"
            ),
            ContinuationSanitizationResult(text: nil, reason: .stillRepeatsPrefix)
        )
        XCTAssertEqual(
            PrefixContinuationEngine.sanitizeContinuationDetailed("我觉得这个方案，", lockedPrefix: "我觉得这个方案"),
            ContinuationSanitizationResult(text: nil, reason: .noUsableSuffix)
        )
    }

    func testFallbackDoesNotBlockWhenProviderIsUnavailable() async {
        let engine = PrefixContinuationEngine()
        let continuations = await engine.continuations(
            for: LockedPrefix(text: "I think this approach", rawInput: "I thikn this approch", candidateID: "test"),
            lengthLevel: .medium
        )

        XCTAssertEqual(continuations.first?.text, "still needs more validation")
    }

    func testProviderFailureDoesNotReturnFallbackContinuations() async {
        let engine = PrefixContinuationEngine(provider: ThrowingProvider())
        let continuations = await engine.continuations(
            for: LockedPrefix(text: "我觉得这个方案", rawInput: "wo jue de zhege fagnan", candidateID: "test"),
            lengthLevel: .medium
        )

        XCTAssertTrue(continuations.isEmpty)
    }

    func testProviderEmptyUsableResponseDoesNotReturnFallbackContinuations() async {
        let provider = StubProvider(
            response: LLMResponse(candidates: [
                LLMCandidate(text: "我觉得这个方案", confidence: 0.9),
                LLMCandidate(text: "  \n", confidence: 0.4)
            ])
        )
        let engine = PrefixContinuationEngine(provider: provider)
        let continuations = await engine.continuations(
            for: LockedPrefix(text: "我觉得这个方案", rawInput: "wo jue de zhege fagnan", candidateID: "test"),
            lengthLevel: .medium
        )

        XCTAssertTrue(continuations.isEmpty)
    }

    func testFallbackProvidesSixMediumCandidatesForInputMethodPanel() {
        let engine = PrefixContinuationEngine()
        let continuations = engine.fallbackContinuations(
            for: "我觉得这个方案",
            lengthLevel: .medium,
            maxCandidates: 6
        )

        XCTAssertEqual(continuations.count, 6)
        XCTAssertEqual(continuations.first?.text, "还有进一步优化空间")
    }

    func testSecretContinuationReturnsEmptyAndDoesNotCallProvider() async {
        let provider = RecordingContinuationProvider()
        let engine = PrefixContinuationEngine(provider: provider)
        let continuations = await engine.continuations(
            for: LockedPrefix(
                text: "API_KEY=sk-abcdefghijklmnopqrstuvwxyz",
                rawInput: "API_KEY=sk-abcdefghijklmnopqrstuvwxyz",
                candidateID: "test"
            ),
            context: InputContext(rawInput: "API_KEY=sk-abcdefghijklmnopqrstuvwxyz", locale: .mixed),
            lengthLevel: .medium
        )
        let requests = await provider.requests

        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(continuations.isEmpty)
    }

    func testNilContextSecretLockedPrefixReturnsEmptyAndDoesNotCallProvider() async {
        let provider = RecordingContinuationProvider()
        let engine = PrefixContinuationEngine(provider: provider)

        let secretPrefixes = [
            "sk-abcdefghijklmnopqrstuvwxyz123456",
            "Authorization: Bearer abcdefghijklmnopqrstuvwxyz",
            "API_KEY=sk-abcdefghijklmnopqrstuvwxyz",
            "https://example.com/callback?token=abcdef123456"
        ]

        for prefix in secretPrefixes {
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

    func testProviderBackedContinuationAllowsTechnicalCommandsAndPaths() async {
        let provider = RecordingContinuationProvider()
        let engine = PrefixContinuationEngine(provider: provider)
        let prefixes = [
            "https://example.com/search?q=KnowType",
            "/Users/zq/project/KnowType",
            "git status",
            "InputMethodKit",
            "snake_case"
        ]

        for prefix in prefixes {
            let continuations = await engine.continuations(
                for: LockedPrefix(text: prefix, rawInput: prefix, candidateID: "test"),
                context: InputContext(rawInput: prefix, locale: .mixed),
                lengthLevel: .medium
            )

            XCTAssertFalse(continuations.isEmpty, "\(prefix) should produce provider-backed continuations")
        }

        let requests = await provider.requests
        XCTAssertEqual(requests.count, prefixes.count)
    }

    func testProseCommandAndCodeKeywordsStillProduceContinuations() async {
        let provider = RecordingContinuationProvider()
        let engine = PrefixContinuationEngine(provider: provider)
        let prefixes = [
            "go to market plan",
            "make this easier",
            "make sure this works",
            "make changes later",
            "> I think this",
            "$ I think this",
            "cat is cute",
            "touch base later",
            "brew coffee",
            "I think A > B",
            "price is < expected",
            "I think we should import data",
            "let me know the plan",
            "export data later",
            "source material",
            "I think camelCase naming works",
            "I think snake_case naming works"
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
