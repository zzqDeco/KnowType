import Foundation
import XCTest
@testable import KnowTypeAI
import KnowTypeCore
import KnowTypeProviders

final class AIRecommendationRuntimeTests: XCTestCase {
    func testRecommendationReadsContextDocumentsAndCachesResult() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let correctionURL = directory.appendingPathComponent("CORRECTION.md")
        try """
        # KnowType Environment

        <!-- KNOWTYPE:BEGIN GENERATED -->
        ## Global Style
        - Prefer concise Chinese.
        <!-- KNOWTYPE:END GENERATED -->

        ## User Notes
        """.write(to: environmentURL, atomically: true, encoding: .utf8)
        try """
        # KnowType Correction Instructions

        - Preserve API tokens.
        """.write(to: correctionURL, atomically: true, encoding: .utf8)

        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "继续推进", confidence: 0.88)
        ]))
        let runtime = AIRecommendationRuntime(
            provider: provider,
            environmentStore: EnvironmentDocumentStore(fileURL: environmentURL),
            correctionStore: CorrectionInstructionStore(fileURL: correctionURL),
            debounceMilliseconds: 0
        )
        let request = AIRecommendationRequest(
            rawInput: "nihao",
            traditionalCandidate: CorrectionCandidate(
                text: "你好",
                source: "traditional",
                confidence: 1,
                correctionLevel: .contextual
            ),
            appBundleID: "com.apple.TextEdit",
            locale: .zhCN,
            compositionID: 1
        )

        let first = await runtime.recommendation(for: request)
        let second = await runtime.recommendation(for: request)
        let requests = await provider.requests

        guard case .ready(let firstCandidate) = first,
              case .ready(let secondCandidate) = second else {
            return XCTFail("expected ready AI recommendations")
        }
        XCTAssertEqual(firstCandidate.displayText, "你好继续推进")
        XCTAssertEqual(secondCandidate.displayText, "你好继续推进")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].task, .continuation)
        XCTAssertEqual(requests[0].lockedPrefix, "你好")
        XCTAssertEqual(requests[0].contextDocuments["ENV.md"]?.contains("Prefer concise Chinese"), true)
        XCTAssertEqual(requests[0].contextDocuments["CORRECTION.md"]?.contains("Preserve API tokens"), true)
    }

    func testRecommendationCacheIncludesRawInput() async {
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "继续推进", confidence: 0.88)
        ]))
        let runtime = AIRecommendationRuntime(provider: provider, debounceMilliseconds: 0)
        let candidate = CorrectionCandidate(
            text: "你好",
            source: "traditional",
            confidence: 1,
            correctionLevel: .contextual
        )

        _ = await runtime.recommendation(
            for: AIRecommendationRequest(
                rawInput: "nihao",
                traditionalCandidate: candidate,
                compositionID: 1
            )
        )
        _ = await runtime.recommendation(
            for: AIRecommendationRequest(
                rawInput: "ni hao",
                traditionalCandidate: candidate,
                compositionID: 2
            )
        )
        let requests = await provider.requests

        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map(\.rawInput), ["nihao", "ni hao"])
    }

    func testLevelZeroInputDoesNotCallProvider() async {
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: " should not be used")
        ]))
        let runtime = AIRecommendationRuntime(provider: provider, debounceMilliseconds: 0)
        let request = AIRecommendationRequest(
            rawInput: "https://example.com/path",
            traditionalCandidate: CorrectionCandidate(
                text: "https://example.com/path",
                source: "raw",
                confidence: 1,
                correctionLevel: .none
            ),
            compositionID: 1
        )

        let state = await runtime.recommendation(for: request)
        let requests = await provider.requests

        XCTAssertEqual(state, .ineligible(reason: "AI 已禁用"))
        XCTAssertTrue(requests.isEmpty)
    }

    func testRepeatedProviderFailuresEnterCooldown() async {
        let provider = FailingLLMProvider(error: ProviderError.httpStatus(503, "unavailable"))
        let runtime = AIRecommendationRuntime(
            provider: provider,
            healthMonitor: AIHealthMonitor(failureThreshold: 1, cooldownSeconds: 60),
            debounceMilliseconds: 0
        )
        let request = AIRecommendationRequest(
            rawInput: "nihao",
            traditionalCandidate: CorrectionCandidate(
                text: "你好",
                source: "traditional",
                confidence: 1,
                correctionLevel: .contextual
            ),
            compositionID: 1
        )

        let first = await runtime.recommendation(for: request)
        let second = await runtime.recommendation(for: request)
        let requestCount = await provider.requestCount

        XCTAssertEqual(first, .unavailable(reason: "AI 暂不可用"))
        XCTAssertEqual(second, .unavailable(reason: "AI 暂不可用"))
        XCTAssertEqual(requestCount, 1)
    }

    func testEmptyRecommendationDoesNotEnterCooldown() async {
        let provider = QueuedLLMProvider(responses: [
            LLMResponse(candidates: []),
            LLMResponse(candidates: [
                LLMCandidate(text: "继续推进", confidence: 0.9)
            ])
        ])
        let runtime = AIRecommendationRuntime(
            provider: provider,
            healthMonitor: AIHealthMonitor(failureThreshold: 1, cooldownSeconds: 60),
            debounceMilliseconds: 0
        )
        let request = AIRecommendationRequest(
            rawInput: "nihao",
            traditionalCandidate: CorrectionCandidate(
                text: "你好",
                source: "traditional",
                confidence: 1,
                correctionLevel: .contextual
            ),
            compositionID: 1
        )

        let first = await runtime.recommendation(for: request)
        let second = await runtime.recommendation(for: request)
        let requestCount = await provider.requestCount

        XCTAssertEqual(first, .ineligible(reason: "AI 无推荐"))
        guard case .ready(let candidate) = second else {
            return XCTFail("expected second recommendation to bypass cooldown")
        }
        XCTAssertEqual(candidate.displayText, "你好继续推进")
        XCTAssertEqual(requestCount, 2)
    }

    func testHardTimeoutReturnsWithoutWaitingForCancellationResistantProvider() async {
        let provider = SlowCancellationResistantLLMProvider()
        let runtime = AIRecommendationRuntime(
            provider: provider,
            debounceMilliseconds: 0,
            hardTimeoutMilliseconds: 20
        )
        let request = AIRecommendationRequest(
            rawInput: "nihao",
            traditionalCandidate: CorrectionCandidate(
                text: "你好",
                source: "traditional",
                confidence: 1,
                correctionLevel: .contextual
            ),
            compositionID: 1
        )
        let start = Date()

        let state = await runtime.recommendation(for: request)
        let requestCount = await provider.requestCount

        XCTAssertEqual(state, .unavailable(reason: "AI 请求超时"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        XCTAssertEqual(requestCount, 1)
    }

    func testDocumentStoresCreateDefaultsAndPreserveUserNotes() throws {
        let directory = temporaryDirectory()
        let environmentStore = EnvironmentDocumentStore(
            fileURL: directory.appendingPathComponent("ENV.md")
        )
        let correctionStore = CorrectionInstructionStore(
            fileURL: directory.appendingPathComponent("CORRECTION.md")
        )

        let environment = try environmentStore.loadSnapshot()
        let correction = try correctionStore.loadSnapshot()

        XCTAssertTrue(environment.content.contains("## User Notes"))
        XCTAssertTrue(correction.content.contains("临近键"))

        let updated = try environmentStore.replaceGeneratedSection(with: "## Global Style\n- Test style.")
        XCTAssertTrue(updated.content.contains("## Global Style\n- Test style."))
        XCTAssertTrue(updated.content.contains("## User Notes"))
    }

    func testEnvironmentReplacementPreservesExistingContentWhenMarkersAreMissing() {
        let current = """
        # KnowType Environment

        ## User Notes
        - Keep this manual note.
        """

        let updated = EnvironmentDocumentStore.replacingGeneratedSection(
            in: current,
            with: "## Global Style\n- Learned style."
        )

        XCTAssertTrue(updated.contains("## Global Style\n- Learned style."))
        XCTAssertTrue(updated.contains("## User Notes"))
        XCTAssertTrue(updated.contains("- Keep this manual note."))
    }
}

private actor RecordingLLMProvider: LLMProvider {
    nonisolated let providerName = "recording"
    private let response: LLMResponse
    private var recordedRequests: [LLMRequest] = []

    init(response: LLMResponse) {
        self.response = response
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        recordedRequests.append(request)
        return response
    }

    var requests: [LLMRequest] {
        recordedRequests
    }
}

private actor FailingLLMProvider: LLMProvider {
    nonisolated let providerName = "failing"
    private let error: Error
    private var count = 0

    init(error: Error) {
        self.error = error
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        count += 1
        throw error
    }

    var requestCount: Int {
        count
    }
}

private actor QueuedLLMProvider: LLMProvider {
    nonisolated let providerName = "queued"
    private var responses: [LLMResponse]
    private var count = 0

    init(responses: [LLMResponse]) {
        self.responses = responses
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        count += 1
        guard !responses.isEmpty else {
            return LLMResponse(candidates: [])
        }
        return responses.removeFirst()
    }

    var requestCount: Int {
        count
    }
}

private actor SlowCancellationResistantLLMProvider: LLMProvider {
    nonisolated let providerName = "slow"
    private var count = 0

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        count += 1
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            do {
                try await Task.sleep(nanoseconds: 20_000_000)
            } catch {
                continue
            }
        }
        return LLMResponse(candidates: [
            LLMCandidate(text: "继续推进", confidence: 0.9)
        ])
    }

    var requestCount: Int {
        count
    }
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("KnowTypeAITests-\(UUID().uuidString)", isDirectory: true)
}
