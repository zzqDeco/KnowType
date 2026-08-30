import Darwin
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

    func testConcurrentRefreshCoalescesLinearizedGenerationInvalidation() async throws {
        let fingerprintA = String(repeating: "a", count: 64)
        let fingerprintB = String(repeating: "b", count: 64)
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: fingerprintA,
            provider: NamedLLMProvider(name: "provider-a", responseText: "A")
        )
        let gateProbe = ProviderRequestGateTestProbe()
        let admissionPause = GateAttemptAdmissionPause()
        let completionPause = GateAttemptCompletionPause()
        let staleOperationProbe = RequestGateProbe()
        let resetProbe = RequestGateProbe()
        let gate = ProviderRequestGate(
            testProbe: gateProbe,
            afterAttemptAdmission: {
                await admissionPause.suspendIfNeeded()
            }
        )
        let registry = makeRegistry(
            source: source,
            capabilityReset: { await resetProbe.markStarted() },
            requestGate: gate
        )
        let initialLease = await registry.leaseForEligibleDispatch()
        let initialResetCount = await resetProbe.startCount
        XCTAssertEqual(initialLease.generation, 1)
        XCTAssertEqual(initialResetCount, 1)

        let staleAttempt = Task<Int, Error> {
            try await gate.executeWithHardTimeout(
                providerIdentity: fingerprintA,
                generation: initialLease.generation,
                timeoutNanoseconds: 60_000_000_000,
                onAttemptCompletion: {
                    await completionPause.suspendAndRecord()
                }
            ) {
                await staleOperationProbe.markStarted()
                return 1
            }
        }
        do {
            try await waitUntil { await admissionPause.hasEntered }
        } catch {
            staleAttempt.cancel()
            await admissionPause.release()
            await completionPause.release()
            _ = try? await staleAttempt.value
            throw error
        }

        source.set(
            revision: 2,
            fingerprint: fingerprintB,
            provider: NamedLLMProvider(name: "provider-b", responseText: "B")
        )
        let firstRefresh = Task { await registry.leaseForEligibleDispatch() }
        do {
            try await waitUntil { await completionPause.hasEntered }
        } catch {
            staleAttempt.cancel()
            firstRefresh.cancel()
            await admissionPause.release()
            await completionPause.release()
            _ = try? await staleAttempt.value
            _ = await firstRefresh.value
            throw error
        }

        let transitionWaitProbe = RegistryGenerationTransitionWaitProbe()
        await registry.setGenerationTransitionWaitObserverForTesting {
            transitionWaitProbe.recordWait()
        }
        let secondRefresh = Task { await registry.leaseForEligibleDispatch() }
        do {
            try await waitUntil { transitionWaitProbe.waitCount == 1 }
        } catch {
            staleAttempt.cancel()
            firstRefresh.cancel()
            secondRefresh.cancel()
            await admissionPause.release()
            await completionPause.release()
            _ = try? await staleAttempt.value
            _ = await firstRefresh.value
            _ = await secondRefresh.value
            throw error
        }

        let generationBeforeLinearizedOwnerCompletes = await registry.currentGeneration()
        XCTAssertEqual(generationBeforeLinearizedOwnerCompletes, 1)
        await completionPause.release()

        let firstLease = await firstRefresh.value
        let secondLease = await secondRefresh.value
        let currentGeneration = await registry.currentGeneration()
        let resetCount = await resetProbe.startCount
        let completionCount = await completionPause.completionCount
        XCTAssertEqual(currentGeneration, 2)
        XCTAssertEqual(firstLease.generation, 2)
        XCTAssertEqual(secondLease.generation, 2)
        XCTAssertEqual(firstLease.revision, 2)
        XCTAssertEqual(secondLease.revision, 2)
        XCTAssertEqual(resetCount, 2)
        XCTAssertEqual(completionCount, 1)
        let secondLeaseIsCurrent = try await registry.commitIfCurrent(
            using: secondLease
        ) { true }
        XCTAssertTrue(secondLeaseIsCurrent)

        await admissionPause.release()
        do {
            _ = try await staleAttempt.value
            XCTFail("invalidated pre-transport work must not start")
        } catch is CancellationError {
            // The invalidated attempt observes its closed phase after the pause.
        } catch ProviderRequestGateError.staleGeneration {
            // A stale fence is also valid if generation observation wins first.
        } catch {
            XCTFail("unexpected invalidated-attempt error: \(error)")
        }
        let staleProviderStarts = await staleOperationProbe.startCount
        let finalCompletionCount = await completionPause.completionCount
        XCTAssertEqual(staleProviderStarts, 0)
        XCTAssertEqual(finalCompletionCount, 1)
        XCTAssertEqual(gateProbe.rejectedTransportStartCount, 1)
    }

    func testSameRevisionSignalBeforeAndAfterTransitionClearsOnlyOnce() async throws {
        let providerB = NamedLLMProvider(name: "provider-b", responseText: "B")
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: NamedLLMProvider(name: "provider-a", responseText: "A")
        )
        let signal = TestProviderRevisionSignal()
        let resetProbe = RegistryCapabilityResetPause()
        let registry = makeRegistry(
            source: source,
            signal: signal,
            capabilityReset: { await resetProbe.reset() }
        )

        _ = await registry.leaseForEligibleDispatch()
        let revisionProbe = RegistryRevisionObservationProbe()
        await registry.setRevisionObservationObserverForTesting {
            revisionProbe.record($0)
        }
        await resetProbe.pauseNextReset()
        source.set(
            revision: 2,
            fingerprint: String(repeating: "b", count: 64),
            provider: providerB
        )
        signal.send(2)
        try await waitUntil { await resetProbe.hasEntered }

        signal.send(2)
        await resetProbe.release()
        try await waitUntil { revisionProbe.observedCount == 2 }
        try await waitUntil { await registry.currentGeneration() == 2 }

        let lease = await registry.leaseForEligibleDispatch()
        XCTAssertEqual(lease.generation, 2)
        XCTAssertEqual(lease.revision, 2)
        XCTAssertEqual(lease.provider?.providerName, "provider-b")
        let resetCountAfterFirstLease = await resetProbe.resetCount
        XCTAssertEqual(resetCountAfterFirstLease, 2)

        signal.send(2)
        try await waitUntil { revisionProbe.observedCount == 3 }
        _ = await registry.leaseForEligibleDispatch()
        let resetCountAfterDuplicateSignal = await resetProbe.resetCount
        XCTAssertEqual(resetCountAfterDuplicateSignal, 2)
    }

    func testSameRevisionFingerprintReplacementRecoversFromProvisionalLease() async {
        let fingerprintF1 = String(repeating: "b", count: 64)
        let fingerprintF2 = String(repeating: "c", count: 64)
        let providerB = NamedLLMProvider(name: "provider-b", responseText: "B")
        let source = ProviderRuntimeTestSource(
            revision: 0,
            fingerprint: fingerprintF2,
            provider: providerB
        )
        source.setRuntimeOverride(
            revision: 2,
            fingerprint: fingerprintF2,
            provider: providerB
        )
        source.setRuntimeSequence([
            ProviderRuntimeLoadResult(
                revision: 2,
                fingerprint: fingerprintF1,
                provider: nil
            ),
            ProviderRuntimeLoadResult(
                revision: 2,
                fingerprint: fingerprintF2,
                provider: providerB
            )
        ])
        let resetProbe = RegistryCapabilityResetPause()
        let registry = makeRegistry(
            source: source,
            capabilityReset: { await resetProbe.reset() }
        )

        let lease = await registry.leaseForEligibleDispatch()

        XCTAssertEqual(lease.revision, 2)
        XCTAssertEqual(lease.generation, 2)
        XCTAssertEqual(lease.fingerprint, fingerprintF2)
        XCTAssertEqual(lease.provider?.providerName, "provider-b")
        let resetCount = await resetProbe.resetCount
        XCTAssertEqual(resetCount, 2)
        XCTAssertEqual(source.runtimeLoadCount, 3)
    }

    func testSameRevisionFingerprintReplacementFencesOldLease() async throws {
        let fingerprintF1 = String(repeating: "b", count: 64)
        let fingerprintF2 = String(repeating: "c", count: 64)
        let providerB = NamedLLMProvider(name: "provider-b", responseText: "B")
        let source = ProviderRuntimeTestSource(
            revision: 0,
            fingerprint: fingerprintF1,
            provider: nil
        )
        source.setRuntimeSequence([
            ProviderRuntimeLoadResult(
                revision: 2,
                fingerprint: fingerprintF1,
                provider: nil
            ),
            ProviderRuntimeLoadResult(
                revision: 2,
                fingerprint: fingerprintF1,
                provider: nil
            )
        ])
        let registry = makeRegistry(source: source)
        let oldLease = await registry.leaseForEligibleDispatch()

        source.setRuntimeOverride(
            revision: 2,
            fingerprint: fingerprintF2,
            provider: providerB
        )
        let currentLease = await registry.leaseForEligibleDispatch()

        XCTAssertEqual(oldLease.revision, 2)
        XCTAssertEqual(oldLease.generation, 1)
        XCTAssertEqual(oldLease.fingerprint, fingerprintF1)
        XCTAssertNil(oldLease.provider)
        XCTAssertEqual(currentLease.generation, 2)
        XCTAssertEqual(currentLease.fingerprint, fingerprintF2)
        XCTAssertEqual(currentLease.provider?.providerName, "provider-b")

        do {
            try await registry.commitIfCurrent(using: oldLease) {
                XCTFail("old same-revision fingerprint lease must not commit")
            }
            XCTFail("expected stale generation")
        } catch ProviderRuntimeRegistryError.staleGeneration {
            // Expected.
        }
    }

    func testSameRevisionFingerprintOscillationIsBoundedAndFailsClosed() async throws {
        let fingerprintF1 = String(repeating: "b", count: 64)
        let fingerprintF2 = String(repeating: "c", count: 64)
        let providerB = NamedLLMProvider(name: "provider-b", responseText: "B")
        let source = ProviderRuntimeTestSource(
            revision: 0,
            fingerprint: fingerprintF1,
            provider: nil
        )
        source.setRuntimeOverride(
            revision: 2,
            fingerprint: fingerprintF2,
            provider: providerB
        )
        source.setRuntimeSequence([
            ProviderRuntimeLoadResult(
                revision: 2,
                fingerprint: fingerprintF1,
                provider: nil
            ),
            ProviderRuntimeLoadResult(
                revision: 2,
                fingerprint: fingerprintF2,
                provider: providerB
            ),
            ProviderRuntimeLoadResult(
                revision: 2,
                fingerprint: fingerprintF1,
                provider: nil
            )
        ])
        let resetProbe = RegistryCapabilityResetPause()
        let registry = makeRegistry(
            source: source,
            capabilityReset: { await resetProbe.reset() }
        )

        let provisionalLease = await registry.leaseForEligibleDispatch()

        XCTAssertEqual(provisionalLease.revision, 2)
        XCTAssertEqual(provisionalLease.generation, 2)
        XCTAssertEqual(provisionalLease.fingerprint, fingerprintF2)
        XCTAssertNil(provisionalLease.provider)
        let resetCountAfterOscillation = await resetProbe.resetCount
        XCTAssertEqual(resetCountAfterOscillation, 2)
        XCTAssertEqual(source.runtimeLoadCount, 3)

        let recoveredLease = await registry.leaseForEligibleDispatch()

        XCTAssertEqual(recoveredLease.generation, 2)
        XCTAssertEqual(recoveredLease.fingerprint, fingerprintF2)
        XCTAssertEqual(recoveredLease.provider?.providerName, "provider-b")
        let resetCountAfterRecovery = await resetProbe.resetCount
        XCTAssertEqual(resetCountAfterRecovery, 2)
        XCTAssertEqual(source.runtimeLoadCount, 4)

        do {
            try await registry.commitIfCurrent(using: provisionalLease) {
                XCTFail("provider-less oscillation lease must become stale on recovery")
            }
            XCTFail("expected stale generation")
        } catch ProviderRuntimeRegistryError.staleGeneration {
            // Expected.
        }
    }

    func testHigherRevisionDuringDiskRefreshCannotPublishOldLease() async throws {
        let providerB = NamedLLMProvider(name: "provider-b", responseText: "B")
        let providerC = NamedLLMProvider(name: "provider-c", responseText: "C")
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: NamedLLMProvider(name: "provider-a", responseText: "A")
        )
        let signal = TestProviderRevisionSignal()
        let resetProbe = RegistryCapabilityResetPause()
        let registry = makeRegistry(
            source: source,
            signal: signal,
            capabilityReset: { await resetProbe.reset() }
        )
        let oldLease = await registry.leaseForEligibleDispatch()
        let revisionProbe = RegistryRevisionObservationProbe()
        await registry.setRevisionObservationObserverForTesting {
            revisionProbe.record($0)
        }

        source.set(
            revision: 2,
            fingerprint: String(repeating: "b", count: 64),
            provider: providerB
        )
        source.setRuntimeOverride(
            revision: 2,
            fingerprint: String(repeating: "b", count: 64),
            provider: providerB
        )
        await resetProbe.pauseNextReset()
        let refresh = Task { await registry.leaseForEligibleDispatch() }
        try await waitUntil { await resetProbe.hasEntered }

        source.set(
            revision: 3,
            fingerprint: String(repeating: "c", count: 64),
            provider: providerC
        )
        signal.send(3)
        try await waitUntil { revisionProbe.observedCount == 1 }
        await resetProbe.release()

        let unavailable = await refresh.value
        XCTAssertEqual(unavailable.generation, 3)
        XCTAssertEqual(unavailable.revision, 3)
        XCTAssertNil(unavailable.provider)
        let resetCountAfterStaleLoad = await resetProbe.resetCount
        XCTAssertEqual(resetCountAfterStaleLoad, 3)

        source.clearRuntimeOverride()
        let current = await registry.leaseForEligibleDispatch()
        XCTAssertEqual(current.generation, 3)
        XCTAssertEqual(current.revision, 3)
        XCTAssertEqual(current.provider?.providerName, "provider-c")
        let resetCountAfterRecovery = await resetProbe.resetCount
        XCTAssertEqual(resetCountAfterRecovery, 3)

        do {
            try await registry.commitIfCurrent(using: oldLease) {
                XCTFail("old lease must not commit after a higher revision transition")
            }
            XCTFail("expected stale generation")
        } catch ProviderRuntimeRegistryError.staleGeneration {
            // Expected.
        }
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

    func testSharedRequestGateClampsRetryAfterAndFencesGeneration() async throws {
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
        let unwrappedDeadline = try XCTUnwrap(deadline)
        XCTAssertEqual(unwrappedDeadline.timeIntervalSince(now), 15, accuracy: 0.001)
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

    func testRequestGateHonorsEightyFiveHourRateLimitHintAcrossRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("gate.json")
        let clock = ProviderGateClock()
        let identity = "long-rate-limit"
        let gate = ProviderRequestGate(now: clock.now, persistenceURL: stateURL)

        await gate.recordFailure(
            providerIdentity: identity,
            generation: 0,
            failure: ProviderRateLimitError(
                retryAfterSeconds: 85 * 60 * 60,
                bodyByteCount: 128
            )
        )

        let loadedDeadline = await gate.cooldownDeadline(
            providerIdentity: identity,
            generation: 0
        )
        let deadline = try XCTUnwrap(loadedDeadline)
        XCTAssertEqual(deadline.timeIntervalSince(clock.now()), 85 * 60 * 60, accuracy: 0.001)

        let restarted = ProviderRequestGate(now: clock.now, persistenceURL: stateURL)
        let loadedRestartedDeadline = await restarted.cooldownDeadline(
            providerIdentity: identity,
            generation: 0
        )
        let restartedDeadline = try XCTUnwrap(loadedRestartedDeadline)
        XCTAssertEqual(
            restartedDeadline.timeIntervalSince(clock.now()),
            85 * 60 * 60,
            accuracy: 0.001
        )
    }

    func testRequestGateUsesDedicatedBoundedRateLimitBackoffWithoutHint() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("gate.json")
        let clock = ProviderGateClock()
        let identity = "rate-limit-without-hint"
        var gate = ProviderRequestGate(now: clock.now, persistenceURL: stateURL)
        let expected: [TimeInterval] = [
            15 * 60,
            30 * 60,
            60 * 60,
            2 * 60 * 60,
            4 * 60 * 60,
            8 * 60 * 60,
            16 * 60 * 60,
            24 * 60 * 60,
            24 * 60 * 60
        ]

        for delay in expected {
            await gate.recordFailure(
                providerIdentity: identity,
                generation: 0,
                failure: ProviderRateLimitError(
                    retryAfterSeconds: nil,
                    bodyByteCount: 0
                )
            )
            let loadedDeadline = await gate.cooldownDeadline(
                providerIdentity: identity,
                generation: 0
            )
            let deadline = try XCTUnwrap(loadedDeadline)
            XCTAssertEqual(deadline.timeIntervalSince(clock.now()), delay, accuracy: 0.001)
            clock.advance(by: delay + 1)
            gate = ProviderRequestGate(now: clock.now, persistenceURL: stateURL)
        }
    }

    func testRateLimitWithoutHintSequenceResetsAfterInterveningFailures() async throws {
        let clock = ProviderGateClock()
        let cases: [(String, ProviderRequestFailureClass)] = [
            ("transport", .transport),
            ("auth", .auth),
            ("timeout", .timeout)
        ]
        for (identity, failureClass) in cases {
            let gate = ProviderRequestGate(now: clock.now)
            await gate.recordFailure(
                providerIdentity: identity,
                generation: 0,
                failure: ProviderRateLimitError(retryAfterSeconds: nil, bodyByteCount: 0)
            )
            await gate.recordFailure(
                providerIdentity: identity,
                generation: 0,
                failure: NSError(domain: "KnowTypeTests", code: 1),
                forcedClass: failureClass
            )
            await gate.recordFailure(
                providerIdentity: identity,
                generation: 0,
                failure: ProviderRateLimitError(retryAfterSeconds: nil, bodyByteCount: 0)
            )
            let loadedDeadline = await gate.cooldownDeadline(
                providerIdentity: identity,
                generation: 0
            )
            let deadline = try XCTUnwrap(loadedDeadline)
            XCTAssertEqual(deadline.timeIntervalSince(clock.now()), 15 * 60, accuracy: 0.001)
        }

        let hintedIdentity = "hinted-rate-limit"
        let hintedGate = ProviderRequestGate(now: clock.now)
        await hintedGate.recordFailure(
            providerIdentity: hintedIdentity,
            generation: 0,
            failure: ProviderRateLimitError(retryAfterSeconds: nil, bodyByteCount: 0)
        )
        await hintedGate.recordFailure(
            providerIdentity: hintedIdentity,
            generation: 0,
            failure: ProviderRateLimitError(retryAfterSeconds: 85 * 60 * 60, bodyByteCount: 1)
        )
        await hintedGate.recordFailure(
            providerIdentity: hintedIdentity,
            generation: 0,
            failure: ProviderRateLimitError(retryAfterSeconds: nil, bodyByteCount: 0)
        )
        let loadedHintedDeadline = await hintedGate.cooldownDeadline(
            providerIdentity: hintedIdentity,
            generation: 0
        )
        let hintedDeadline = try XCTUnwrap(loadedHintedDeadline)
        XCTAssertEqual(hintedDeadline.timeIntervalSince(clock.now()), 15 * 60, accuracy: 0.001)
    }

    func testNonRateLimitBackoffRemainsUnchanged() async throws {
        let clock = ProviderGateClock()
        let identity = "server-failure"
        let gate = ProviderRequestGate(now: clock.now)
        let expected: [TimeInterval] = [60, 120, 240, 480, 900, 900]

        for delay in expected {
            await gate.recordFailure(
                providerIdentity: identity,
                generation: 0,
                failure: ProviderError.httpStatus(503, "unavailable")
            )
            let loadedDeadline = await gate.cooldownDeadline(
                providerIdentity: identity,
                generation: 0
            )
            let deadline = try XCTUnwrap(loadedDeadline)
            XCTAssertEqual(deadline.timeIntervalSince(clock.now()), delay, accuracy: 0.001)
        }
    }

    func testPersistedDistantFutureCooldownIsBoundedAndWaiterDoesNotTrap() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("gate.json")
        let clock = ProviderGateClock()
        let identity = "distant-future-cooldown"
        let identityHash = ProviderRequestGate.identityHash(identity)
        let state: [String: Any] = [
            "entries": [[
                "identityHash": identityHash,
                "deadline": Date.distantFuture.timeIntervalSinceReferenceDate,
                "failureClass": ProviderRequestFailureClass.rateLimit.rawValue,
                "failureCount": 1
            ]]
        ]
        try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
            .write(to: stateURL, options: .atomic)

        let gate = ProviderRequestGate(now: clock.now, persistenceURL: stateURL)
        let loadedDeadline = await gate.cooldownDeadline(
            providerIdentity: identity,
            generation: 0
        )
        let deadline = try XCTUnwrap(loadedDeadline)
        let maximumCooldown: TimeInterval = 7 * 24 * 60 * 60
        XCTAssertEqual(
            deadline.timeIntervalSince(clock.now()),
            maximumCooldown,
            accuracy: 0.001
        )

        let rewrittenData = try Data(contentsOf: stateURL)
        let rewrittenObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: rewrittenData) as? [String: Any]
        )
        let rewrittenEntries = try XCTUnwrap(
            rewrittenObject["entries"] as? [[String: Any]]
        )
        let rewrittenDeadlineValue = try XCTUnwrap(
            rewrittenEntries.first?["deadline"] as? NSNumber
        )
        let rewrittenDeadline = Date(
            timeIntervalSinceReferenceDate: rewrittenDeadlineValue.doubleValue
        )
        XCTAssertEqual(
            rewrittenDeadline.timeIntervalSince(clock.now()),
            maximumCooldown,
            accuracy: 0.001
        )

        let waiter = Task {
            await gate.waitForAvailability(
                providerIdentity: identity,
                generation: 0
            )
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        waiter.cancel()
        await waiter.value
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
    }

    func testPersistentGateTreatsMissingFileErrorVariantsAsEmptyState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let errors: [NSError] = [
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError),
            NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT)),
            NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadUnknownError,
                userInfo: [
                    NSUnderlyingErrorKey: NSError(
                        domain: NSPOSIXErrorDomain,
                        code: Int(ENOENT)
                    )
                ]
            )
        ]

        for (index, error) in errors.enumerated() {
            let stateURL = directory.appendingPathComponent("gate-\(index).json")
            let fileManager = ProviderGateAttributesErrorFileManager(
                targetURL: stateURL,
                error: error
            )
            let gate = ProviderRequestGate(
                persistenceURL: stateURL,
                fileManager: fileManager
            )

            let preflight = await gate.persistencePreflight()
            XCTAssertEqual(
                preflight,
                .available,
                "missing file error must be treated as empty state: \(error)"
            )
            let value = try await gate.execute(
                providerIdentity: "missing-file-provider-\(index)",
                generation: 0
            ) { 1 }
            XCTAssertEqual(value, 1)
        }
    }

    func testPersistentGatePermissionFailureRecoversOnGenerationChange() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("gate.json")
        let clock = ProviderGateClock()
        let identity = "permission-secret-provider"
        let seed = ProviderRequestGate(now: clock.now, persistenceURL: stateURL)
        await seed.recordFailure(
            providerIdentity: identity,
            generation: 0,
            failure: ProviderError.httpStatus(503, "unavailable")
        )
        let probe = ProviderRequestGateTestProbe()
        probe.failNextPermissionChanges(1)
        let gate = ProviderRequestGate(
            now: clock.now,
            persistenceURL: stateURL,
            testProbe: probe
        )
        let operation = RequestGateProbe()

        do {
            _ = try await gate.execute(providerIdentity: identity, generation: 0) {
                await operation.markStarted()
                return 1
            }
            XCTFail("permission failure must block dispatch")
        } catch ProviderRequestGatePersistenceError.blocked {
            // Expected.
        }

        await gate.invalidate(providerIdentity: identity, generation: 0)
        let value = try await gate.execute(providerIdentity: identity, generation: 1) {
            await operation.markStarted()
            return 2
        }

        XCTAssertEqual(value, 2)
        let operationStartCount = await operation.startCount
        XCTAssertEqual(operationStartCount, 1)
        XCTAssertEqual(probe.persistenceRecoveryProbeCount, 1)
        XCTAssertEqual(probe.persistenceRecoveryCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
    }

    func testPersistentGateCorruptStateRecoversAfterAtomicReplacement() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("gate.json")
        let identity = "corrupt-secret-provider"
        let clock = ProviderGateClock()
        try Data("corrupt".utf8).write(to: stateURL)
        let probe = ProviderRequestGateTestProbe()
        let gate = ProviderRequestGate(
            now: clock.now,
            persistenceURL: stateURL,
            testProbe: probe
        )
        let operation = RequestGateProbe()

        do {
            _ = try await gate.execute(providerIdentity: identity, generation: 0) {
                await operation.markStarted()
                return 1
            }
            XCTFail("corrupt persistent state must block dispatch")
        } catch ProviderRequestGatePersistenceError.blocked {
            // Expected.
        }

        let operationStarted = await operation.hasStarted
        XCTAssertFalse(operationStarted)
        XCTAssertFalse(
            String(decoding: try Data(contentsOf: stateURL), as: UTF8.self).contains(identity)
        )

        try Data(#"{"entries":[]}"#.utf8).write(to: stateURL, options: .atomic)
        guard case .persistenceBlocked = await gate.preflight(
            providerIdentity: identity,
            generation: 0
        ) else {
            return XCTFail("recovery must honor the initial retry deadline")
        }
        XCTAssertEqual(probe.persistenceRecoveryProbeCount, 0)

        clock.advance(by: 5)
        let recovered = await gate.preflight(providerIdentity: identity, generation: 0)
        XCTAssertEqual(recovered, .available)
        let value = try await gate.execute(providerIdentity: identity, generation: 0) {
            await operation.markStarted()
            return 2
        }

        XCTAssertEqual(value, 2)
        let operationStartCount = await operation.startCount
        XCTAssertEqual(operationStartCount, 1)
        XCTAssertEqual(probe.persistenceBlockCount, 1)
        XCTAssertEqual(probe.persistenceRecoveryProbeCount, 1)
        XCTAssertEqual(probe.persistenceRecoveryCount, 1)
    }

    func testPersistentGateCorruptStateRecoversAfterSafeRemoval() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("gate.json")
        let clock = ProviderGateClock()
        let identity = "removed-corrupt-provider"
        try Data("corrupt".utf8).write(to: stateURL)
        let probe = ProviderRequestGateTestProbe()
        let gate = ProviderRequestGate(
            now: clock.now,
            persistenceURL: stateURL,
            testProbe: probe
        )

        guard case .persistenceBlocked = await gate.preflight(
            providerIdentity: identity,
            generation: 0
        ) else {
            return XCTFail("corrupt state must fail closed")
        }
        try FileManager.default.removeItem(at: stateURL)
        clock.advance(by: 5)

        let value = try await gate.execute(providerIdentity: identity, generation: 0) { 3 }
        XCTAssertEqual(value, 3)
        XCTAssertEqual(probe.persistenceRecoveryProbeCount, 1)
        XCTAssertEqual(probe.persistenceRecoveryCount, 1)
    }

    func testPersistentGateRecoveryBackoffGrowsAndCapsWithoutExtraIO() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("gate.json")
        try Data("corrupt".utf8).write(to: stateURL)
        let clock = ProviderGateClock()
        let probe = ProviderRequestGateTestProbe()
        let gate = ProviderRequestGate(
            now: clock.now,
            persistenceURL: stateURL,
            testProbe: probe
        )
        let expectedDelays: [TimeInterval] = [5, 10, 20, 40, 60, 60]

        for expectedDelay in expectedDelays {
            guard case .persistenceBlocked(let retryAt) = await gate.preflight(
                providerIdentity: "backoff-provider",
                generation: 0
            ) else {
                return XCTFail("corrupt persistence must remain fail-closed")
            }
            XCTAssertEqual(retryAt.timeIntervalSince(clock.now()), expectedDelay, accuracy: 0.001)

            let probeCount = probe.persistenceRecoveryProbeCount
            guard case .persistenceBlocked(let repeatedRetryAt) = await gate.preflight(
                providerIdentity: "backoff-provider",
                generation: 0
            ) else {
                return XCTFail("preflight before the deadline must stay blocked")
            }
            XCTAssertEqual(repeatedRetryAt, retryAt)
            XCTAssertEqual(probe.persistenceRecoveryProbeCount, probeCount)
            clock.advance(by: expectedDelay)
        }

        XCTAssertEqual(probe.persistenceBlockCount, expectedDelays.count)
        XCTAssertEqual(probe.persistenceRecoveryProbeCount, expectedDelays.count - 1)
        XCTAssertEqual(probe.persistenceRecoveryCount, 0)
    }

    func testGenerationInvalidationDoesNotResurrectCooldownAfterRecoveryRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("gate.json")
        let identity = "stale-cooldown-provider"
        let clock = ProviderGateClock()
        let seed = ProviderRequestGate(now: clock.now, persistenceURL: stateURL)
        await seed.recordFailure(
            providerIdentity: identity,
            generation: 0,
            failure: ProviderError.httpStatus(503, "unavailable")
        )

        let probe = ProviderRequestGateTestProbe()
        probe.failNextPermissionChanges(2)
        let gate = ProviderRequestGate(
            now: clock.now,
            persistenceURL: stateURL,
            testProbe: probe
        )
        guard case .persistenceBlocked = await gate.preflight(
            providerIdentity: identity,
            generation: 0
        ) else {
            return XCTFail("initial permission failure must block dispatch")
        }

        await gate.invalidate(providerIdentity: identity, generation: 0)
        guard case .persistenceBlocked(let retryAt) = await gate.preflight(
            providerIdentity: identity,
            generation: 1
        ) else {
            return XCTFail("failed generation recovery must remain blocked")
        }
        XCTAssertEqual(retryAt.timeIntervalSince(clock.now()), 10, accuracy: 0.001)

        clock.advance(by: 10)
        let recovered = await gate.preflight(providerIdentity: identity, generation: 1)
        XCTAssertEqual(recovered, .available)
        let value = try await gate.execute(providerIdentity: identity, generation: 1) { 4 }

        XCTAssertEqual(value, 4)
        XCTAssertEqual(probe.persistenceRecoveryProbeCount, 2)
        XCTAssertEqual(probe.persistenceRecoveryCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
    }

    func testStaleGenerationInvalidationDoesNotForcePersistenceRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("gate.json")
        let clock = ProviderGateClock()
        let probe = ProviderRequestGateTestProbe()
        probe.failNextWrites(1)
        let gate = ProviderRequestGate(
            now: clock.now,
            persistenceURL: stateURL,
            testProbe: probe
        )
        await gate.recordFailure(
            providerIdentity: "stale-invalidation-provider",
            generation: 5,
            failure: ProviderError.httpStatus(503, "unavailable")
        )
        XCTAssertEqual(probe.persistenceBlockCount, 1)

        await gate.invalidate(
            providerIdentity: "stale-invalidation-provider",
            expectedGeneration: 0,
            newGeneration: 1
        )
        guard case .persistenceBlocked(let retryAt) = await gate.preflight(
            providerIdentity: "stale-invalidation-provider",
            generation: 5
        ) else {
            return XCTFail("stale invalidation must leave persistence backoff intact")
        }

        XCTAssertEqual(retryAt.timeIntervalSince(clock.now()), 5, accuracy: 0.001)
        XCTAssertEqual(probe.persistenceRecoveryProbeCount, 0)
        XCTAssertEqual(probe.persistenceRecoveryCount, 0)
    }

    func testGatePreflightDistinguishesCooldownStaleAndPersistenceBlockedWithoutAdmission() async throws {
        let now = Date()
        let identity = "preflight-private-provider"
        let gate = ProviderRequestGate(now: { now })

        let available = await gate.preflight(providerIdentity: identity, generation: 0)
        XCTAssertEqual(available, .available)

        await gate.recordFailure(
            providerIdentity: identity,
            generation: 0,
            failure: ProviderError.httpStatus(503, "unavailable")
        )
        let coolingDown = await gate.preflight(providerIdentity: identity, generation: 0)
        guard case .cooldown(let deadline, let failureClass) = coolingDown else {
            return XCTFail("expected cooldown preflight")
        }
        XCTAssertEqual(deadline.timeIntervalSince(now), 60, accuracy: 0.001)
        XCTAssertEqual(failureClass, .server5xx)

        await gate.invalidate(providerIdentity: identity, generation: 0)
        let stale = await gate.preflight(providerIdentity: identity, generation: 0)
        XCTAssertEqual(stale, .staleGeneration)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("gate.json")
        try Data("corrupt-value-only-state".utf8).write(to: stateURL)
        let probe = ProviderRequestGateTestProbe()
        let blockedGate = ProviderRequestGate(persistenceURL: stateURL, testProbe: probe)
        for _ in 0..<10 {
            let blocked = await blockedGate.preflight(
                providerIdentity: identity,
                generation: 0
            )
            guard case .persistenceBlocked = blocked else {
                return XCTFail("expected persistence-blocked preflight")
            }
        }

        XCTAssertEqual(probe.preflightCheckCount, 10)
        XCTAssertEqual(probe.admittedAttemptCount, 0)
        XCTAssertEqual(probe.persistenceRecoveryProbeCount, 0)
        let persisted = String(decoding: try Data(contentsOf: stateURL), as: UTF8.self)
        XCTAssertFalse(persisted.contains(identity))
    }

    func testPersistentGateCooldownWriteFailureBlocksSubsequentDispatch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("gate.json")
        let identity = "write-secret-provider"
        let clock = ProviderGateClock()
        let probe = ProviderRequestGateTestProbe()
        probe.failNextWrites(1)
        let gate = ProviderRequestGate(
            now: clock.now,
            persistenceURL: stateURL,
            testProbe: probe
        )
        let operation = RequestGateProbe()

        do {
            _ = try await gate.execute(providerIdentity: identity, generation: 0) {
                await operation.markStarted()
                throw ProviderError.httpStatus(503, "unavailable")
            } as Int
            XCTFail("expected provider failure")
        } catch ProviderError.httpStatus(let status, _) {
            XCTAssertEqual(status, 503)
        }

        do {
            _ = try await gate.execute(providerIdentity: identity, generation: 0) {
                await operation.markStarted()
                return 2
            }
            XCTFail("failed cooldown persistence must block later dispatch")
        } catch ProviderRequestGatePersistenceError.blocked {
            // Expected.
        }

        let operationStartCount = await operation.startCount
        XCTAssertEqual(operationStartCount, 1)
        clock.advance(by: 5)
        let recovered = await gate.preflight(providerIdentity: identity, generation: 0)
        guard case .cooldown(let deadline, let failureClass) = recovered else {
            return XCTFail("recovered write must preserve the active cooldown")
        }
        XCTAssertEqual(failureClass, .server5xx)
        XCTAssertEqual(deadline.timeIntervalSince(clock.now()), 55, accuracy: 0.001)
        XCTAssertEqual(probe.persistenceRecoveryProbeCount, 1)
        XCTAssertEqual(probe.persistenceRecoveryCount, 1)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for file in files {
            let data = try Data(contentsOf: file)
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(identity))
        }
    }

    func testStartedTransportFailureDuringPersistenceBackoffDefersRewrite() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("gate.json")
        let clock = ProviderGateClock()
        let probe = ProviderRequestGateTestProbe()
        probe.failNextWrites(2)
        let gate = ProviderRequestGate(
            now: clock.now,
            persistenceURL: stateURL,
            testProbe: probe
        )
        let operation = SuspendedFailingGateOperation()
        let request = Task {
            try await gate.execute(providerIdentity: "started-provider", generation: 0) {
                try await operation.run()
            }
        }
        try await waitUntil { await operation.started }

        await gate.recordFailure(
            providerIdentity: "blocking-provider",
            generation: 0,
            failure: ProviderError.httpStatus(503, "unavailable")
        )
        XCTAssertEqual(probe.persistenceBlockCount, 1)

        await operation.finish()
        do {
            _ = try await request.value
            XCTFail("started provider must return its failure")
        } catch ProviderError.httpStatus(let status, _) {
            XCTAssertEqual(status, 503)
        }
        XCTAssertEqual(
            probe.persistenceBlockCount,
            1,
            "started completion must update memory without touching disk during backoff"
        )

        clock.advance(by: 5)
        guard case .persistenceBlocked(let retryAt) = await gate.preflight(
            providerIdentity: "started-provider",
            generation: 0
        ) else {
            return XCTFail("the first deferred rewrite retry is intentionally failed")
        }
        XCTAssertEqual(retryAt.timeIntervalSince(clock.now()), 10, accuracy: 0.001)

        clock.advance(by: 10)
        guard case .cooldown(_, let startedFailureClass) = await gate.preflight(
            providerIdentity: "started-provider",
            generation: 0
        ) else {
            return XCTFail("recovery must persist the started transport failure")
        }
        guard case .cooldown(_, let blockingFailureClass) = await gate.preflight(
            providerIdentity: "blocking-provider",
            generation: 0
        ) else {
            return XCTFail("recovery must retain the failure that entered backoff")
        }
        XCTAssertEqual(startedFailureClass, .server5xx)
        XCTAssertEqual(blockingFailureClass, .server5xx)
        XCTAssertEqual(probe.persistenceBlockCount, 2)
        XCTAssertEqual(probe.persistenceRecoveryProbeCount, 2)
        XCTAssertEqual(probe.persistenceRecoveryCount, 1)
    }

    func testPersistenceRecoveryPreservesEveryProviderCooldownClass() async throws {
        for failureClass in [
            ProviderRequestFailureClass.auth,
            .rateLimit,
            .server5xx,
            .timeout
        ] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stateURL = directory.appendingPathComponent("gate.json")
            let clock = ProviderGateClock()
            let probe = ProviderRequestGateTestProbe()
            probe.failNextWrites(1)
            let gate = ProviderRequestGate(
                now: clock.now,
                persistenceURL: stateURL,
                testProbe: probe
            )
            let identity = "cooldown-\(failureClass.rawValue)"

            await gate.recordFailure(
                providerIdentity: identity,
                generation: 0,
                failure: NSError(domain: "KnowTypeTests", code: 1),
                forcedClass: failureClass
            )
            clock.advance(by: 5)
            guard case .cooldown(let deadline, let recoveredClass) = await gate.preflight(
                providerIdentity: identity,
                generation: 0
            ) else {
                return XCTFail("recovery must retain the \(failureClass.rawValue) cooldown")
            }

            XCTAssertEqual(recoveredClass, failureClass)
            let expectedRemaining: TimeInterval = failureClass == .rateLimit ? 895 : 55
            XCTAssertEqual(
                deadline.timeIntervalSince(clock.now()),
                expectedRemaining,
                accuracy: 0.001
            )
            XCTAssertEqual(probe.persistenceRecoveryProbeCount, 1)
            XCTAssertEqual(probe.persistenceRecoveryCount, 1)
        }
    }

    func testPersistenceRecoveryDoesNotDuplicateStartedTransport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("gate.json")
        let clock = ProviderGateClock()
        let probe = ProviderRequestGateTestProbe()
        probe.failNextWrites(1)
        let gate = ProviderRequestGate(
            now: clock.now,
            persistenceURL: stateURL,
            testProbe: probe
        )
        let operation = SuspendedGateOperation()
        let request = Task {
            try await gate.execute(providerIdentity: "in-flight-provider", generation: 0) {
                await operation.run()
                return 1
            }
        }
        try await waitUntil { await operation.started }

        await gate.recordFailure(
            providerIdentity: "blocking-provider",
            generation: 0,
            failure: ProviderError.httpStatus(503, "unavailable")
        )
        clock.advance(by: 5)
        let recoveredState = await gate.preflight(
            providerIdentity: "in-flight-provider",
            generation: 0
        )
        XCTAssertEqual(recoveredState, .busy)
        do {
            _ = try await gate.execute(providerIdentity: "in-flight-provider", generation: 0) { 2 }
            XCTFail("recovery must not admit a duplicate transport")
        } catch ProviderRequestGateError.busy {
            // Expected.
        }

        XCTAssertEqual(probe.admittedAttemptCount, 1)
        XCTAssertEqual(probe.persistenceRecoveryCount, 1)
        await operation.finish()
        let value = try await request.value
        XCTAssertEqual(value, 1)
    }

    func testPersistentGateReadFailureBlocksProviderDispatch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stateURL = directory.appendingPathComponent("gate.json")
        let clock = ProviderGateClock()
        let identity = "read-secret-provider"
        let seed = ProviderRequestGate(now: clock.now, persistenceURL: stateURL)
        await seed.recordFailure(
            providerIdentity: identity,
            generation: 0,
            failure: ProviderError.httpStatus(503, "unavailable")
        )
        let probe = ProviderRequestGateTestProbe()
        probe.failNextReads(1)
        let gate = ProviderRequestGate(
            now: clock.now,
            persistenceURL: stateURL,
            testProbe: probe
        )
        let operation = RequestGateProbe()

        do {
            _ = try await gate.execute(providerIdentity: identity, generation: 0) {
                await operation.markStarted()
                return 1
            }
            XCTFail("read failure must block dispatch")
        } catch ProviderRequestGatePersistenceError.blocked {
            // Expected.
        }

        let operationStarted = await operation.hasStarted
        XCTAssertFalse(operationStarted)
        clock.advance(by: 61)
        let value = try await gate.execute(providerIdentity: identity, generation: 0) {
            await operation.markStarted()
            return 2
        }
        XCTAssertEqual(value, 2)
        let operationStartCount = await operation.startCount
        XCTAssertEqual(operationStartCount, 1)
        XCTAssertEqual(probe.persistenceRecoveryProbeCount, 1)
        XCTAssertEqual(probe.persistenceRecoveryCount, 1)
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
        let completionProbe = GateAttemptCompletionProbe()
        let oldRequest = Task {
            do {
                _ = try await gate.executeWithHardTimeout(
                    providerIdentity: "generation-provider",
                    generation: 0,
                    timeoutNanoseconds: 5_000_000_000,
                    onAttemptCompletion: {
                        await completionProbe.recordCompletion()
                    }
                ) {
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
        let preflightWhileOldTransportRuns = await gate.preflight(
            providerIdentity: "generation-provider",
            generation: 1
        )
        XCTAssertEqual(preflightWhileOldTransportRuns, .busy)
        let completionCountBeforeOldTransportFinishes = await completionProbe.completionCount
        XCTAssertEqual(completionCountBeforeOldTransportFinishes, 0)
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
        let finalCompletionCount = await completionProbe.completionCount
        XCTAssertEqual(finalCompletionCount, 1)
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
        let unwrappedTimeoutDeadline = try XCTUnwrap(timeoutDeadline)
        XCTAssertEqual(unwrappedTimeoutDeadline.timeIntervalSince(now), 60, accuracy: 0.001)

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
        let unwrappedFinalDeadline = try XCTUnwrap(finalDeadline)
        XCTAssertEqual(unwrappedFinalDeadline.timeIntervalSince(now), 60, accuracy: 0.001)
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
        let unwrappedDeadline = try XCTUnwrap(deadline)
        XCTAssertEqual(unwrappedDeadline.timeIntervalSince(now), 60, accuracy: 0.001)
        do {
            _ = try await gate.execute(providerIdentity: identity, generation: 0) { 1 }
            XCTFail("late 5xx must retain the owning timeout cooldown")
        } catch ProviderRequestGateError.cooldown {
            // Expected after the cancellation-triggered completion releases the lease.
        }
    }

    func testHardTimeoutBeforeTransportPreventsLateProviderStart() async throws {
        let identity = "timeout-before-transport"
        let clock = ProviderGateClock()
        let testProbe = ProviderRequestGateTestProbe()
        let admissionPause = GateAttemptAdmissionPause()
        let operationProbe = RequestGateProbe()
        let completionProbe = GateAttemptCompletionProbe()
        let gate = ProviderRequestGate(
            now: clock.now,
            testProbe: testProbe,
            afterAttemptAdmission: {
                await admissionPause.suspendIfNeeded()
            }
        )
        let request = Task<Int, Error> {
            try await gate.executeWithHardTimeout(
                providerIdentity: identity,
                generation: 0,
                timeoutNanoseconds: 20_000_000,
                onAttemptCompletion: {
                    await completionProbe.recordCompletion()
                }
            ) {
                await operationProbe.markStarted()
                return 1
            }
        }

        do {
            try await waitUntil { await admissionPause.hasEntered }
        } catch {
            request.cancel()
            await admissionPause.release()
            _ = try? await request.value
            throw error
        }
        let entered = await admissionPause.hasEntered
        guard entered else {
            request.cancel()
            await admissionPause.release()
            _ = try? await request.value
            return
        }

        var observedTimeout = false
        do {
            _ = try await request.value
            XCTFail("expected timeout before transport start")
        } catch is TimeoutError {
            observedTimeout = true
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertTrue(observedTimeout)

        let startCountBeforeRelease = await operationProbe.startCount
        let completionCountAtTimeout = await completionProbe.completionCount
        XCTAssertEqual(startCountBeforeRelease, 0)
        XCTAssertEqual(completionCountAtTimeout, 1)

        let preflight = await gate.preflight(providerIdentity: identity, generation: 0)
        switch preflight {
        case .cooldown(let deadline, let failureClass):
            XCTAssertEqual(failureClass, .timeout)
            XCTAssertEqual(deadline.timeIntervalSince(clock.now()), 60, accuracy: 0.001)
        default:
            XCTFail("pre-transport timeout must release busy ownership into cooldown")
        }

        await admissionPause.release()
        try await waitUntil { testProbe.rejectedTransportStartCount == 1 }
        let rejectedStarts = testProbe.rejectedTransportStartCount
        let providerStartsAfterRelease = await operationProbe.startCount
        let finalCompletionCount = await completionProbe.completionCount
        XCTAssertEqual(rejectedStarts, 1)
        XCTAssertEqual(providerStartsAfterRelease, 0)
        XCTAssertEqual(finalCompletionCount, 1)

        clock.advance(by: 61)
        let replacementProbe = RequestGateProbe()
        let replacement = try await gate.execute(
            providerIdentity: identity,
            generation: 0
        ) {
            await replacementProbe.markStarted()
            return 2
        }
        let replacementStartCount = await replacementProbe.startCount
        XCTAssertEqual(replacement, 2)
        XCTAssertEqual(replacementStartCount, 1)
        XCTAssertEqual(testProbe.admittedAttemptCount, 2)
    }

    func testGenerationInvalidateBeforeTransportAbortsOnlyStaleAttempt() async throws {
        let identity = "invalidate-before-transport"
        let testProbe = ProviderRequestGateTestProbe()
        let admissionPause = GateAttemptAdmissionPause()
        let staleOperationProbe = RequestGateProbe()
        let completionProbe = GateAttemptCompletionProbe()
        let gate = ProviderRequestGate(
            testProbe: testProbe,
            afterAttemptAdmission: {
                await admissionPause.suspendIfNeeded()
            }
        )
        let staleRequest = Task<Int, Error> {
            try await gate.executeWithHardTimeout(
                providerIdentity: identity,
                generation: 0,
                timeoutNanoseconds: 1_000_000_000,
                onAttemptCompletion: {
                    await completionProbe.recordCompletion()
                }
            ) {
                await staleOperationProbe.markStarted()
                return 1
            }
        }

        do {
            try await waitUntil { await admissionPause.hasEntered }
        } catch {
            staleRequest.cancel()
            await admissionPause.release()
            _ = try? await staleRequest.value
            throw error
        }
        let entered = await admissionPause.hasEntered
        guard entered else {
            staleRequest.cancel()
            await admissionPause.release()
            _ = try? await staleRequest.value
            return
        }

        await gate.invalidate(providerIdentity: identity, generation: 0)
        let completionCountAfterInvalidate = await completionProbe.completionCount
        let staleStartsAfterInvalidate = await staleOperationProbe.startCount
        XCTAssertEqual(completionCountAfterInvalidate, 1)
        XCTAssertEqual(staleStartsAfterInvalidate, 0)

        let replacementOperation = SuspendedGateOperation()
        let replacement = Task<Int, Error> {
            try await gate.execute(providerIdentity: identity, generation: 1) {
                await replacementOperation.run()
                return 2
            }
        }
        do {
            try await waitUntil { await replacementOperation.started }
        } catch {
            staleRequest.cancel()
            replacement.cancel()
            await admissionPause.release()
            await replacementOperation.finish()
            _ = try? await staleRequest.value
            _ = try? await replacement.value
            throw error
        }
        let replacementStarted = await replacementOperation.started
        guard replacementStarted else {
            staleRequest.cancel()
            replacement.cancel()
            await admissionPause.release()
            await replacementOperation.finish()
            _ = try? await staleRequest.value
            _ = try? await replacement.value
            return
        }

        var observedStaleGeneration = false
        do {
            _ = try await staleRequest.value
            XCTFail("expected stale generation after pre-transport invalidation")
        } catch ProviderRequestGateError.staleGeneration {
            observedStaleGeneration = true
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertTrue(observedStaleGeneration)

        let newAttemptStillBusy = await gate.preflight(
            providerIdentity: identity,
            generation: 1
        )
        XCTAssertEqual(newAttemptStillBusy, .busy)

        await admissionPause.release()
        do {
            try await waitUntil { testProbe.rejectedTransportStartCount == 1 }
        } catch {
            replacement.cancel()
            await replacementOperation.finish()
            _ = try? await replacement.value
            throw error
        }
        let rejectedStarts = testProbe.rejectedTransportStartCount
        let staleProviderStarts = await staleOperationProbe.startCount
        let finalCompletionCount = await completionProbe.completionCount
        XCTAssertEqual(rejectedStarts, 1)
        XCTAssertEqual(staleProviderStarts, 0)
        XCTAssertEqual(finalCompletionCount, 1)

        await replacementOperation.finish()
        let replacementValue = try await replacement.value
        XCTAssertEqual(replacementValue, 2)
        XCTAssertEqual(testProbe.admittedAttemptCount, 2)
        let cooldown = await gate.cooldownDeadline(
            providerIdentity: identity,
            generation: 1
        )
        XCTAssertNil(cooldown)
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

    func testCallerCancellationAfterAdmissionBeforeTransportAbortsAttempt() async throws {
        let identity = "cancel-after-admission"
        let testProbe = ProviderRequestGateTestProbe()
        let admissionPause = GateAttemptAdmissionPause()
        let operationProbe = RequestGateProbe()
        let gate = ProviderRequestGate(
            testProbe: testProbe,
            afterAttemptAdmission: {
                await admissionPause.suspendIfNeeded()
            }
        )
        let request = Task<Int, Error> {
            try await gate.executeWithHardTimeout(
                providerIdentity: identity,
                generation: 0,
                timeoutNanoseconds: 1_000_000_000
            ) {
                await operationProbe.markStarted()
                return 1
            }
        }

        try await waitUntil { await admissionPause.hasEntered }
        let entered = await admissionPause.hasEntered
        guard entered else {
            request.cancel()
            await admissionPause.release()
            _ = try? await request.value
            return
        }
        request.cancel()
        let cancelledOperationStarted = await operationProbe.hasStarted
        XCTAssertFalse(cancelledOperationStarted)
        let replacement = Task<Int, Error> {
            await gate.waitForAvailability(providerIdentity: identity, generation: 0)
            return try await gate.execute(providerIdentity: identity, generation: 0) {
                await operationProbe.markStarted()
                return 2
            }
        }
        try await waitUntil { await operationProbe.hasStarted }
        let replacementStarted = await operationProbe.hasStarted
        guard replacementStarted else {
            await admissionPause.release()
            replacement.cancel()
            _ = try? await replacement.value
            _ = try? await request.value
            return
        }
        let value = try await replacement.value
        XCTAssertEqual(value, 2)

        await admissionPause.release()
        do {
            _ = try await request.value
            XCTFail("expected caller cancellation")
        } catch is CancellationError {
            // The matching admitted attempt is aborted before transport starts.
        }

        let cooldown = await gate.cooldownDeadline(
            providerIdentity: identity,
            generation: 0
        )
        XCTAssertNil(cooldown)
        XCTAssertEqual(testProbe.admittedAttemptCount, 2)
        let finalStartCount = await operationProbe.startCount
        XCTAssertEqual(finalStartCount, 1)
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
        let unwrappedDeadline = try XCTUnwrap(deadline)
        XCTAssertEqual(unwrappedDeadline.timeIntervalSince(now), 15 * 60, accuracy: 0.001)
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
    private var starts = 0
    private var didFinishAvailabilityWait = false

    func markStarted() {
        started = true
        starts += 1
    }

    var hasStarted: Bool {
        started
    }

    var startCount: Int {
        starts
    }

    func markAvailabilityFinished() {
        didFinishAvailabilityWait = true
    }

    var availabilityFinished: Bool {
        didFinishAvailabilityWait
    }
}

private actor GateAttemptAdmissionPause {
    private var entered = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    var hasEntered: Bool {
        entered
    }

    func suspendIfNeeded() async {
        guard !entered else { return }
        entered = true
        guard !released else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private actor GateAttemptCompletionProbe {
    private var completions = 0

    func recordCompletion() {
        completions += 1
    }

    var completionCount: Int {
        completions
    }
}

private actor GateAttemptCompletionPause {
    private var entered = false
    private var released = false
    private var completions = 0
    private var continuation: CheckedContinuation<Void, Never>?

    var hasEntered: Bool {
        entered
    }

    var completionCount: Int {
        completions
    }

    func suspendAndRecord() async {
        completions += 1
        entered = true
        guard !released else { return }
        await withCheckedContinuation { continuation in
            if released {
                continuation.resume()
            } else {
                self.continuation = continuation
            }
        }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private actor RegistryCapabilityResetPause {
    private var pausesNextReset = false
    private var entered = false
    private var released = false
    private var resets = 0
    private var continuation: CheckedContinuation<Void, Never>?

    var hasEntered: Bool {
        entered
    }

    var resetCount: Int {
        resets
    }

    func pauseNextReset() {
        pausesNextReset = true
        entered = false
        released = false
    }

    func reset() async {
        resets += 1
        guard pausesNextReset else { return }
        pausesNextReset = false
        entered = true
        guard !released else { return }
        await withCheckedContinuation { continuation in
            if released {
                continuation.resume()
            } else {
                self.continuation = continuation
            }
        }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private final class RegistryGenerationTransitionWaitProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var waits = 0

    var waitCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return waits
    }

    func recordWait() {
        lock.lock()
        waits += 1
        lock.unlock()
    }
}

private final class RegistryRevisionObservationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var revisions: [UInt64] = []

    var observedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return revisions.count
    }

    func record(_ revision: UInt64) {
        lock.lock()
        revisions.append(revision)
        lock.unlock()
    }
}

private final class ProviderGateClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(interval)
        lock.unlock()
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
    private var runtimeOverride: ProviderRuntimeLoadResult?
    private var runtimeSequence: [ProviderRuntimeLoadResult?] = []
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
        if !runtimeSequence.isEmpty {
            return runtimeSequence.removeFirst()
        }
        return runtimeOverride ?? ProviderRuntimeLoadResult(
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

    func setRuntimeOverride(
        revision: UInt64,
        fingerprint: String,
        provider: (any LLMProvider)?
    ) {
        lock.lock()
        runtimeOverride = ProviderRuntimeLoadResult(
            revision: revision,
            fingerprint: fingerprint,
            provider: provider
        )
        lock.unlock()
    }

    func clearRuntimeOverride() {
        lock.lock()
        runtimeOverride = nil
        lock.unlock()
    }

    func setRuntimeSequence(_ results: [ProviderRuntimeLoadResult?]) {
        lock.lock()
        runtimeSequence = results
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

private final class ProviderGateAttributesErrorFileManager: FileManager, @unchecked Sendable {
    private let targetPath: String
    private let error: NSError

    init(targetURL: URL, error: NSError) {
        self.targetPath = targetURL.path
        self.error = error
        super.init()
    }

    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        if path == targetPath { throw error }
        return try super.attributesOfItem(atPath: path)
    }
}
