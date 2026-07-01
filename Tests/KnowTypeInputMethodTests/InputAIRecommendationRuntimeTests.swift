import KnowTypeAI
import KnowTypeCore
@testable import KnowTypeInputMethod
import XCTest

final class InputAIRecommendationRuntimeTests: XCTestCase {
    @MainActor
    func testSkipPathsDoNotCallProviderAndRecordDiagnostics() async {
        let provider = RecordingRuntimeAIRecommendationProvider()
        let diagnosticSink = RecordingRuntimeDiagnosticSink()
        let runtime = InputAIRecommendationRuntime(
            provider: provider,
            providerAvailability: nil,
            hasEagerProvider: true,
            diagnosticSink: diagnosticSink
        )

        let emptyState = runtime.schedule(
            context: context(rawInput: ""),
            currentSnapshot: { snapshot(rawInput: "") },
            onStateChange: { _ in XCTFail("skip paths must not publish async state") }
        )
        let shortState = runtime.schedule(
            context: context(rawInput: "ab"),
            currentSnapshot: { snapshot(rawInput: "ab") },
            onStateChange: { _ in XCTFail("skip paths must not publish async state") }
        )
        let secretState = runtime.schedule(
            context: context(rawInput: "sk-proj-abcdefghijklmnopqrstuvwxyz"),
            currentSnapshot: { snapshot(rawInput: "sk-proj-abcdefghijklmnopqrstuvwxyz") },
            onStateChange: { _ in XCTFail("skip paths must not publish async state") }
        )
        let disabledState = runtime.schedule(
            context: context(rawInput: "abc", cloudContinuationEnabled: false),
            currentSnapshot: { snapshot(rawInput: "abc") },
            onStateChange: { _ in XCTFail("skip paths must not publish async state") }
        )

        XCTAssertEqual(emptyState, .idle)
        XCTAssertEqual(shortState, .idle)
        XCTAssertEqual(secretState, .ineligible(reason: "AI 已禁用"))
        XCTAssertEqual(disabledState, .ineligible(reason: "AI 已关闭"))
        let requests = await provider.requests
        XCTAssertEqual(requests.count, 0)
        XCTAssertTrue(diagnosticSink.events.contains { $0.stage == .skippedIneligible })
        XCTAssertTrue(diagnosticSink.events.contains { $0.stage == .skippedPrefixTooShort })
        XCTAssertTrue(diagnosticSink.events.contains { $0.stage == .skippedProtectedText })
        XCTAssertTrue(diagnosticSink.events.contains { $0.stage == .skippedDisabled })
    }

    @MainActor
    func testNoProviderSkipReturnsExistingNoProviderStates() {
        let configuredUnavailableRuntime = InputAIRecommendationRuntime(
            provider: RecordingRuntimeAIRecommendationProvider(),
            providerAvailability: nil,
            hasEagerProvider: false,
            diagnosticSink: RecordingRuntimeDiagnosticSink()
        )
        let configuredUnavailableState = configuredUnavailableRuntime.schedule(
            context: context(
                rawInput: "abc",
                canRequestAIRecommendations: false
            ),
            currentSnapshot: { snapshot(rawInput: "abc") },
            onStateChange: { _ in XCTFail("skip paths must not publish async state") }
        )
        XCTAssertEqual(configuredUnavailableState, .unavailable(reason: "AI 未配置"))

        let unavailableRuntime = InputAIRecommendationRuntime(
            provider: nil,
            providerAvailability: nil,
            hasEagerProvider: false,
            diagnosticSink: RecordingRuntimeDiagnosticSink()
        )
        let unavailableState = unavailableRuntime.schedule(
            context: context(
                rawInput: "abc",
                canRequestAIRecommendations: false,
                hasRecommendationProvider: false
            ),
            currentSnapshot: { snapshot(rawInput: "abc") },
            onStateChange: { _ in XCTFail("skip paths must not publish async state") }
        )
        XCTAssertEqual(unavailableState, .idle)

        let lazyMissingRuntime = InputAIRecommendationRuntime(
            provider: nil,
            providerAvailability: nil,
            hasEagerProvider: false,
            diagnosticSink: RecordingRuntimeDiagnosticSink()
        )
        let lazyMissingState = lazyMissingRuntime.schedule(
            context: context(
                rawInput: "abc",
                canRequestAIRecommendations: true,
                hasRecommendationProvider: false
            ),
            currentSnapshot: { snapshot(rawInput: "abc") },
            onStateChange: { _ in XCTFail("skip paths must not publish async state") }
        )
        XCTAssertEqual(lazyMissingState, .idle)
    }

