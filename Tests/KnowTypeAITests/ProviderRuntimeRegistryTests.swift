import Foundation
import XCTest
@testable import KnowTypeAI
import KnowTypeCore
@testable import KnowTypeProviders

final class ProviderRuntimeRegistryTests: XCTestCase {
    func testLeaseIncludesRevisionGenerationFingerprintAndProvider() async {
        let provider = NamedLLMProvider(name: "provider-a", responseText: "A result")
        let source = ProviderRuntimeTestSource(
            revision: 7,
            fingerprint: String(repeating: "a", count: 64),
            provider: provider
        )
        let registry = makeRegistry(source: source)

        let lease = await registry.leaseForEligibleDispatch()

        XCTAssertEqual(lease.revision, 7)
        XCTAssertEqual(lease.generation, 1)
        XCTAssertEqual(lease.fingerprint, String(repeating: "a", count: 64))
        XCTAssertEqual(lease.provider?.providerName, "provider-a")
    }

    func testRecommendationReloadsAtoBWithoutRestartAndClearsGenerationCache() async {
        let providerA = NamedLLMProvider(name: "provider-a", responseText: "A result")
        let providerB = NamedLLMProvider(name: "provider-b", responseText: "B result")
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: providerA
        )
        let signal = TestProviderRevisionSignal()
        let registry = makeRegistry(source: source, signal: signal)
        let runtime = LazyDefaultAIRecommendationRuntime(
            providerRegistry: registry,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            debounceMilliseconds: 0
        )
        let request = AIRecommendationRequest(rawInput: "nihao", compositionID: 1)

        let first = await runtime.recommendation(for: request)
        source.set(
            revision: 2,
            fingerprint: String(repeating: "b", count: 64),
            provider: providerB
        )
        signal.send(2)
        let second = await runtime.recommendation(for: request)
        let providerACount = await providerA.requestCount
        let providerBCount = await providerB.requestCount

