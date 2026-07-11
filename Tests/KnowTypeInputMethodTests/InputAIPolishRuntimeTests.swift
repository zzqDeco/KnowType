import Foundation
import KnowTypeAI
import KnowTypeCore
import KnowTypeProviders
@testable import KnowTypeInputMethod
import XCTest

@MainActor
final class InputAIPolishRuntimeTests: XCTestCase {
    func testRequestDispatchesExactlyOnceWithPolishTaskAndKeepsFullRewrite() async throws {
        let providerRuntime = RecordingPolishProviderRuntime(
            response: LLMResponse(candidates: [
                LLMCandidate(text: "这个接口的响应速度偏慢。", confidence: 0.93)
            ])
        )
        let diagnosticSink = RecordingPolishDiagnosticSink()
        let runtime = InputAIPolishRuntime(
            providerRuntime: providerRuntime,
            diagnosticSink: diagnosticSink
        )
        let snapshot = PolishSnapshotBox(rawInput: "我觉得这个接口慢", compositionID: 7, rawRevision: 11)
        let states = PolishStateRecorder()

        let initial = runtime.request(
            context: context(snapshot: snapshot),
            currentSnapshot: { snapshot.value },
            onStateChange: { states.append($0) }
        )

        guard case .pending(let initialBinding) = initial else {
            return XCTFail("expected immediate pending state")
        }
        XCTAssertNil(initialBinding.providerGeneration)
        let becameReady = await waitUntil { runtime.currentState.candidates.count == 1 }
        XCTAssertTrue(becameReady)

        let requests = await providerRuntime.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.task, .polish)
        XCTAssertEqual(requests.first?.rawInput, "我觉得这个接口慢")
        XCTAssertNil(requests.first?.lockedPrefix)
        XCTAssertTrue(requests.first?.candidateHints.isEmpty == true)
        XCTAssertEqual(runtime.currentState.candidates.first?.text, "这个接口的响应速度偏慢。")
        XCTAssertEqual(runtime.currentState.binding?.providerGeneration, 9)
        XCTAssertTrue(states.values.contains { state in
            if case .pending(let binding) = state {
                return binding.providerGeneration == 9
            }
            return false
        })
        XCTAssertEqual(
            diagnosticSink.events.map(\.stage),
            [.polishRequested, .polishReady]
        )
        XCTAssertEqual(diagnosticSink.events.last?.rawLength, snapshot.value.rawInput.count)
        XCTAssertEqual(diagnosticSink.events.last?.candidateCount, 1)