    @MainActor
    func testSchedulePublishesPendingAndBuildsRequestWithoutCandidateHints() async throws {
        let lexicalContext = LexicalContextSnapshot(
            terms: [LexicalContextTerm(text: "JSON", score: 1, source: "test")],
            recentCommits: ["最近提交"],
            toneProfile: ToneProfile(register: "technical"),
            sourceSummary: ["test: 1"]
        )
        let feedbackContext = AIAcceptedFeedbackContextSnapshot(
            summary: AIAcceptedFeedbackSummary(
                historyHash: "feedback",
                feedbackCount: 1,
                strongCount: 1,
                avoidTerms: ["啰嗦"],
                styleAdjustments: ["更短"],
                replacementPatterns: ["A -> B"],
                sourceSummary: ["feedback: 1"]
            )
        )
        let provider = RecordingRuntimeAIRecommendationProvider(response: readyState("我觉得继续推进"))
        let diagnosticSink = RecordingRuntimeDiagnosticSink()
        let runtime = InputAIRecommendationRuntime(
            provider: provider,
            providerAvailability: nil,
            hasEagerProvider: true,
            diagnosticSink: diagnosticSink
        )
        var states: [AIRecommendationState] = []
        let currentSnapshot = snapshot(rawInput: "wojuede", compositionID: 7, rawRevision: 3)

        let initialState = runtime.schedule(
            context: context(
                rawInput: "wojuede",
                lockedPrefix: "我觉得",
                appBundleID: "com.example.editor",
                locale: .zhCN,
                compositionID: 7,
                rawRevision: 3,
                lexicalContext: lexicalContext,
                feedbackContext: feedbackContext
            ),
            currentSnapshot: { currentSnapshot },
            onStateChange: { states.append($0) }
        )

        guard case .pending = initialState else {
            return XCTFail("Expected pending state")
        }
        let didPublishState = await waitUntil { !states.isEmpty }
        XCTAssertTrue(didPublishState)
        let requests = await provider.requests
        let request = try XCTUnwrap(requests.last)

        XCTAssertEqual(request.rawInput, "wojuede")
        XCTAssertEqual(request.lockedPrefix, "我觉得")
        XCTAssertEqual(request.candidateHints, [])
        XCTAssertEqual(request.appBundleID, "com.example.editor")
        XCTAssertEqual(request.appName, "com.example.editor")
        XCTAssertEqual(request.locale, .zhCN)
        XCTAssertEqual(request.compositionID, 7)
        XCTAssertEqual(request.lexicalContext, lexicalContext)
        XCTAssertEqual(request.feedbackContext, feedbackContext)
        XCTAssertTrue(diagnosticSink.events.contains { $0.stage == .scheduled })
        XCTAssertTrue(diagnosticSink.events.contains { $0.stage == .stateApplied && $0.reason == "ready" })
    }