        XCTAssertEqual(first.readyDisplayText, "A result")
        XCTAssertEqual(second.readyDisplayText, "B result")
        XCTAssertEqual(providerACount, 1)
        XCTAssertEqual(providerBCount, 1)
    }

    func testEligibleDispatchUsesDiskRevisionFallbackWhenNotificationIsMissed() async {
        let providerA = NamedLLMProvider(name: "provider-a", responseText: "A")
        let providerB = NamedLLMProvider(name: "provider-b", responseText: "B")
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: providerA
        )
        let registry = makeRegistry(source: source)
        let first = await registry.leaseForEligibleDispatch()

        source.set(
            revision: 2,
            fingerprint: String(repeating: "b", count: 64),
            provider: providerB
        )
        let second = await registry.leaseForEligibleDispatch()

        XCTAssertEqual(first.generation, 1)
        XCTAssertEqual(second.generation, 2)
        XCTAssertEqual(second.revision, 2)
        XCTAssertEqual(second.provider?.providerName, "provider-b")
    }

    func testNewDiskRevisionFailsClosedWhenRuntimeReloadIsTransientlyUnavailable() async {
        let providerB = NamedLLMProvider(name: "provider-b", responseText: "B")
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: NamedLLMProvider(name: "provider-a", responseText: "A")
        )
        let registry = makeRegistry(source: source)
        _ = await registry.leaseForEligibleDispatch()

        source.set(
            revision: 2,
            fingerprint: String(repeating: "b", count: 64),
            provider: providerB
        )
        source.setRuntimeLoadEnabled(false)
        let unavailable = await registry.leaseForEligibleDispatch()

        XCTAssertEqual(unavailable.revision, 2)
        XCTAssertNil(unavailable.provider)

        source.setRuntimeLoadEnabled(true)
        let recovered = await registry.leaseForEligibleDispatch()
        XCTAssertEqual(recovered.provider?.providerName, "provider-b")
    }

    func testGenerationChangeClearsProviderHealthAndCapabilityState() async {
        let providerA = AlwaysFailingGenerationLLMProvider(name: "provider-a")
        let providerB = NamedLLMProvider(name: "provider-b", responseText: "B result")
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: providerA
        )
        let registry = makeRegistry(
            source: source,
            capabilityReset: { await ProviderRuntimeCapabilityState.reset() }
        )
        let runtime = LazyDefaultAIRecommendationRuntime(
            providerRegistry: registry,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            debounceMilliseconds: 0
        )
        let request = AIRecommendationRequest(rawInput: "nihao", compositionID: 1)

        for _ in 0..<3 {
            _ = await runtime.recommendation(for: request)
        }
        await StructuredOutputCapabilityCache.shared.markUnsupported("old", mode: .promptOnly)
        let oldCapability = await StructuredOutputCapabilityCache.shared.fallbackMode(for: "old")
        XCTAssertNotNil(oldCapability)

        source.set(
            revision: 2,
            fingerprint: String(repeating: "b", count: 64),
            provider: providerB
        )
        let current = await runtime.recommendation(for: request)
        let capability = await StructuredOutputCapabilityCache.shared.fallbackMode(for: "old")

        XCTAssertEqual(current.readyDisplayText, "B result")
        XCTAssertNil(capability)
    }

    func testGenerationChangeCancelsInFlightRecommendationAndDropsOldResult() async throws {
        let providerA = SuspendedGenerationLLMProvider(name: "provider-a")
        let providerB = NamedLLMProvider(name: "provider-b", responseText: "B result")
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: providerA
        )
        let signal = TestProviderRevisionSignal()
        let registry = makeRegistry(source: source, signal: signal)
        let runtime = LazyDefaultAIRecommendationRuntime(
            providerRegistry: registry,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            debounceMilliseconds: 0
        )
        let request = AIRecommendationRequest(rawInput: "nihao", compositionID: 1)

        let oldRequest = Task { await runtime.recommendation(for: request) }
        try await waitUntil { await providerA.requestCount == 1 }
        source.set(
            revision: 2,
            fingerprint: String(repeating: "b", count: 64),
            provider: providerB
        )
        signal.send(2)
        try await waitUntil { await providerA.cancellationCount == 1 }
        await providerA.finish(responseText: "A stale result")
        let oldState = await oldRequest.value

        XCTAssertEqual(oldState, .stale)
        let current = await runtime.recommendation(for: request)
        XCTAssertEqual(current.readyDisplayText, "B result")
    }

    func testMissedNotificationRevisionChangeDropsSuspendedWork() async throws {
        let providerA = SuspendedGenerationLLMProvider(name: "provider-a")
        let providerB = NamedLLMProvider(name: "provider-b", responseText: "B result")
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: providerA
        )
        let registry = makeRegistry(source: source)
        let runtime = LazyDefaultAIRecommendationRuntime(
            providerRegistry: registry,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            debounceMilliseconds: 0
        )
        let request = AIRecommendationRequest(rawInput: "nihao", compositionID: 1)

        let oldRequest = Task { await runtime.recommendation(for: request) }
        try await waitUntil { await providerA.requestCount == 1 }
        source.set(
            revision: 2,
            fingerprint: String(repeating: "b", count: 64),
            provider: providerB
        )
        await providerA.finish(responseText: "A stale result")

        let oldState = await oldRequest.value
        XCTAssertEqual(oldState, .stale)
        let current = await runtime.recommendation(for: request)
        XCTAssertEqual(current.readyDisplayText, "B result")
    }

    func testMissedNotificationRevisionChangeDropsSuspendedFailure() async throws {
        let providerA = SuspendedGenerationLLMProvider(name: "provider-a")
        let providerB = NamedLLMProvider(name: "provider-b", responseText: "B result")
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: providerA
        )
        let registry = makeRegistry(source: source)
        let runtime = LazyDefaultAIRecommendationRuntime(
            providerRegistry: registry,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            debounceMilliseconds: 0
        )
        let request = AIRecommendationRequest(rawInput: "nihao", compositionID: 1)

        let oldRequest = Task { await runtime.recommendation(for: request) }
        try await waitUntil { await providerA.requestCount == 1 }
        source.set(
            revision: 2,
            fingerprint: String(repeating: "b", count: 64),
            provider: providerB
        )
        await providerA.finishWithFailure()

        let oldState = await oldRequest.value
        XCTAssertEqual(oldState, .stale)
        let current = await runtime.recommendation(for: request)
        XCTAssertEqual(current.readyDisplayText, "B result")
    }

    func testMissedNotificationRevisionChangeRejectsCommitAfterPerform() async throws {
        let providerB = NamedLLMProvider(name: "provider-b", responseText: "B result")
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: NamedLLMProvider(name: "provider-a", responseText: "A result")
        )
        let registry = makeRegistry(source: source)
        let lease = await registry.leaseForEligibleDispatch()

        let performed = try await registry.perform(using: lease) { _ in "performed" }
        XCTAssertEqual(performed, "performed")
        source.set(
            revision: 2,
            fingerprint: String(repeating: "b", count: 64),
            provider: providerB
        )

        do {
            try await registry.commitIfCurrent(using: lease) {
                XCTFail("stale provider work must not commit")
            }
            XCTFail("expected stale generation")
        } catch {
            XCTAssertEqual(error as? ProviderRuntimeRegistryError, .staleGeneration)
        }
        let current = await registry.leaseForEligibleDispatch()
        XCTAssertEqual(current.provider?.providerName, "provider-b")
    }

    func testIneligibleRecommendationDoesNotReadProviderRevisionOrProfiles() async {
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: NamedLLMProvider(name: "provider-a", responseText: "unused")
        )
        let runtime = LazyDefaultAIRecommendationRuntime(
            providerRegistry: makeRegistry(source: source),
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            debounceMilliseconds: 0
        )

        let state = await runtime.recommendation(
            for: AIRecommendationRequest(rawInput: "ni", compositionID: 1)
        )

        XCTAssertEqual(state, .ineligible(reason: "AI 无推荐"))
        XCTAssertEqual(source.revisionReadCount, 0)
        XCTAssertEqual(source.runtimeLoadCount, 0)
    }

    func testProviderFingerprintAndDiagnosticsDoNotExposeConfigurationSecrets() async throws {
        let profile = ProviderProfile(
            displayName: "Private",
            kind: .openAIResponses,
            baseURL: URL(string: "https://user:pass@example.com/v1?api_key=URL_SECRET")!,
            model: "private-model",
            secretName: "private-secret",
            isDefault: true
        )
        let loader = ProviderRuntimeLoader(
            profileStore: StaticProviderProfileStore(
                file: ProviderProfilesFile(revision: 9, profiles: [profile])
            ),
            secretStore: DictionarySecretStore(values: ["private-secret": "KEY_SECRET"]),
            providerBuilder: { configuration in
                NamedLLMProvider(name: configuration.kind.rawValue, responseText: "unused")
            }
        )
        let loaded = try XCTUnwrap(loader.loadDefaultProviderRuntime())
        let event = ProviderRuntimeDiagnosticEvent(
            stage: .loaded,
            revision: loaded.revision,
            generation: 3,
            fingerprint: loaded.fingerprint,
            providerConfigured: loaded.provider != nil
        )
        let line = InputDebugDiagnostics.formatLine(
            category: .ai,
            fields: InputDebugProviderRuntimeDiagnosticSink.fields(for: event)
        )

        XCTAssertEqual(loaded.fingerprint.count, 64)
        XCTAssertTrue(loaded.fingerprint.allSatisfy(\.isHexDigit))
        XCTAssertFalse(line.contains("example.com"))
        XCTAssertFalse(line.contains("URL_SECRET"))
        XCTAssertFalse(line.contains("KEY_SECRET"))
        XCTAssertFalse(line.contains("private-model"))
        XCTAssertTrue(line.contains("providerFingerprint=\(loaded.fingerprint.prefix(12))"))
    }

    func testSharedRequestGateClampsRetryAfterAndFencesGeneration() async {
        let now = Date()
        let gate = ProviderRequestGate(now: { now })
        do {
            _ = try await gate.execute(providerIdentity: "provider-config-secret", generation: 1) {
                throw ProviderRateLimitError(retryAfterSeconds: 1, bodyByteCount: 24)
            } as LLMResponse
            XCTFail("expected rate limit")
        } catch is ProviderRateLimitError {
            // Expected.
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        let deadline = await gate.cooldownDeadline(providerIdentity: "provider-config-secret", generation: 1)
        XCTAssertEqual(deadline?.timeIntervalSince(now), 15, accuracy: 0.001)
        do {
            _ = try await gate.execute(providerIdentity: "provider-config-secret", generation: 1) {
                LLMResponse(candidates: [])
            } as LLMResponse
            XCTFail("expected cooldown")
        } catch ProviderRequestGateError.cooldown {
            // Expected.
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        await gate.invalidate(providerIdentity: "provider-config-secret", generation: 1)
        do {
            _ = try await gate.execute(providerIdentity: "provider-config-secret", generation: 1) {
                LLMResponse(candidates: [])
            } as LLMResponse
            XCTFail("expected stale generation")
        } catch ProviderRequestGateError.staleGeneration {
            // Expected.
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

final class ProviderRuntimeTestSource: @unchecked Sendable {
    private let lock = NSLock()
    private var revision: UInt64
    private var fingerprint: String
    private var provider: (any LLMProvider)?
    private var runtimeLoadEnabled = true
    private var revisionReads = 0
    private var runtimeLoads = 0

    init(revision: UInt64, fingerprint: String, provider: (any LLMProvider)?) {
        self.revision = revision
        self.fingerprint = fingerprint
        self.provider = provider
    }

    func loadRevision() -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        revisionReads += 1
        return revision
    }

    func loadRuntime() -> ProviderRuntimeLoadResult? {
        lock.lock()
        defer { lock.unlock() }
        runtimeLoads += 1
        guard runtimeLoadEnabled else {
            return nil
        }
        return ProviderRuntimeLoadResult(
            revision: revision,
            fingerprint: fingerprint,
            provider: provider
        )
    }

    func set(revision: UInt64, fingerprint: String, provider: (any LLMProvider)?) {
        lock.lock()
        self.revision = revision
        self.fingerprint = fingerprint
        self.provider = provider
        lock.unlock()
    }

    func setRuntimeLoadEnabled(_ enabled: Bool) {
        lock.lock()
        runtimeLoadEnabled = enabled
        lock.unlock()
    }

    var revisionReadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return revisionReads
    }

    var runtimeLoadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return runtimeLoads
    }
}

final class TestProviderRevisionSignal: @unchecked Sendable {
    let stream: AsyncStream<UInt64>
    private let continuation: AsyncStream<UInt64>.Continuation

    init() {
        let pair = Self.makeStream()
        self.stream = pair.stream
        self.continuation = pair.continuation
    }

    func send(_ revision: UInt64) {
        continuation.yield(revision)
    }

    private static func makeStream() -> (
        stream: AsyncStream<UInt64>,
        continuation: AsyncStream<UInt64>.Continuation
    ) {
        var continuation: AsyncStream<UInt64>.Continuation?
        let stream = AsyncStream<UInt64> { continuation = $0 }
        return (stream, continuation!)
    }
}

actor NamedLLMProvider: LLMProvider {
    nonisolated let providerName: String
    private let responseText: String
    private var requests: [LLMRequest] = []

    init(name: String, responseText: String) {
        self.providerName = name
        self.responseText = responseText
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        requests.append(request)
        return LLMResponse(candidates: [LLMCandidate(text: responseText, confidence: 0.9)])
    }

    var requestCount: Int { requests.count }
    var recordedRequests: [LLMRequest] { requests }
}

actor SuspendedGenerationLLMProvider: LLMProvider {
    nonisolated let providerName: String
    private var continuation: CheckedContinuation<LLMResponse, Error>?
    private(set) var requestCount = 0
    private(set) var cancellationCount = 0

    init(name: String) {
        self.providerName = name
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        requestCount += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        } onCancel: {
            Task { await self.recordCancellation() }
        }
    }

    func finish(responseText: String) {
        continuation?.resume(
            returning: LLMResponse(candidates: [LLMCandidate(text: responseText, confidence: 0.9)])
        )
        continuation = nil
    }

    func finishWithFailure() {
        continuation?.resume(throwing: ProviderError.httpStatus(503, "unavailable"))
        continuation = nil
    }

    private func recordCancellation() {
        cancellationCount += 1
    }
}

