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
            dispatchDebounceMilliseconds: 0,
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
            dispatchDebounceMilliseconds: 0,
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
            dispatchDebounceMilliseconds: 0,
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
            dispatchDebounceMilliseconds: 0,
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
    func testSchedulePublishesPendingAfterDispatchAndBuildsRequestWithoutCandidateHints() async throws {
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
            dispatchDebounceMilliseconds: 0,
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
    func testDefaultDebounceShowsPendingPlaceholderUntilProviderDispatch() async {
        XCTAssertEqual(InputAIRecommendationRuntime.Defaults.dispatchDebounceMilliseconds, 450)
        let provider = RecordingRuntimeAIRecommendationProvider(
            response: readyState("稳定后推荐")
        )
        let diagnosticSink = RecordingRuntimeDiagnosticSink()
        let runtime = InputAIRecommendationRuntime(
            provider: provider,
            providerAvailability: nil,
            hasEagerProvider: true,
            dispatchDebounceMilliseconds: 80,
            diagnosticSink: diagnosticSink
        )
        var states: [AIRecommendationState] = []

        let initialState = runtime.schedule(
            context: context(rawInput: "abc", compositionID: 2, rawRevision: 1),
            currentSnapshot: { snapshot(rawInput: "abc", compositionID: 2, rawRevision: 1) },
            onStateChange: { states.append($0) }
        )

        XCTAssertNotNil(pendingRequestID(initialState))
        try? await Task.sleep(nanoseconds: 20_000_000)
        let earlyRequests = await provider.requests
        XCTAssertTrue(earlyRequests.isEmpty)
        XCTAssertTrue(states.isEmpty)

        let didDispatch = await waitUntilAsync {
            await provider.requests.count == 1
        }
        XCTAssertTrue(didDispatch)
        XCTAssertFalse(states.contains {
            if case .pending = $0 {
                return true
            }
            return false
        })
        XCTAssertTrue(diagnosticSink.events.contains { $0.stage == .pendingPlaceholder })
        XCTAssertTrue(diagnosticSink.events.contains { $0.stage == .dispatchDeferred })
        XCTAssertTrue(diagnosticSink.events.contains { $0.stage == .transportStarted })
    }

    @MainActor
    func testNewInputDuringDebounceCancelsDeferredDispatchWithoutCallingProvider() async {
        let provider = RecordingRuntimeAIRecommendationProvider(
            response: readyState("新结果")
        )
        let diagnosticSink = RecordingRuntimeDiagnosticSink()
        let runtime = InputAIRecommendationRuntime(
            provider: provider,
            providerAvailability: nil,
            hasEagerProvider: true,
            dispatchDebounceMilliseconds: 200,
            diagnosticSink: diagnosticSink
        )

        let firstState = runtime.schedule(
            context: context(rawInput: "abc", compositionID: 1, rawRevision: 1),
            currentSnapshot: { snapshot(rawInput: "abc", compositionID: 1, rawRevision: 1) },
            onStateChange: { _ in XCTFail("debounced request must not publish state") }
        )
        XCTAssertNotNil(pendingRequestID(firstState))
        let firstRequestID = diagnosticSink.events.last { $0.stage == .scheduled }?.requestID

        let secondState = runtime.schedule(
            context: context(rawInput: "abcd", compositionID: 1, rawRevision: 2),
            currentSnapshot: { snapshot(rawInput: "abcd", compositionID: 1, rawRevision: 2) },
            onStateChange: { _ in }
        )
        XCTAssertNotNil(pendingRequestID(secondState))

        let didCallProvider = await waitUntilAsync {
            await provider.requests.count == 1
        }
        XCTAssertTrue(didCallProvider)
        let requests = await provider.requests
        XCTAssertEqual(requests.map(\.rawInput), ["abcd"])
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .dispatchCancelledByNewInput
                && $0.requestID == firstRequestID
        })
        XCTAssertEqual(
            diagnosticSink.events.filter { $0.stage == .pendingPlaceholder }.count,
            2
        )
    }

    @MainActor
    func testProviderDispatchAfterNewInputCancelsOldTransportWithoutApplying() async {
        let provider = RecordingRuntimeAIRecommendationProvider(
            response: readyState("旧结果"),
            delayNanoseconds: 300_000_000
        )
        let diagnosticSink = RecordingRuntimeDiagnosticSink()
        let runtime = InputAIRecommendationRuntime(
            provider: provider,
            providerAvailability: nil,
            hasEagerProvider: true,
            dispatchDebounceMilliseconds: 0,
            diagnosticSink: diagnosticSink
        )
        let currentSnapshot = RuntimeSnapshotBox(
            snapshot(rawInput: "abc", compositionID: 1, rawRevision: 1)
        )

        let firstState = runtime.schedule(
            context: context(rawInput: "abc", compositionID: 1, rawRevision: 1),
            currentSnapshot: { currentSnapshot.snapshot },
            onStateChange: { _ in XCTFail("cancelled request must not publish state") }
        )
        let firstRequestID = pendingRequestID(firstState)
        let firstTransportStarted = await waitUntilAsync {
            await provider.requests.count == 1
        }
        XCTAssertTrue(firstTransportStarted)
        currentSnapshot.update(snapshot(rawInput: "abcd", compositionID: 1, rawRevision: 2))

        let secondState = runtime.schedule(
            context: context(rawInput: "abcd", compositionID: 1, rawRevision: 2),
            currentSnapshot: { currentSnapshot.snapshot },
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
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .transportLeftStale
                && $0.requestID == firstRequestID
                && $0.reason == "new_schedule"
        })
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .transportCancellationRequested
                && $0.requestID == firstRequestID
                && $0.reason == "new_schedule"
        })
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .transportCancelledByNewInput
                && $0.requestID == firstRequestID
                && $0.reason == "new_schedule"
        })
        let cancelled = await waitUntil {
            diagnosticSink.events.contains {
                $0.stage == .cancelled
                    && $0.requestID == firstRequestID
                    && $0.reason == "task_cancelled_before_apply"
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
            dispatchDebounceMilliseconds: 0,
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
    func testResetCancelsDeferredDispatchAndReturnsIdle() async {
        let provider = RecordingRuntimeAIRecommendationProvider(
            response: .unavailable(reason: "timeout"),
            delayNanoseconds: 5_000_000_000
        )
        let diagnosticSink = RecordingRuntimeDiagnosticSink()
        let runtime = InputAIRecommendationRuntime(
            provider: provider,
            providerAvailability: nil,
            hasEagerProvider: true,
            dispatchDebounceMilliseconds: 200,
            diagnosticSink: diagnosticSink
        )
        let state = runtime.schedule(
            context: context(rawInput: "abc", compositionID: 9, rawRevision: 1),
            currentSnapshot: { snapshot(rawInput: "abc", compositionID: 9, rawRevision: 1) },
            onStateChange: { _ in XCTFail("reset request must not publish state") }
        )
        XCTAssertNotNil(pendingRequestID(state))
        let requestID = diagnosticSink.events.last { $0.stage == .scheduled }?.requestID

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
                $0.stage == .dispatchCancelledByNewInput
                    && $0.requestID == requestID
                    && (
                        $0.reason == "debounce_cancelled_by_new_input"
                        || $0.reason == "request_inactive_before_transport"
                    )
            }
        }
        XCTAssertTrue(cancelled, "\(diagnosticSink.events)")
        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
    }

    @MainActor
    func testHasKnownProviderUsesEagerProviderOrAvailabilitySnapshot() {
        let availability = AIRecommendationProviderAvailabilityState(.unknown)
        let lazyRuntime = InputAIRecommendationRuntime(
            provider: RecordingRuntimeAIRecommendationProvider(),
            providerAvailability: availability,
            hasEagerProvider: false,
            dispatchDebounceMilliseconds: 0,
            diagnosticSink: RecordingRuntimeDiagnosticSink()
        )
        XCTAssertFalse(lazyRuntime.hasKnownProvider)

        availability.update(.available)
        XCTAssertTrue(lazyRuntime.hasKnownProvider)

        let eagerRuntime = InputAIRecommendationRuntime(
            provider: nil,
            providerAvailability: nil,
            hasEagerProvider: true,
            dispatchDebounceMilliseconds: 0,
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
            dispatchDebounceMilliseconds: 0,
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
            dispatchDebounceMilliseconds: 0,
            diagnosticSink: RecordingRuntimeDiagnosticSink()
        )
        XCTAssertTrue(injectedProviderRuntime.shouldBuildRecommendationContext)

        let eagerRuntime = InputAIRecommendationRuntime(
            provider: nil,
            providerAvailability: nil,
            hasEagerProvider: true,
            dispatchDebounceMilliseconds: 0,
            diagnosticSink: RecordingRuntimeDiagnosticSink()
        )
        XCTAssertFalse(eagerRuntime.shouldBuildRecommendationContext)
        XCTAssertFalse(eagerRuntime.shouldScheduleRecommendationRequest)

        let eagerRuntimeWithRecommendationProvider = InputAIRecommendationRuntime(
            provider: RecordingRuntimeAIRecommendationProvider(),
            providerAvailability: nil,
            hasEagerProvider: true,
            dispatchDebounceMilliseconds: 0,
            diagnosticSink: RecordingRuntimeDiagnosticSink()
        )
        XCTAssertTrue(eagerRuntimeWithRecommendationProvider.shouldBuildRecommendationContext)
        XCTAssertTrue(eagerRuntimeWithRecommendationProvider.shouldScheduleRecommendationRequest)

        let missingRuntime = InputAIRecommendationRuntime(
            provider: nil,
            providerAvailability: nil,
            hasEagerProvider: false,
            dispatchDebounceMilliseconds: 0,
            diagnosticSink: RecordingRuntimeDiagnosticSink()
        )
        XCTAssertFalse(missingRuntime.shouldBuildRecommendationContext)
    }

    @MainActor
    func testUnavailableProviderProbeRetriesWithoutPublishingUnavailableState() async {
        let provider = RecordingRuntimeAIRecommendationProvider(response: .unavailable(reason: "AI 未配置"))
        let diagnosticSink = RecordingRuntimeDiagnosticSink()
        let runtime = InputAIRecommendationRuntime(
            provider: provider,
            providerAvailability: AIRecommendationProviderAvailabilityState(.unavailable),
            hasEagerProvider: false,
            dispatchDebounceMilliseconds: 0,
            diagnosticSink: diagnosticSink
        )

        var publishedStates: [AIRecommendationState] = []
        let state = runtime.schedule(
            context: context(
                rawInput: "abc",
                hasRecommendationProvider: true,
                isProviderAvailabilityProbe: true
            ),
            currentSnapshot: { snapshot(rawInput: "abc") },
            onStateChange: { publishedStates.append($0) }
        )

        XCTAssertEqual(state, .idle)
        let didCallProvider = await waitUntilAsync {
            await provider.requests.count == 1
        }
        XCTAssertTrue(didCallProvider)
        let requests = await provider.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(publishedStates.isEmpty)
        XCTAssertFalse(diagnosticSink.events.contains { $0.stage == .pendingPlaceholder })
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .stateApplied
                && ($0.reason?.hasPrefix("availability_probe_suppressed_") ?? false)
        })
    }

    @MainActor
    func testUnavailableProviderProbeCanPublishReadyStateAfterProviderRecovers() async {
        let provider = RecordingRuntimeAIRecommendationProvider(response: readyState("恢复续写"))
        let diagnosticSink = RecordingRuntimeDiagnosticSink()
        let runtime = InputAIRecommendationRuntime(
            provider: provider,
            providerAvailability: AIRecommendationProviderAvailabilityState(.unavailable),
            hasEagerProvider: false,
            dispatchDebounceMilliseconds: 0,
            diagnosticSink: diagnosticSink
        )

        var publishedStates: [AIRecommendationState] = []
        let state = runtime.schedule(
            context: context(
                rawInput: "abc",
                hasRecommendationProvider: true,
                isProviderAvailabilityProbe: true
            ),
            currentSnapshot: { snapshot(rawInput: "abc") },
            onStateChange: { publishedStates.append($0) }
        )

        XCTAssertEqual(state, .idle)
        let didPublishReady = await waitUntil {
            publishedStates.contains { state in
                if case .ready = state {
                    return true
                }
                return false
            }
        }
        XCTAssertTrue(didPublishReady)
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .stateApplied
                && $0.reason == "ready"
        })
    }

    @MainActor
    func testProviderGenerationStaleResultNeverPublishesUIState() async {
        let provider = RecordingRuntimeAIRecommendationProvider(response: .stale)
        let diagnosticSink = RecordingRuntimeDiagnosticSink()
        let runtime = InputAIRecommendationRuntime(
            provider: provider,
            providerAvailability: nil,
            hasEagerProvider: true,
            dispatchDebounceMilliseconds: 0,
            diagnosticSink: diagnosticSink
        )
        var publishedStates: [AIRecommendationState] = []

        let initial = runtime.schedule(
            context: context(rawInput: "abc"),
            currentSnapshot: { snapshot(rawInput: "abc") },
            onStateChange: { publishedStates.append($0) }
        )

        XCTAssertNotNil(pendingRequestID(initial))
        let staleDropped = await waitUntil {
            diagnosticSink.events.contains {
                $0.stage == .staleResultDropped
                    && $0.reason == "provider_generation_changed"
            }
        }
        XCTAssertTrue(staleDropped)
        XCTAssertTrue(publishedStates.isEmpty)
        XCTAssertFalse(diagnosticSink.events.contains { $0.stage == .stateApplied })
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
    isProviderAvailabilityProbe: Bool = false,
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
        isProviderAvailabilityProbe: isProviderAvailabilityProbe,
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

@MainActor
private func waitUntilAsync(
    timeout: TimeInterval = 3,
    condition: @MainActor () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return await condition()
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