        let accepted = PolishCandidateRecorder()
        XCTAssertTrue(
            runtime.acceptCandidate(
                at: 0,
                currentSnapshot: { snapshot.value },
                onStateChange: { _ in },
                onAccept: { accepted.append($0) }
            )
        )
        let acceptanceCompleted = await waitUntil { accepted.values.count == 1 }
        XCTAssertTrue(acceptanceCompleted)
        XCTAssertEqual(diagnosticSink.events.last?.stage, .polishAccepted)
        XCTAssertEqual(diagnosticSink.events.last?.candidateCount, 1)
    }

    func testPrivacyGateRejectsProtectedAppAndSecretWithoutProviderRequest() async {
        let providerRuntime = RecordingPolishProviderRuntime()
        let runtime = InputAIPolishRuntime(providerRuntime: providerRuntime)
        let protectedSnapshot = PolishSnapshotBox(rawInput: "我觉得这个接口慢", compositionID: 1, rawRevision: 1)

        let protectedState = runtime.request(
            context: context(snapshot: protectedSnapshot, appBundleID: "com.apple.Terminal"),
            currentSnapshot: { protectedSnapshot.value },
            onStateChange: { _ in }
        )
        guard case .unavailable(_, let protectedReason) = protectedState else {
            return XCTFail("expected protected app to be unavailable")
        }
        XCTAssertEqual(protectedReason, "当前内容不可润色")

        let secretSnapshot = PolishSnapshotBox(
            rawInput: "token=abcd1234",
            compositionID: 2,
            rawRevision: 2
        )
        let secretState = runtime.request(
            context: context(snapshot: secretSnapshot),
            currentSnapshot: { secretSnapshot.value },
            onStateChange: { _ in }
        )
        guard case .unavailable = secretState else {
            return XCTFail("expected secret-like input to be unavailable")
        }

        let disabledSnapshot = PolishSnapshotBox(
            rawInput: "需要润色的句子",
            compositionID: 7,
            rawRevision: 7
        )
        let disabledState = runtime.request(
            context: context(snapshot: disabledSnapshot, cloudAIEnabled: false),
            currentSnapshot: { disabledSnapshot.value },
            onStateChange: { _ in }
        )
        guard case .unavailable(_, let disabledReason) = disabledState else {
            return XCTFail("expected disabled cloud AI to be unavailable")
        }
        XCTAssertEqual(disabledReason, "AI 润色已禁用")

        let rawLevelZeroSnapshot = PolishSnapshotBox(
            rawInput: "https://example.com/private",
            compositionID: 8,
            rawRevision: 8
        )
        let rawLevelZeroState = runtime.request(
            context: InputAIPolishRequestContext(
                text: "普通候选文本",
                rawInput: rawLevelZeroSnapshot.value.rawInput,
                appBundleID: "com.example.Editor",
                locale: .zhCN,
                compositionID: rawLevelZeroSnapshot.value.compositionID,
                rawRevision: rawLevelZeroSnapshot.value.rawRevision,
                hasActiveComposition: true,
                cloudAIEnabled: true
            ),
            currentSnapshot: { rawLevelZeroSnapshot.value },
            onStateChange: { _ in }
        )
        guard case .unavailable(_, let rawLevelZeroReason) = rawLevelZeroState else {
            return XCTFail("expected raw Level 0 input to be unavailable")
        }
        XCTAssertEqual(rawLevelZeroReason, "当前内容不可润色")
        let requestCount = await providerRuntime.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testPendingAndProviderErrorRemainNonblockingAndPublishUnavailable() async {
        let providerRuntime = RecordingPolishProviderRuntime(
            delayNanoseconds: 200_000_000,
            error: ProviderError.httpStatus(503, "unavailable")
        )
        let runtime = InputAIPolishRuntime(providerRuntime: providerRuntime)
        let snapshot = PolishSnapshotBox(rawInput: "需要润色的句子", compositionID: 3, rawRevision: 5)

        let startedAt = ContinuousClock.now
        let initial = runtime.request(
            context: context(snapshot: snapshot),
            currentSnapshot: { snapshot.value },
            onStateChange: { _ in }
        )
        let elapsed = startedAt.duration(to: .now)

        XCTAssertLessThan(elapsed, .milliseconds(50))
        guard case .pending = initial else {
            return XCTFail("expected pending state")
        }
        let becameUnavailable = await waitUntil {
            if case .unavailable(_, let reason) = runtime.currentState {
                return reason == "AI 润色暂不可用"
            }
            return false
        }
        XCTAssertTrue(becameUnavailable)
    }

    func testChangedCompositionDropsDelayedResult() async {
        let providerRuntime = RecordingPolishProviderRuntime(delayNanoseconds: 150_000_000)
        let runtime = InputAIPolishRuntime(providerRuntime: providerRuntime)
        let snapshot = PolishSnapshotBox(rawInput: "需要润色的句子", compositionID: 4, rawRevision: 8)

        _ = runtime.request(
            context: context(snapshot: snapshot),
            currentSnapshot: { snapshot.value },
            onStateChange: { _ in }
        )
        snapshot.value = InputAIPolishCompositionSnapshot(
            rawInput: "需要润色的句子x",
            compositionID: 4,
            rawRevision: 9
        )

        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(runtime.currentState.candidates.isEmpty)
    }

    func testProviderGenerationChangeDropsResultAndRejectsReadyAcceptance() async {
        let providerRuntime = RecordingPolishProviderRuntime(performStaleGeneration: true)
        let runtime = InputAIPolishRuntime(providerRuntime: providerRuntime)
        let snapshot = PolishSnapshotBox(rawInput: "需要润色的句子", compositionID: 5, rawRevision: 10)

        _ = runtime.request(
            context: context(snapshot: snapshot),
            currentSnapshot: { snapshot.value },
            onStateChange: { _ in }
        )
        let staleResultDropped = await waitUntil { runtime.currentState == .idle }
        XCTAssertTrue(staleResultDropped)
        XCTAssertTrue(runtime.currentState.candidates.isEmpty)

        let acceptanceRuntime = RecordingPolishProviderRuntime()
        let readyRuntime = InputAIPolishRuntime(providerRuntime: acceptanceRuntime)
        _ = readyRuntime.request(
            context: context(snapshot: snapshot),
            currentSnapshot: { snapshot.value },
            onStateChange: { _ in }
        )
        let acceptanceBecameReady = await waitUntil { !readyRuntime.currentState.candidates.isEmpty }
        XCTAssertTrue(acceptanceBecameReady)
        await acceptanceRuntime.setAcceptanceStaleGeneration(true)
        let accepted = PolishCandidateRecorder()
        XCTAssertTrue(
            readyRuntime.acceptCandidate(
                at: 0,
                currentSnapshot: { snapshot.value },
                onStateChange: { _ in },
                onAccept: { accepted.append($0) }
            )
        )
        let staleAcceptanceDropped = await waitUntil { readyRuntime.currentState == .idle }
        XCTAssertTrue(staleAcceptanceDropped)
        XCTAssertTrue(accepted.values.isEmpty)
    }

    func testProviderRevisionNotificationCancelsReadyCandidate() async {
        let providerRuntime = RecordingPolishProviderRuntime()
        let diagnosticSink = RecordingPolishDiagnosticSink()
        let runtime = InputAIPolishRuntime(
            providerRuntime: providerRuntime,
            diagnosticSink: diagnosticSink
        )
        let snapshot = PolishSnapshotBox(rawInput: "需要润色的句子", compositionID: 6, rawRevision: 12)

        _ = runtime.request(
            context: context(snapshot: snapshot),
            currentSnapshot: { snapshot.value },
            onStateChange: { _ in }
        )
        let becameReady = await waitUntil { !runtime.currentState.candidates.isEmpty }
        XCTAssertTrue(becameReady)

        await providerRuntime.emitRevision(5)

        let revisionChangeDroppedCandidate = await waitUntil { runtime.currentState == .idle }
        XCTAssertTrue(revisionChangeDroppedCandidate)
        XCTAssertEqual(diagnosticSink.events.last?.stage, .polishStaleDropped)
        XCTAssertEqual(diagnosticSink.events.last?.reason, "provider_revision")
    }

    private func context(
        snapshot: PolishSnapshotBox,
        appBundleID: String? = "com.example.Editor",
        cloudAIEnabled: Bool = true
    ) -> InputAIPolishRequestContext {
        InputAIPolishRequestContext(
            text: snapshot.value.rawInput,
            rawInput: snapshot.value.rawInput,
            appBundleID: appBundleID,
            locale: .zhCN,
            compositionID: snapshot.value.compositionID,
            rawRevision: snapshot.value.rawRevision,
            hasActiveComposition: true,
            cloudAIEnabled: cloudAIEnabled
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}

private final class PolishSnapshotBox: @unchecked Sendable {
    var value: InputAIPolishCompositionSnapshot

    init(rawInput: String, compositionID: Int, rawRevision: Int) {
        self.value = InputAIPolishCompositionSnapshot(
            rawInput: rawInput,
            compositionID: compositionID,
            rawRevision: rawRevision
        )
    }
}

private final class RecordingPolishDiagnosticSink: AIRecommendationDiagnosticSink, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [AIRecommendationDiagnosticEvent] = []

    func record(_ event: AIRecommendationDiagnosticEvent) {
        lock.lock()
        recordedEvents.append(event)
        lock.unlock()
    }

    var events: [AIRecommendationDiagnosticEvent] {
        lock.lock()
        let events = recordedEvents
        lock.unlock()
        return events
    }
}

@MainActor
private final class PolishStateRecorder {
    private(set) var values: [InputAIPolishState] = []

    func append(_ state: InputAIPolishState) {
        values.append(state)
    }
}

@MainActor
private final class PolishCandidateRecorder {
    private(set) var values: [InputAIPolishCandidate] = []

    func append(_ candidate: InputAIPolishCandidate) {
        values.append(candidate)
    }
}

private actor PolishLeaseProvider: LLMProvider {
    nonisolated let providerName = "polish-test"

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        LLMResponse(candidates: [])
    }
}