func makeRegistry(
    source: ProviderRuntimeTestSource,
    signal: TestProviderRevisionSignal = TestProviderRevisionSignal(),
    capabilityReset: @escaping ProviderRuntimeRegistry.CapabilityReset = {},
    diagnosticSink: any ProviderRuntimeDiagnosticSink = NoopProviderRuntimeDiagnosticSink()
) -> ProviderRuntimeRegistry {
    ProviderRuntimeRegistry(
        revisionLoader: { source.loadRevision() },
        runtimeLoader: { source.loadRuntime() },
        revisionUpdates: { signal.stream },
        capabilityReset: capabilityReset,
        diagnosticSink: diagnosticSink
    )
}

actor AlwaysFailingGenerationLLMProvider: LLMProvider {
    nonisolated let providerName: String

    init(name: String) {
        self.providerName = name
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        throw ProviderError.httpStatus(503, "unavailable")
    }
}

func waitUntil(
    timeout: TimeInterval = 2,
    condition: @escaping @Sendable () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("condition was not satisfied before timeout")
}

private struct StaticProviderProfileStore: ProviderProfileStore {
    let file: ProviderProfilesFile

    func loadProfiles() throws -> ProviderProfilesFile { file }
    func saveProfiles(_ profiles: ProviderProfilesFile) throws {}
}

private extension AIRecommendationState {
    var readyDisplayText: String? {
        guard case .ready(let candidate) = self else {
            return nil
        }
        return candidate.displayText
    }
}
