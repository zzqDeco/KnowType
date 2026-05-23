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
            "example.com/path?q=token",
            "go.dev/doc",
            "visit example.com",
            "send to go.dev",
            "192.168.1.1",
            "localhost:3000",
            "127.0.0.1:8080",
            "api.local:8080",
            "service.internal",
            "example.sh",
            "open api.local:8080",
            "support@example.com",
            "/Users/zq/project/KnowType",
            "docker ps",
            "docker login",
            "kubectl get pods",
            "git config user.email",
            "git stash",
            "brew install foo",
            "pnpm install",
            "curl example.com",
            "curl staging",
            "ssh production-box",
            "ssh prod",
            "ssh user@prod",
            "> docker ps",
            "$ docker ps",
            "cat ./Package.swift",
            "cat Package.swift",
            "vim secrets.txt",
            "rm README.md",
            "sudo rm README.md",
            "sudo -E rm README.md",
            "sudo -u deploy git pull",
            "cp .env backup.env",
            "touch /tmp/knowtype",
            "git status&&echo ok",
            "docker ps|rg api",
            "swift test>test.log",
            "swift test > test.log",
            "pwd",
            "echo $GITHUB_TOKEN",
            "unset API_KEY",
            "env",
            "export PATH=/usr/local/bin:$PATH",
            "source .env",
            "source .env.local",
            "source .env.production",
            "python main.py",
            "python my-script.py",
            "node server.js",
            "node build-prod.js",
            "GITHUB_TOKEN=secret npm publish",
            "API_KEY=secret curl example.com",
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