    @MainActor
    func testRescheduleCancelsPreviousActiveRequest() async {
        let provider = RecordingRuntimeAIRecommendationProvider(
            response: readyState("旧结果"),
            delayNanoseconds: 5_000_000_000
        )
        let diagnosticSink = RecordingRuntimeDiagnosticSink()
        let runtime = InputAIRecommendationRuntime(
            provider: provider,
            providerAvailability: nil,
            hasEagerProvider: true,
            diagnosticSink: diagnosticSink
        )

        let firstState = runtime.schedule(
            context: context(rawInput: "abc", compositionID: 1, rawRevision: 1),
            currentSnapshot: { snapshot(rawInput: "abc", compositionID: 1, rawRevision: 1) },
            onStateChange: { _ in XCTFail("cancelled request must not publish state") }
        )
        let firstRequestID = pendingRequestID(firstState)

        let secondState = runtime.schedule(
            context: context(rawInput: "abcd", compositionID: 1, rawRevision: 2),
            currentSnapshot: { snapshot(rawInput: "abcd", compositionID: 1, rawRevision: 2) },
            onStateChange: { _ in }
        )
        let secondRequestID = pendingRequestID(secondState)

        XCTAssertNotNil(firstRequestID)
        XCTAssertNotNil(secondRequestID)
        XCTAssertNotEqual(firstRequestID, secondRequestID)
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .cancelPrevious
                && $0.requestID == firstRequestID
                && $0.reason == "new_schedule"
        })
        _ = runtime.reset(compositionID: 1, rawLength: 4, reason: "test_cleanup")
        let cancelled = await waitUntil {
            diagnosticSink.events.contains {
                $0.stage == .cancelled && $0.requestID == firstRequestID
            }
        }
        XCTAssertTrue(cancelled, "\(diagnosticSink.events)")
    }

    @MainActor
    func testStaleResultDoesNotPublishState() async {
        let provider = RecordingRuntimeAIRecommendationProvider(
            response: readyState("旧结果"),
            delayNanoseconds: 20_000_000
        )
        let diagnosticSink = RecordingRuntimeDiagnosticSink()
        let runtime = InputAIRecommendationRuntime(
            provider: provider,
            providerAvailability: nil,
            hasEagerProvider: true,
            diagnosticSink: diagnosticSink
        )
        var states: [AIRecommendationState] = []
        let currentSnapshot = RuntimeSnapshotBox(
            snapshot(rawInput: "abc", compositionID: 1, rawRevision: 1)
        )

        let state = runtime.schedule(
            context: context(rawInput: "abc", compositionID: 1, rawRevision: 1),
            currentSnapshot: { currentSnapshot.snapshot },
            onStateChange: { states.append($0) }
        )
        XCTAssertNotNil(pendingRequestID(state))
        currentSnapshot.update(snapshot(rawInput: "abc", compositionID: 1, rawRevision: 2))

        let staleDropped = await waitUntil {
            diagnosticSink.events.contains {
                $0.stage == .staleResultDropped && $0.reason == "ready"
            }
        }
        XCTAssertTrue(staleDropped, "\(diagnosticSink.events)")
        XCTAssertEqual(states, [])
    }

    @MainActor
    func testResetCancelsActiveTaskAndReturnsIdle() async {
        let provider = RecordingRuntimeAIRecommendationProvider(
            response: .unavailable(reason: "timeout"),
            delayNanoseconds: 5_000_000_000
        )
        let diagnosticSink = RecordingRuntimeDiagnosticSink()
        let runtime = InputAIRecommendationRuntime(
            provider: provider,
            providerAvailability: nil,
            hasEagerProvider: true,
            diagnosticSink: diagnosticSink
        )
        let state = runtime.schedule(
            context: context(rawInput: "abc", compositionID: 9, rawRevision: 1),
            currentSnapshot: { snapshot(rawInput: "abc", compositionID: 9, rawRevision: 1) },
            onStateChange: { _ in XCTFail("reset request must not publish state") }
        )
        let requestID = pendingRequestID(state)

        XCTAssertEqual(
            runtime.reset(compositionID: 9, rawLength: 3, reason: "composition_invalidated"),
            .idle
        )
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .cancelPrevious
                && $0.requestID == requestID
                && $0.reason == "composition_invalidated"
        })
        let cancelled = await waitUntil {
            diagnosticSink.events.contains {
                $0.stage == .cancelled
                    && $0.requestID == requestID
                    && $0.reason == "task_cancelled_before_apply"
            }
        }
        XCTAssertTrue(cancelled, "\(diagnosticSink.events)")
    }

    @MainActor
    func testHasKnownProviderUsesEagerProviderOrAvailabilitySnapshot() {
        let availability = AIRecommendationProviderAvailabilityState(.unknown)
        let lazyRuntime = InputAIRecommendationRuntime(
            provider: RecordingRuntimeAIRecommendationProvider(),
            providerAvailability: availability,
            hasEagerProvider: false,
            diagnosticSink: RecordingRuntimeDiagnosticSink()
        )
        XCTAssertFalse(lazyRuntime.hasKnownProvider)

        availability.update(.available)
        XCTAssertTrue(lazyRuntime.hasKnownProvider)

        let eagerRuntime = InputAIRecommendationRuntime(
            provider: nil,
            providerAvailability: nil,
            hasEagerProvider: true,
            diagnosticSink: RecordingRuntimeDiagnosticSink()
        )
        XCTAssertTrue(eagerRuntime.hasKnownProvider)
    }

    @MainActor
    func testShouldBuildRecommendationContextTracksProviderAvailability() {
        let availability = AIRecommendationProviderAvailabilityState(.unknown)
        let lazyRuntime = InputAIRecommendationRuntime(
            provider: RecordingRuntimeAIRecommendationProvider(),
            providerAvailability: availability,
            hasEagerProvider: false,
            diagnosticSink: RecordingRuntimeDiagnosticSink()
        )
        XCTAssertTrue(lazyRuntime.shouldBuildRecommendationContext)

        availability.update(.available)
        XCTAssertTrue(lazyRuntime.shouldBuildRecommendationContext)

        availability.update(.unavailable)
        XCTAssertFalse(lazyRuntime.shouldBuildRecommendationContext)

        let injectedProviderRuntime = InputAIRecommendationRuntime(
            provider: RecordingRuntimeAIRecommendationProvider(),
            providerAvailability: nil,
            hasEagerProvider: false,
            diagnosticSink: RecordingRuntimeDiagnosticSink()
        )
        XCTAssertTrue(injectedProviderRuntime.shouldBuildRecommendationContext)

        let eagerRuntime = InputAIRecommendationRuntime(
            provider: nil,
            providerAvailability: nil,
            hasEagerProvider: true,
            diagnosticSink: RecordingRuntimeDiagnosticSink()
        )
        XCTAssertTrue(eagerRuntime.shouldBuildRecommendationContext)

        let missingRuntime = InputAIRecommendationRuntime(
            provider: nil,
            providerAvailability: nil,
            hasEagerProvider: false,
            diagnosticSink: RecordingRuntimeDiagnosticSink()
        )
        XCTAssertFalse(missingRuntime.shouldBuildRecommendationContext)
    }

    @MainActor
    func testUnavailableProviderGateSkipsSchedulingEvenWhenProviderIsInjected() async {
        let provider = RecordingRuntimeAIRecommendationProvider()
        let diagnosticSink = RecordingRuntimeDiagnosticSink()
        let runtime = InputAIRecommendationRuntime(
            provider: provider,
            providerAvailability: AIRecommendationProviderAvailabilityState(.unavailable),
            hasEagerProvider: false,
            diagnosticSink: diagnosticSink
        )

        let state = runtime.schedule(
            context: context(rawInput: "abc", hasRecommendationProvider: false),
            currentSnapshot: { snapshot(rawInput: "abc") },
            onStateChange: { _ in XCTFail("known-unavailable providers must not publish async state") }
        )

        XCTAssertEqual(state, .idle)
        let requests = await provider.requests
        XCTAssertEqual(requests.count, 0)
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .skippedNoProvider
                && $0.reason == "recommendation_provider_missing"
        })
    }

    private func pendingRequestID(_ state: AIRecommendationState) -> UUID? {
        guard case .pending(let requestID) = state else {
            return nil
        }
        return requestID
    }
}

