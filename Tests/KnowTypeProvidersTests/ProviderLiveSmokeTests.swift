import Foundation
import XCTest
import KnowTypeCore
@testable import KnowTypeProviders

private let liveSmokeEnabledVariable = "KNOWTYPE_PROVIDER_LIVE_SMOKE"
private let liveSmokeAPIKeyVariable = "KNOWTYPE_PROVIDER_LIVE_API_KEY"
private let liveSmokeModelVariable = "KNOWTYPE_PROVIDER_LIVE_MODEL"
private let defaultLiveSmokeAPIKey = "local-544c98478806455ae2c63d54830cc3d3"
private let defaultLiveSmokeModel = "gpt-5.3-codex-spark"
private let liveSmokeBaseURL = URL(string: "http://127.0.0.1:8317/v1")!
private let liveSmokeProviderTimeoutSeconds: TimeInterval = 12
private let expectedRuntimeBudgetSeconds: TimeInterval = 10

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

private actor FixtureRecordingHTTPClient: HTTPClient {
    private var requestedPaths: [String] = []

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let path = request.url?.path {
            requestedPaths.append(path)
        }

        guard request.url?.path == "/v1/chat/completions" else {
            throw ProviderError.invalidResponse("unexpected fixture request path: \(request.url?.path ?? "<nil>")")
        }

        let content = #"{"candidates":[{"text":"还可以继续优化","confidence":0.9,"reason":"fixture"}]}"#
        let escaped = content.replacingOccurrences(of: "\"", with: "\\\"")
        let data = Data(#"{"choices":[{"message":{"content":"\#(escaped)"}}]}"#.utf8)
        let response = HTTPURLResponse(
            url: request.url ?? liveSmokeBaseURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
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

private struct LiveSmokeModelResolution: Equatable {
    var model: String
    var source: String

    var overrideHint: String {
        "Set \(liveSmokeModelVariable)=<model-id> to override the live smoke model."
    }
}

private enum LiveSmokeModelResolver {
    static func resolveFromDefaultStore(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LiveSmokeModelResolution {
        resolve(
            environment: environment,
            profilesFile: (try? FileProviderProfileStore.defaultStore().loadProfiles())
        )
    }

    static func resolve(
        environment: [String: String],
        profilesFile: ProviderProfilesFile?
    ) -> LiveSmokeModelResolution {
        if let override = trimmed(environment[liveSmokeModelVariable]) {
            return LiveSmokeModelResolution(
                model: override,
                source: "environment \(liveSmokeModelVariable)"
            )
        }

        if let profile = profilesFile?.profiles.first(where: isLiveSmokeLocalDefaultProfile),
           let model = trimmed(profile.model) {
            return LiveSmokeModelResolution(
                model: model,
                source: "default local provider profile \(profile.id)"
            )
        }

        return LiveSmokeModelResolution(
            model: defaultLiveSmokeModel,
            source: "built-in fallback \(defaultLiveSmokeModel)"
        )
    }

    private static func isLiveSmokeLocalDefaultProfile(_ profile: ProviderProfile) -> Bool {
        profile.isDefault
            && profile.kind == .openAIChat
            && normalizedBaseURL(profile.baseURL) == normalizedBaseURL(liveSmokeBaseURL)
    }

    private static func normalizedBaseURL(_ url: URL) -> String {
        url.absoluteString
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

final class ProviderLiveSmokeTests: XCTestCase {
    func testLiveSmokeModelResolutionUsesEnvironmentOverride() {
        let profilesFile = ProviderProfilesFile(profiles: [
            localProfile(model: "profile-model")
        ])

        let resolution = LiveSmokeModelResolver.resolve(
            environment: [liveSmokeModelVariable: " env-model \n"],
            profilesFile: profilesFile
        )

        XCTAssertEqual(resolution.model, "env-model")
        XCTAssertEqual(resolution.source, "environment \(liveSmokeModelVariable)")
    }

    func testLiveSmokeModelResolutionUsesLocalDefaultProfileModel() {
        let profilesFile = ProviderProfilesFile(profiles: [
            ProviderProfile(
                displayName: "Remote",
                kind: .openAIChat,
                baseURL: URL(string: "https://api.example.com")!,
                model: "remote-model",
                isDefault: true
            ),
            localProfile(model: "gpt-5.3-codex-spark")
        ])

        let resolution = LiveSmokeModelResolver.resolve(
            environment: [:],
            profilesFile: profilesFile
        )

        XCTAssertEqual(resolution.model, "gpt-5.3-codex-spark")
        XCTAssertTrue(resolution.source.contains("default local provider profile"))
    }

    func testLiveSmokeModelResolutionFallsBackWhenProfileMissingOrBlank() {
        XCTAssertEqual(
            LiveSmokeModelResolver.resolve(environment: [:], profilesFile: nil).model,
            defaultLiveSmokeModel
        )
        XCTAssertEqual(
            LiveSmokeModelResolver.resolve(
                environment: [:],
                profilesFile: ProviderProfilesFile(profiles: [localProfile(model: " ")])
            ).model,
            defaultLiveSmokeModel
        )
    }

    func testContinuationLiveSmokeConfigurationUsesExplicitModelAndSkipsDiscovery() async throws {
        let resolution = LiveSmokeModelResolver.resolve(
            environment: [:],
            profilesFile: ProviderProfilesFile(profiles: [
                localProfile(model: "gpt-5.3-codex-spark")
            ])
        )
        let client = FixtureRecordingHTTPClient()
        let provider = OpenAIChatProvider(
            configuration: continuationLiveSmokeConfiguration(modelResolution: resolution),
            httpClient: client
        )

        _ = try await provider.complete(
            LLMRequest(
                task: .continuation,
                lockedPrefix: "我觉得这个方案",
                rawInput: "wojuedezhegefangan",
                locale: .zhCN,
                maxCandidates: 2,
                lengthLevel: .short
            )
        )

        let paths = await client.paths()
        XCTAssertEqual(paths, ["/v1/chat/completions"])
    }

    func testLocalOpenAICompatibleModelDiscoveryLiveSmoke() async throws {
        try requireLiveSmokeEnabled()
        let discovery = OpenAICompatibleModelDiscovery()

        let model = try await discovery.resolvedModel(for: modelDiscoveryLiveSmokeConfiguration())

        XCTAssertFalse(model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testLocalOpenAICompatibleContinuationLiveSmoke() async throws {
        try requireLiveSmokeEnabled()
        let client = LiveRecordingHTTPClient()
        let modelResolution = LiveSmokeModelResolver.resolveFromDefaultStore()
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
            configuration: continuationLiveSmokeConfiguration(modelResolution: modelResolution),
            httpClient: client
        )

        let startedAt = Date()
        let response: LLMResponse
        do {
            response = try await provider.complete(request)
        } catch let error as URLError where error.code == .timedOut {
            XCTFail("transport timeout: model=\(modelResolution.model) source=\(modelResolution.source) did not respond within \(liveSmokeProviderTimeoutSeconds)s. \(modelResolution.overrideHint) Error: \(error)")
            return
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut {
                XCTFail("transport timeout: model=\(modelResolution.model) source=\(modelResolution.source) did not respond within \(liveSmokeProviderTimeoutSeconds)s. \(modelResolution.overrideHint) Error: \(error)")
            } else {
                XCTFail("local provider failure before live smoke could validate runtime budget: model=\(modelResolution.model) source=\(modelResolution.source). \(modelResolution.overrideHint) Error: \(error)")
            }
            return
        }
        let elapsedSeconds = Date().timeIntervalSince(startedAt)
        let paths = await client.paths()
        let sanitized = response.candidates.compactMap { candidate in
            PrefixContinuationEngine.sanitizeContinuation(candidate.text, lockedPrefix: lockedPrefix)
        }

        XCTAssertEqual(
            paths,
            ["/v1/chat/completions"],
            "continuation live smoke must use explicit model \(modelResolution.model) and skip /v1/models discovery"
        )
        XCTAssertLessThanOrEqual(
            elapsedSeconds,
            expectedRuntimeBudgetSeconds,
            "runtime budget exceeded: model=\(modelResolution.model) source=\(modelResolution.source) returned in \(elapsedSeconds)s, slower than KnowType's \(expectedRuntimeBudgetSeconds)s AI runtime hard timeout. \(modelResolution.overrideHint)"
        )
        XCTAssertFalse(response.candidates.isEmpty, "invalid continuation: model=\(modelResolution.model) provider returned no candidates")
        XCTAssertFalse(sanitized.isEmpty, "invalid continuation: model=\(modelResolution.model) provider candidates did not pass the locked-prefix sanitizer")
        XCTAssertTrue(
            sanitized.allSatisfy { !$0.hasPrefix(lockedPrefix) },
            "invalid continuation: model=\(modelResolution.model) sanitized suffix must not repeat lockedPrefix"
        )
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

    private func modelDiscoveryLiveSmokeConfiguration() -> ProviderConfiguration {
        let rawAPIKey = ProcessInfo.processInfo.environment[liveSmokeAPIKeyVariable]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = rawAPIKey?.isEmpty == false ? rawAPIKey : defaultLiveSmokeAPIKey
        return ProviderConfiguration(
            kind: .openAIChat,
            baseURL: liveSmokeBaseURL,
            apiKey: apiKey,
            model: "",
            timeoutSeconds: liveSmokeProviderTimeoutSeconds
        )
    }

    private func continuationLiveSmokeConfiguration(
        modelResolution: LiveSmokeModelResolution
    ) -> ProviderConfiguration {
        let rawAPIKey = ProcessInfo.processInfo.environment[liveSmokeAPIKeyVariable]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = rawAPIKey?.isEmpty == false ? rawAPIKey : defaultLiveSmokeAPIKey
        return ProviderConfiguration(
            kind: .openAIChat,
            baseURL: liveSmokeBaseURL,
            apiKey: apiKey,
            model: modelResolution.model,
            timeoutSeconds: liveSmokeProviderTimeoutSeconds
        )
    }

    private func localProfile(
        model: String,
        id: String = "local-openai-compatible",
        isDefault: Bool = true
    ) -> ProviderProfile {
        ProviderProfile(
            id: id,
            displayName: "Local OpenAI Compatible",
            kind: .openAIChat,
            baseURL: liveSmokeBaseURL,
            model: model,
            isDefault: isDefault
        )
    }
}