private actor RecordingPolishProviderRuntime: InputAIPolishProviderRuntime {
    private nonisolated let revisionStream: AsyncStream<UInt64>
    private nonisolated let revisionContinuation: AsyncStream<UInt64>.Continuation
    private let provider = PolishLeaseProvider()
    private let response: LLMResponse
    private let delayNanoseconds: UInt64
    private let error: Error?
    private let performStaleGeneration: Bool
    private var acceptanceStaleGeneration = false
    private(set) var requests: [LLMRequest] = []

    init(
        response: LLMResponse = LLMResponse(candidates: [LLMCandidate(text: "润色结果", confidence: 0.9)]),
        delayNanoseconds: UInt64 = 0,
        error: Error? = nil,
        performStaleGeneration: Bool = false
    ) {
        var continuation: AsyncStream<UInt64>.Continuation?
        self.revisionStream = AsyncStream { continuation = $0 }
        self.revisionContinuation = continuation!
        self.response = response
        self.delayNanoseconds = delayNanoseconds
        self.error = error
        self.performStaleGeneration = performStaleGeneration
    }

    var requestCount: Int {
        requests.count
    }

    func leaseForEligibleDispatch() async -> ProviderRuntimeLease {
        ProviderRuntimeLease(
            revision: 4,
            generation: 9,
            fingerprint: String(repeating: "a", count: 64),
            provider: provider
        )
    }

    func performPolish(_ request: LLMRequest, using lease: ProviderRuntimeLease) async throws -> LLMResponse {
        requests.append(request)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if performStaleGeneration {
            throw ProviderRuntimeRegistryError.staleGeneration
        }
        if let error {
            throw error
        }
        return response
    }

    func validateForAcceptance(_ lease: ProviderRuntimeLease) async throws {
        if acceptanceStaleGeneration {
            throw ProviderRuntimeRegistryError.staleGeneration
        }
    }

    func setAcceptanceStaleGeneration(_ value: Bool) {
        acceptanceStaleGeneration = value
    }

    nonisolated func polishRevisionUpdates() async -> AsyncStream<UInt64> {
        revisionStream
    }

    func emitRevision(_ revision: UInt64) {
        revisionContinuation.yield(revision)
    }
}