private func context(
    rawInput: String,
    lockedPrefix: String? = nil,
    cloudContinuationEnabled: Bool = true,
    canRequestAIRecommendations: Bool = true,
    hasRecommendationProvider: Bool = true,
    appBundleID: String? = nil,
    locale: KnowTypeLocale = .mixed,
    compositionID: Int = 1,
    rawRevision: Int = 1,
    lexicalContext: LexicalContextSnapshot? = nil,
    feedbackContext: AIAcceptedFeedbackContextSnapshot? = nil
) -> InputAIRecommendationRuntimeContext {
    InputAIRecommendationRuntimeContext(
        rawInput: rawInput,
        hasResolvedSegments: false,
        isFullyResolved: false,
        lockedPrefix: lockedPrefix,
        cloudContinuationEnabled: cloudContinuationEnabled,
        canRequestAIRecommendations: canRequestAIRecommendations,
        hasRecommendationProvider: hasRecommendationProvider,
        appBundleID: appBundleID,
        locale: locale,
        compositionID: compositionID,
        rawRevision: rawRevision,
        lexicalContext: lexicalContext,
        feedbackContext: feedbackContext
    )
}

private func snapshot(
    rawInput: String,
    compositionID: Int = 1,
    rawRevision: Int = 1
) -> InputAIRecommendationRuntimeCompositionSnapshot {
    InputAIRecommendationRuntimeCompositionSnapshot(
        compositionID: compositionID,
        rawRevision: rawRevision,
        rawInput: rawInput
    )
}

private func readyState(_ displayText: String) -> AIRecommendationState {
    .ready(
        AIRecommendationCandidate(
            prefixText: "",
            continuationText: nil,
            displayText: displayText,
            confidence: 0.9,
            provider: "runtime-test",
            contextVersion: "test"
        )
    )
}

private func waitUntil(
    timeout: TimeInterval = 3,
    condition: @MainActor () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await MainActor.run(body: condition) {
            return true
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return await MainActor.run(body: condition)
}

private actor RecordingRuntimeAIRecommendationProvider: AIRecommendationProviding {
    private let response: AIRecommendationState
    private let delayNanoseconds: UInt64
    private var recordedRequests: [AIRecommendationRequest] = []

    init(
        response: AIRecommendationState = readyState("继续推进"),
        delayNanoseconds: UInt64 = 0
    ) {
        self.response = response
        self.delayNanoseconds = delayNanoseconds
    }

    func recommendation(for request: AIRecommendationRequest) async -> AIRecommendationState {
        recordedRequests.append(request)
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return response
    }

    var requests: [AIRecommendationRequest] {
        recordedRequests
    }
}

private final class RuntimeSnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var currentSnapshot: InputAIRecommendationRuntimeCompositionSnapshot

    init(_ snapshot: InputAIRecommendationRuntimeCompositionSnapshot) {
        self.currentSnapshot = snapshot
    }

    var snapshot: InputAIRecommendationRuntimeCompositionSnapshot {
        lock.lock()
        let snapshot = currentSnapshot
        lock.unlock()
        return snapshot
    }

    func update(_ snapshot: InputAIRecommendationRuntimeCompositionSnapshot) {
        lock.lock()
        currentSnapshot = snapshot
        lock.unlock()
    }
}

private final class RecordingRuntimeDiagnosticSink: AIRecommendationDiagnosticSink, @unchecked Sendable {
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
