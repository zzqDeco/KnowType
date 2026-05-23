import Foundation
import XCTest
import KnowTypeCore
@testable import KnowTypeProviders

private let liveSmokeEnabledVariable = "KNOWTYPE_PROVIDER_LIVE_SMOKE"
private let liveSmokeAPIKeyVariable = "KNOWTYPE_PROVIDER_LIVE_API_KEY"
private let defaultLiveSmokeAPIKey = "local-544c98478806455ae2c63d54830cc3d3"
private let liveSmokeBaseURL = URL(string: "http://127.0.0.1:8317/v1")!

private actor LiveRecordingHTTPClient: HTTPClient {
    private var requestedPaths: [String] = []

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let path = request.url?.path {
            requestedPaths.append(path)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("missing HTTPURLResponse")
        }
        return (data, httpResponse)
    }

    func paths() -> [String] {
        requestedPaths
    }
}

private struct ThrowingContinuationProvider: LLMProvider {
    let providerName = "throwing-provider"

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        throw ProviderError.httpStatus(503, "provider unavailable")
    }
}

final class ProviderLiveSmokeTests: XCTestCase {
    func testLocalOpenAICompatibleModelDiscoveryLiveSmoke() async throws {
        try requireLiveSmokeEnabled()
        let discovery = OpenAICompatibleModelDiscovery()

        let model = try await discovery.resolvedModel(for: liveSmokeConfiguration())

        XCTAssertFalse(model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testLocalOpenAICompatibleContinuationLiveSmoke() async throws {
        try requireLiveSmokeEnabled()
        let client = LiveRecordingHTTPClient()
        let lockedPrefix = "我觉得这个方案"
        let request = LLMRequest(
            task: .continuation,
            lockedPrefix: lockedPrefix,
            rawInput: "wojuedezhegefangan",
            locale: .zhCN,
            maxCandidates: 2,
            lengthLevel: .short
        )
        let provider = OpenAIChatProvider(
            configuration: liveSmokeConfiguration(),
            httpClient: client
        )

        let response = try await provider.complete(request)
        let paths = await client.paths()
        let sanitized = response.candidates.compactMap { candidate in
            PrefixContinuationEngine.sanitizeContinuation(candidate.text, lockedPrefix: lockedPrefix)
        }

        XCTAssertEqual(paths, ["/v1/models", "/v1/chat/completions"])
        XCTAssertFalse(response.candidates.isEmpty)
        XCTAssertFalse(sanitized.isEmpty)
        XCTAssertTrue(sanitized.allSatisfy { !$0.hasPrefix(lockedPrefix) })
    }

    func testProviderFailureDoesNotReturnLocalFallbackContinuation() async {
        let prefix = LockedPrefix(
            text: "This approach",
            rawInput: "this approach",
            candidateID: "provider-failure-smoke"
        )

        let fallbackCandidates = await PrefixContinuationEngine().continuations(
            for: prefix,
            lengthLevel: .short,
            maxCandidates: 2
        )
        let failedProviderCandidates = await PrefixContinuationEngine(provider: ThrowingContinuationProvider()).continuations(
            for: prefix,
            lengthLevel: .short,
            maxCandidates: 2
        )

        XCTAssertFalse(fallbackCandidates.isEmpty)
        XCTAssertTrue(failedProviderCandidates.isEmpty)
    }

    private func requireLiveSmokeEnabled(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let enabled = ProcessInfo.processInfo.environment[liveSmokeEnabledVariable]
        try XCTSkipUnless(
            enabled == "1",
            "Set \(liveSmokeEnabledVariable)=1 to run local provider live smoke tests.",
            file: file,
            line: line
        )
    }

    private func liveSmokeConfiguration() -> ProviderConfiguration {
        let rawAPIKey = ProcessInfo.processInfo.environment[liveSmokeAPIKeyVariable]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = rawAPIKey?.isEmpty == false ? rawAPIKey : defaultLiveSmokeAPIKey
        return ProviderConfiguration(
            kind: .openAIChat,
            baseURL: liveSmokeBaseURL,
            apiKey: apiKey,
            model: "",
            timeoutSeconds: 5
        )
    }
}
