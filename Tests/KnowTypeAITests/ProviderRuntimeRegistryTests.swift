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
        let runtime = makeLazyRecommendationRuntime(providerRegistry: registry)
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
        let runtime = makeLazyRecommendationRuntime(providerRegistry: registry)
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

    func testGenerationChangeDoesNotCancelInFlightRecommendationAndDropsOldResult() async throws {
        let providerA = SuspendedGenerationLLMProvider(name: "provider-a")
        let providerB = NamedLLMProvider(name: "provider-b", responseText: "B result")
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: providerA
        )
        let signal = TestProviderRevisionSignal()
        let registry = makeRegistry(source: source, signal: signal)
        let runtime = makeLazyRecommendationRuntime(providerRegistry: registry)
        let request = AIRecommendationRequest(rawInput: "nihao", compositionID: 1)

        let oldRequest = Task { await runtime.recommendation(for: request) }
        try await waitUntil { await providerA.requestCount == 1 }
        source.set(
            revision: 2,
            fingerprint: String(repeating: "b", count: 64),
            provider: providerB
        )
        signal.send(2)
        try await waitUntil { await registry.currentGeneration() == 2 }
        let cancellationCount = await providerA.cancellationCount
        XCTAssertEqual(cancellationCount, 0)
        await providerA.finish(responseText: "A stale result")
        let oldState = await oldRequest.value

        XCTAssertEqual(oldState, .stale)
        let current = await runtime.recommendation(for: request)
        XCTAssertEqual(current.readyDisplayText, "B result")
    }

    func testStaleOldRuntimeCannotClearNewRuntimeInstalledDuringActorReentry() async throws {
        let providerA = SuspendedGenerationLLMProvider(name: "provider-a")
        let providerB = NamedLLMProvider(name: "provider-b", responseText: "B result")
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: providerA
        )
        let runtime = makeLazyRecommendationRuntime(
            providerRegistry: makeRegistry(source: source)
        )
        let request = AIRecommendationRequest(rawInput: "nihao", compositionID: 1)

        let oldRequest = Task { await runtime.recommendation(for: request) }
        try await waitUntil { await providerA.requestCount == 1 }
        source.set(
            revision: 2,
            fingerprint: String(repeating: "b", count: 64),
            provider: providerB
        )

        let newState = await runtime.recommendation(for: request)
        XCTAssertEqual(newState.readyDisplayText, "B result")
        await providerA.finish(responseText: "A stale result")
        let oldState = await oldRequest.value
        XCTAssertEqual(oldState, .stale)

        let cachedState = await runtime.recommendation(for: request)
        XCTAssertEqual(cachedState.readyDisplayText, "B result")
        let providerBCount = await providerB.requestCount
        XCTAssertEqual(providerBCount, 1)
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
        let runtime = makeLazyRecommendationRuntime(providerRegistry: registry)
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
        let runtime = makeLazyRecommendationRuntime(providerRegistry: registry)
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
        let runtime = makeLazyRecommendationRuntime(
            providerRegistry: makeRegistry(source: source)
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

    func testRequestGateDoesNotCooldownLocalBudgetFailure() async throws {
        let now = Date()
        let gate = ProviderRequestGate(now: { now })
        let budget = ProviderRequestBudgetError(
            task: .continuation,
            component: "raw_input",
            byteCount: 4_097,
            limit: 4 * 1_024
        )

        do {
            _ = try await gate.execute(providerIdentity: "budget-provider", generation: 0) {
                throw budget
            } as LLMResponse
            XCTFail("expected local budget rejection")
        } catch let error as ProviderRequestBudgetError {
            XCTAssertEqual(error, budget)
        }
        await gate.recordFailure(
            providerIdentity: "budget-provider",
            generation: 0,
            failure: budget
        )
        let cooldown = await gate.cooldownDeadline(providerIdentity: "budget-provider", generation: 0)
        XCTAssertNil(cooldown)
        _ = try await gate.execute(providerIdentity: "budget-provider", generation: 0) {
            LLMResponse(candidates: [])
        } as LLMResponse
    }

    func testPersistentGateStateIsHashedBoundedAndClearsOnInvalidate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("gate.json")
        let now = Date()
        let identity = "provider-with-secret-and-model"
        let gate = ProviderRequestGate(now: { now }, persistenceURL: stateURL)

        do {
            _ = try await gate.execute(providerIdentity: identity, generation: 0) {
                throw ProviderRateLimitError(retryAfterSeconds: 30, bodyByteCount: 12)
            } as LLMResponse
            XCTFail("expected rate limit")
        } catch is ProviderRateLimitError {
            // Expected.
        }

        let persisted = try Data(contentsOf: stateURL)
        XCTAssertFalse(String(decoding: persisted, as: UTF8.self).contains(identity))
        let permissions = try FileManager.default.attributesOfItem(atPath: stateURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue ?? 0, 0o600)

        let reloaded = ProviderRequestGate(now: { now }, persistenceURL: stateURL)
        let reloadedDeadline = await reloaded.cooldownDeadline(providerIdentity: identity, generation: 0)
        XCTAssertNotNil(reloadedDeadline)
        await reloaded.invalidate(providerIdentity: identity, generation: 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))

        try Data("corrupt".utf8).write(to: stateURL)
        _ = try await ProviderRequestGate(now: { now }, persistenceURL: stateURL).execute(
            providerIdentity: identity,
            generation: 0
        ) {
            LLMResponse(candidates: [])
        } as LLMResponse
    }

    func testRequestGateSerializesSameIdentityButAllowsDifferentIdentity() async throws {
        let gate = ProviderRequestGate()
        let probe = RequestGateProbe()
        let first = Task {
            try await gate.execute(providerIdentity: "shared-provider", generation: 0) {
                await probe.markStarted()
                try await Task.sleep(nanoseconds: 200_000_000)
                return 1
            }
        }

        var started = false
        let deadline = Date().addingTimeInterval(2)
        while !started, Date() < deadline {
            started = await probe.hasStarted
            if !started { try await Task.sleep(nanoseconds: 10_000_000) }
        }
        XCTAssertTrue(started)

        do {
            _ = try await gate.execute(providerIdentity: "shared-provider", generation: 0) {
                2
            }
            XCTFail("same identity must be single-flight")
        } catch ProviderRequestGateError.busy {
            // Expected.
        }

        let different = try await gate.execute(providerIdentity: "different-provider", generation: 0) {
            3
        }
        XCTAssertEqual(different, 3)
        let firstValue = try await first.value
        XCTAssertEqual(firstValue, 1)
    }

    func testCooldownAvailabilityWaitIsReleasedImmediatelyByGenerationInvalidate() async throws {
        let now = Date()
        let gate = ProviderRequestGate(now: { now })
        do {
            _ = try await gate.execute(providerIdentity: "cooldown-provider", generation: 0) {
                throw ProviderRateLimitError(retryAfterSeconds: 15 * 60, bodyByteCount: 1)
            } as LLMResponse
            XCTFail("expected rate limit")
        } catch is ProviderRateLimitError {
            // Expected.
        }

        let probe = RequestGateProbe()
        let waiter = Task {
            await gate.waitForAvailability(providerIdentity: "cooldown-provider", generation: 0)
            await probe.markAvailabilityFinished()
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        let availabilityFinishedBeforeInvalidate = await probe.availabilityFinished
        XCTAssertFalse(availabilityFinishedBeforeInvalidate)

        await gate.invalidate(providerIdentity: "cooldown-provider", generation: 0)
        try await waitUntil { await probe.availabilityFinished }
        await waiter.value
    }

    func testNewGenerationWaiterWakesWhenOldOperationFinishesStale() async throws {
        let gate = ProviderRequestGate()
        let operation = SuspendedGateOperation()
        let oldRequest = Task {
            do {
                _ = try await gate.execute(providerIdentity: "generation-provider", generation: 0) {
                    await operation.run()
                    return 1
                }
                XCTFail("old operation must be stale after invalidation")
            } catch ProviderRequestGateError.staleGeneration {
                // Expected after the old provider operation actually finishes.
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }
        try await waitUntil { await operation.started }

        await gate.invalidate(providerIdentity: "generation-provider", generation: 0)
        let waiterProbe = RequestGateProbe()
        let waiter = Task {
            await gate.waitForAvailability(providerIdentity: "generation-provider", generation: 1)
            await waiterProbe.markAvailabilityFinished()
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        let finishedBeforeOldOperation = await waiterProbe.availabilityFinished
        XCTAssertFalse(finishedBeforeOldOperation)

        await operation.finish()
        await oldRequest.value
        try await waitUntil { await waiterProbe.availabilityFinished }
        await waiter.value
    }

    func testTimedOutGateAttemptRecordsOneFailureWhenCancelledOperationLaterFails() async throws {
        let now = Date()
        let identity = "timeout-owner"
        let gate = ProviderRequestGate(now: { now })
        let operation = SuspendedFailingGateOperation()
        let owner = Task {
            do {
                let _: Int = try await gate.executeWithHardTimeout(
                    providerIdentity: identity,
                    generation: 0,
                    timeoutNanoseconds: 20_000_000
                ) {
                    try await operation.run()
                }
                XCTFail("expected timeout")
            } catch is TimeoutError {
                // The gate records the owning attempt before exposing the timeout.
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }

        try await waitUntil { await operation.started }
        await owner.value
        let timeoutDeadline = await gate.cooldownDeadline(
            providerIdentity: identity,
            generation: 0
        )
        XCTAssertEqual(timeoutDeadline?.timeIntervalSince(now), 60, accuracy: 0.001)

        await operation.finish()
        var releasedWithCooldown = false
        let releaseDeadline = Date().addingTimeInterval(2)
        while !releasedWithCooldown, Date() < releaseDeadline {
            do {
                _ = try await gate.execute(providerIdentity: identity, generation: 0) { 1 }
                XCTFail("late provider error must preserve the timeout cooldown")
                break
            } catch ProviderRequestGateError.busy {
                try await Task.sleep(nanoseconds: 10_000_000)
            } catch ProviderRequestGateError.cooldown {
                releasedWithCooldown = true
            }
        }
        XCTAssertTrue(releasedWithCooldown)
        let finalDeadline = await gate.cooldownDeadline(
            providerIdentity: identity,
            generation: 0
        )
        XCTAssertEqual(finalDeadline?.timeIntervalSince(now), 60, accuracy: 0.001)
    }

    func testTimeoutAttemptOwnsFailureBeforeCancellationTriggeredLateErrorReleasesLease() async throws {
        let now = Date()
        let identity = "timeout-release-race"
        let gate = ProviderRequestGate(now: { now })
        let operation = CancellationTriggeredFailingGateOperation()

        do {
            let _: Int = try await gate.executeWithHardTimeout(
                providerIdentity: identity,
                generation: 0,
                timeoutNanoseconds: 20_000_000
            ) {
                try await operation.run()
            }
            XCTFail("expected timeout")
        } catch is TimeoutError {
            // Expected.
        }

        try await waitUntil { await operation.finished }
        let deadline = await gate.cooldownDeadline(
            providerIdentity: identity,
            generation: 0
        )
        XCTAssertEqual(deadline?.timeIntervalSince(now), 60, accuracy: 0.001)
        do {
            _ = try await gate.execute(providerIdentity: identity, generation: 0) { 1 }
            XCTFail("late 5xx must retain the owning timeout cooldown")
        } catch ProviderRequestGateError.cooldown {
            // Expected after the cancellation-triggered completion releases the lease.
        }
    }

    func testHardTimeoutAttemptCallerCancellationBeforeDeadlineDoesNotRecordFailure() async throws {
        let gate = ProviderRequestGate()
        let operation = SuspendedFailingGateOperation()
        let request = Task {
            try await gate.executeWithHardTimeout(
                providerIdentity: "cancel-before-timeout",
                generation: 0,
                timeoutNanoseconds: 1_000_000_000
            ) {
                try await operation.run()
            }
        }

        try await waitUntil { await operation.started }
        request.cancel()
        do {
            _ = try await request.value
            XCTFail("expected caller cancellation")
        } catch is CancellationError {
            // Expected before the hard-timeout task can claim the attempt.
        }
        await operation.finish()

        var released = false
        let releaseDeadline = Date().addingTimeInterval(2)
        while !released, Date() < releaseDeadline {
            do {
                let value = try await gate.execute(
                    providerIdentity: "cancel-before-timeout",
                    generation: 0
                ) { 2 }
                XCTAssertEqual(value, 2)
                released = true
            } catch ProviderRequestGateError.busy {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        XCTAssertTrue(released)
        let cooldown = await gate.cooldownDeadline(
            providerIdentity: "cancel-before-timeout",
            generation: 0
        )
        XCTAssertNil(cooldown)
    }

    func testCallerCancellationDoesNotCountCancellationResistantLateFailure() async throws {
        let gate = ProviderRequestGate()
        let operation = SuspendedFailingGateOperation()
        let request = Task {
            try await gate.execute(providerIdentity: "caller-cancel", generation: 0) {
                try await operation.run()
            }
        }

        try await waitUntil { await operation.started }
        request.cancel()
        await operation.finish()
        do {
            _ = try await request.value
            XCTFail("expected late provider failure")
        } catch {
            guard case ProviderError.httpStatus(let status, _) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(status, 503)
        }

        let cooldown = await gate.cooldownDeadline(
            providerIdentity: "caller-cancel",
            generation: 0
        )
        XCTAssertNil(cooldown)
        let value = try await gate.execute(providerIdentity: "caller-cancel", generation: 0) { 2 }
        XCTAssertEqual(value, 2)
    }

    func testFailureCountClampsAtSixteenAndPersistsMaximumCooldown() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("gate.json")
        let now = Date()
        let identity = "clamped-provider"
        let gate = ProviderRequestGate(now: { now }, persistenceURL: stateURL)

        for _ in 0..<17 {
            await gate.recordFailure(
                providerIdentity: identity,
                generation: 0,
                failure: ProviderError.httpStatus(503, "unavailable")
            )
        }

        let data = try Data(contentsOf: stateURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        let failureCount = try XCTUnwrap(entries.first?["failureCount"] as? NSNumber)
        XCTAssertEqual(failureCount.intValue, 16)

        let reloaded = ProviderRequestGate(now: { now }, persistenceURL: stateURL)
        let deadline = await reloaded.cooldownDeadline(
            providerIdentity: identity,
            generation: 0
        )
        XCTAssertEqual(deadline?.timeIntervalSince(now), 15 * 60, accuracy: 0.001)
    }

    func testPersistentGateWriterTrimsDeterministicallyAndExpiresAcrossRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("gate.json")
        let now = Date()
        let identities = (0..<300).map { "provider-\($0)" }
        let gate = ProviderRequestGate(now: { now }, persistenceURL: stateURL)

        for identity in identities {
            await gate.recordFailure(
                providerIdentity: identity,
                generation: 0,
                failure: ProviderError.httpStatus(503, "unavailable")
            )
        }

        let data = try Data(contentsOf: stateURL)
        XCTAssertLessThanOrEqual(data.count, 64 * 1_024)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        XCTAssertLessThanOrEqual(entries.count, 256)

        let ordered = identities.sorted {
            ProviderRequestGate.identityHash($0) < ProviderRequestGate.identityHash($1)
        }
        let retainedIdentity = try XCTUnwrap(ordered.first)
        let trimmedIdentity = try XCTUnwrap(ordered.last)
        let reloaded = ProviderRequestGate(now: { now }, persistenceURL: stateURL)
        let includedDeadline = await reloaded.cooldownDeadline(
            providerIdentity: retainedIdentity,
            generation: 0
        )
        let excludedDeadline = await reloaded.cooldownDeadline(
            providerIdentity: trimmedIdentity,
            generation: 0
        )
        XCTAssertNotNil(includedDeadline)
        XCTAssertNil(excludedDeadline)

        let expired = ProviderRequestGate(
            now: { now.addingTimeInterval(61) },
            persistenceURL: stateURL
        )
        _ = await expired.cooldownDeadline(
            providerIdentity: retainedIdentity,
            generation: 0
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
    }

    private func makeLazyRecommendationRuntime(
        providerRegistry: ProviderRuntimeRegistry
    ) -> LazyDefaultAIRecommendationRuntime {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return LazyDefaultAIRecommendationRuntime(
            providerRegistry: providerRegistry,
            environmentStore: EnvironmentDocumentStore(
                fileURL: directory.appendingPathComponent("ENV.md")
            ),
            correctionStore: CorrectionInstructionStore(
                fileURL: directory.appendingPathComponent("CORRECTION.md")
            ),
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            debounceMilliseconds: 0
        )
    }
}

private actor RequestGateProbe {
    private var started = false
    private var didFinishAvailabilityWait = false

    func markStarted() {
        started = true
    }

    var hasStarted: Bool {
        started
    }

    func markAvailabilityFinished() {
        didFinishAvailabilityWait = true
    }

    var availabilityFinished: Bool {
        didFinishAvailabilityWait
    }
}

private actor SuspendedGateOperation {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false

    func run() async {
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

private actor SuspendedFailingGateOperation {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false

    func run() async throws -> Int {
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        throw ProviderError.httpStatus(503, "late failure")
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

private actor CancellationTriggeredFailingGateOperation {
    private(set) var finished = false

    func run() async throws -> Int {
        while !Task.isCancelled {
            await Task.yield()
        }
        finished = true
        throw ProviderError.httpStatus(503, "late cancellation failure")
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
    diagnosticSink: any ProviderRuntimeDiagnosticSink = NoopProviderRuntimeDiagnosticSink(),
    requestGate: ProviderRequestGate = ProviderRequestGate()
) -> ProviderRuntimeRegistry {
    ProviderRuntimeRegistry(
        revisionLoader: { source.loadRevision() },
        runtimeLoader: { source.loadRuntime() },
        revisionUpdates: { signal.stream },
        capabilityReset: capabilityReset,
        diagnosticSink: diagnosticSink,
        requestGate: requestGate
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
