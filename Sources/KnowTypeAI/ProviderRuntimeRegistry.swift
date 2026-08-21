import Foundation
import KnowTypeCore
import KnowTypeProviders

public struct ProviderRuntimeLease: Sendable {
    public var revision: UInt64
    public var generation: UInt64
    public var fingerprint: String
    public var provider: (any LLMProvider)?

    public init(
        revision: UInt64,
        generation: UInt64,
        fingerprint: String,
        provider: (any LLMProvider)?
    ) {
        self.revision = revision
        self.generation = generation
        self.fingerprint = fingerprint
        self.provider = provider
    }
}

public enum ProviderRuntimeRegistryError: Error, Sendable, Equatable {
    case staleGeneration
    case providerUnavailable
}

public enum ProviderRuntimeDiagnosticStage: String, Sendable, Equatable {
    case loaded
    case generationChanged = "generation_changed"
    case staleResultDropped = "stale_result_dropped"
}

public struct ProviderRuntimeDiagnosticEvent: Sendable, Equatable {
    public var stage: ProviderRuntimeDiagnosticStage
    public var revision: UInt64
    public var generation: UInt64
    public var fingerprintPrefix: String
    public var providerConfigured: Bool

    public init(
        stage: ProviderRuntimeDiagnosticStage,
        revision: UInt64,
        generation: UInt64,
        fingerprint: String,
        providerConfigured: Bool
    ) {
        self.stage = stage
        self.revision = revision
        self.generation = generation
        self.fingerprintPrefix = String(fingerprint.prefix(12))
        self.providerConfigured = providerConfigured
    }
}

public protocol ProviderRuntimeDiagnosticSink: Sendable {
    func record(_ event: ProviderRuntimeDiagnosticEvent)
}

public struct NoopProviderRuntimeDiagnosticSink: ProviderRuntimeDiagnosticSink {
    public init() {}
    public func record(_ event: ProviderRuntimeDiagnosticEvent) {}
}

public struct InputDebugProviderRuntimeDiagnosticSink: ProviderRuntimeDiagnosticSink {
    public init() {}

    public func record(_ event: ProviderRuntimeDiagnosticEvent) {
        InputDebugDiagnostics.emit(category: .ai, fields: Self.fields(for: event))
    }

    public static func fields(for event: ProviderRuntimeDiagnosticEvent) -> [InputDebugDiagnostics.Field] {
        [
            .init(.stage, "provider_runtime_\(event.stage.rawValue)"),
            .init(.providerRevision, event.revision),
            .init(.providerGeneration, event.generation),
            .init(.providerFingerprint, event.fingerprintPrefix),
            .init(.providerConfigured, event.providerConfigured ? "true" : "false")
        ]
    }
}

public actor ProviderRuntimeRegistry {
    public typealias RevisionLoader = @Sendable () -> UInt64?
    public typealias RuntimeLoader = @Sendable () -> ProviderRuntimeLoadResult?
    public typealias RevisionUpdates = @Sendable () -> AsyncStream<UInt64>
    public typealias CapabilityReset = @Sendable () async -> Void

    public static let shared = ProviderRuntimeRegistry()

    private static let unavailableFingerprint = String(repeating: "0", count: 64)

    private struct GenerationTransitionTarget {
        let revision: UInt64
        let fingerprint: String
        let providerConfigured: Bool
    }

    private struct GenerationTransition {
        let id: UUID
        let newGeneration: UInt64
        var revision: UInt64
        var fingerprint: String
        var providerConfigured: Bool
        var pendingTarget: GenerationTransitionTarget?
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let revisionLoader: RevisionLoader
    private let runtimeLoader: RuntimeLoader
    private let revisionUpdates: RevisionUpdates
    private let capabilityReset: CapabilityReset
    private let diagnosticSink: any ProviderRuntimeDiagnosticSink
    public nonisolated let requestGate: ProviderRequestGate
    private var currentLease: ProviderRuntimeLease?
    private var generation: UInt64 = 0
    private var latestSignaledRevision: UInt64?
    private var leasePublicationPending = false
    private var observationTask: Task<Void, Never>?
    private var activeOperations: [UUID: @Sendable () -> Void] = [:]
    private var generationTransition: GenerationTransition?
    private var generationTransitionWaitObserver: (@Sendable () -> Void)?
    private var revisionObservationObserver: (@Sendable (UInt64) -> Void)?
    private var lastCompletedGenerationTransitionID: UUID?

    private struct GenerationTransitionResult {
        let id: UUID
        let generation: UInt64
        let revision: UInt64
    }

    public init(
        revisionLoader: @escaping RevisionLoader = {
            ProviderRuntimeLoader.loadDefaultProviderRevision(createProfileDirectory: false)
        },
        runtimeLoader: @escaping RuntimeLoader = {
            ProviderRuntimeLoader.loadDefaultProviderRuntime(createProfileDirectory: false)
        },
        revisionUpdates: @escaping RevisionUpdates = {
            DistributedProviderProfileRevisionSignal().revisionUpdates()
        },
        capabilityReset: @escaping CapabilityReset = {
            await ProviderRuntimeCapabilityState.reset()
        },
        diagnosticSink: any ProviderRuntimeDiagnosticSink = InputDebugProviderRuntimeDiagnosticSink(),
        requestGate: ProviderRequestGate = .shared
    ) {
        self.revisionLoader = revisionLoader
        self.runtimeLoader = runtimeLoader
        self.revisionUpdates = revisionUpdates
        self.capabilityReset = capabilityReset
        self.diagnosticSink = diagnosticSink
        self.requestGate = requestGate
    }

    deinit {
        observationTask?.cancel()
        activeOperations.values.forEach { $0() }
    }

    public func leaseForEligibleDispatch() async -> ProviderRuntimeLease {
        while true {
            await waitForGenerationTransitionIfNeeded()
            startObservationIfNeeded()
            let diskRevision = await refreshDiskRevisionIfNeeded()
            guard generationTransition == nil else { continue }

            let expectedRevision = max(
                diskRevision ?? 0,
                latestSignaledRevision ?? 0
            )
            if let currentLease,
               currentLease.generation == generation,
               !leasePublicationPending,
               currentLease.provider != nil,
               currentLease.revision >= expectedRevision {
                return currentLease
            }

            guard let loaded = runtimeLoader() else {
                let unavailableRevision = max(
                    expectedRevision,
                    currentLease?.revision ?? 0
                )
                if let currentLease,
                   currentLease.generation == generation,
                   currentLease.revision >= unavailableRevision {
                    return currentLease
                }
                if currentLease == nil, generation == 0 {
                    return installUnavailableLease(revision: unavailableRevision)
                }
                if currentLease == nil || currentLease?.generation == generation {
                    let transition = await advanceGeneration(
                        revision: unavailableRevision,
                        fingerprint: Self.unavailableFingerprint,
                        providerConfigured: false
                    )
                    guard isStable(transition) else { continue }
                    continue
                }
                return installUnavailableLease(revision: unavailableRevision)
            }

            let loadedRevision = loaded.revision
            let acceptedRevision = max(
                expectedRevision,
                currentLease?.revision ?? 0
            )
            guard loadedRevision >= acceptedRevision else {
                return installUnavailableLease(revision: acceptedRevision)
            }
            rememberRevision(loadedRevision)

            if let currentLease,
               currentLease.generation == generation {
                if leasePublicationPending {
                    if loadedRevision > currentLease.revision {
                        let transition = await advanceGeneration(
                            revision: loadedRevision,
                            fingerprint: loaded.fingerprint,
                            providerConfigured: loaded.provider != nil
                        )
                        guard isStable(transition) else { continue }
                        continue
                    }
                    guard loadedRevision == currentLease.revision,
                          currentLease.fingerprint == Self.unavailableFingerprint
                            || currentLease.fingerprint == loaded.fingerprint else {
                        return currentLease
                    }
                    return publishLoadedLease(loaded)
                }

                let providerPresenceChanged = (currentLease.provider == nil) != (loaded.provider == nil)
                let sourceChanged = currentLease.revision != loadedRevision
                    || currentLease.fingerprint != loaded.fingerprint
                    || providerPresenceChanged
                guard sourceChanged else { return currentLease }
            }

            let transition = await advanceGeneration(
                revision: loadedRevision,
                fingerprint: loaded.fingerprint,
                providerConfigured: loaded.provider != nil
            )
            guard isStable(transition) else { continue }
        }
    }

    public func perform<T: Sendable>(
        using lease: ProviderRuntimeLease,
        operation: @escaping @Sendable (any LLMProvider) async throws -> T
    ) async throws -> T {
        await waitForGenerationTransitionIfNeeded()
        guard isCurrent(lease), let provider = lease.provider else {
            throw lease.provider == nil
                ? ProviderRuntimeRegistryError.providerUnavailable
                : ProviderRuntimeRegistryError.staleGeneration
        }
        let operationID = UUID()
        let task = Task<T, Error> {
            try await operation(provider)
        }
        activeOperations[operationID] = { task.cancel() }
        let value: T
        do {
            value = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch {
            activeOperations[operationID] = nil
            await refreshDiskRevisionIfNeeded()
            await waitForGenerationTransitionIfNeeded()
            if !isCurrent(lease) {
                diagnosticSink.record(event(.staleResultDropped, lease: lease))
                throw ProviderRuntimeRegistryError.staleGeneration
            }
            throw error
        }
        activeOperations[operationID] = nil
        await refreshDiskRevisionIfNeeded()
        await waitForGenerationTransitionIfNeeded()
        guard isCurrent(lease) else {
            diagnosticSink.record(event(.staleResultDropped, lease: lease))
            throw ProviderRuntimeRegistryError.staleGeneration
        }
        return value
    }

    public func commitIfCurrent<T: Sendable>(
        using lease: ProviderRuntimeLease,
        operation: @Sendable () throws -> T
    ) async throws -> T {
        await waitForGenerationTransitionIfNeeded()
        await refreshDiskRevisionIfNeeded()
        await waitForGenerationTransitionIfNeeded()
        guard isCurrent(lease) else {
            diagnosticSink.record(event(.staleResultDropped, lease: lease))
            throw ProviderRuntimeRegistryError.staleGeneration
        }
        return try operation()
    }

    public func currentGeneration() -> UInt64 {
        generation
    }

    func setGenerationTransitionWaitObserverForTesting(
        _ observer: (@Sendable () -> Void)?
    ) {
        generationTransitionWaitObserver = observer
    }

    func setRevisionObservationObserverForTesting(
        _ observer: (@Sendable (UInt64) -> Void)?
    ) {
        revisionObservationObserver = observer
    }

    private func startObservationIfNeeded() {
        guard observationTask == nil else {
            return
        }
        let updates = revisionUpdates()
        observationTask = Task { [weak self] in
            for await revision in updates {
                guard let self else {
                    return
                }
                await self.providerRevisionDidChange(revision)
            }
        }
    }

    private func providerRevisionDidChange(_ revision: UInt64) async {
        revisionObservationObserver?(revision)
        let knownRevision = highestKnownRevision()
        guard revision > knownRevision else {
            return
        }
        rememberRevision(revision)
        _ = await advanceGeneration(
            revision: revision,
            fingerprint: Self.unavailableFingerprint,
            providerConfigured: false
        )
    }

    @discardableResult
    private func refreshDiskRevisionIfNeeded() async -> UInt64? {
        await waitForGenerationTransitionIfNeeded()
        guard let diskRevision = revisionLoader() else {
            return nil
        }
        guard diskRevision > highestKnownRevision() else {
            return diskRevision
        }
        rememberRevision(diskRevision)
        let transition = await advanceGeneration(
            revision: diskRevision,
            fingerprint: Self.unavailableFingerprint,
            providerConfigured: false
        )
        if !isStable(transition) {
            await waitForGenerationTransitionIfNeeded()
        }
        return highestKnownRevision(atLeast: diskRevision)
    }

    private func advanceGeneration(
        revision: UInt64,
        fingerprint: String,
        providerConfigured: Bool
    ) async -> GenerationTransitionResult? {
        rememberRevision(revision)
        if let transition = generationTransition {
            mergeGenerationTransition(
                revision: revision,
                fingerprint: fingerprint,
                providerConfigured: providerConfigured
            )
            await waitForGenerationTransition(transition.id)
            return GenerationTransitionResult(
                id: lastCompletedGenerationTransitionID ?? transition.id,
                generation: generation,
                revision: highestKnownRevision(atLeast: transition.revision)
            )
        }

        let oldGeneration = generation
        let newGeneration = oldGeneration &+ 1
        var transitionID = UUID()
        generationTransition = GenerationTransition(
            id: transitionID,
            newGeneration: newGeneration,
            revision: revision,
            fingerprint: fingerprint,
            providerConfigured: providerConfigured,
            pendingTarget: nil
        )

        while true {
            guard let activeTransition = generationTransition,
                  activeTransition.id == transitionID else { return nil }
            if let currentLease {
                await requestGate.invalidate(
                    providerIdentity: currentLease.fingerprint,
                    expectedGeneration: generation,
                    newGeneration: activeTransition.newGeneration
                )
            }
            guard generationTransition?.id == transitionID else { return nil }
            generation = activeTransition.newGeneration
            await capabilityReset()
            guard let completedTransition = generationTransition,
                  completedTransition.id == transitionID else { return nil }

            let lease = ProviderRuntimeLease(
                revision: completedTransition.revision,
                generation: completedTransition.newGeneration,
                fingerprint: completedTransition.fingerprint,
                provider: nil
            )
            currentLease = lease
            leasePublicationPending = true
            rememberRevision(lease.revision)
            diagnosticSink.record(
                ProviderRuntimeDiagnosticEvent(
                    stage: .generationChanged,
                    revision: completedTransition.revision,
                    generation: completedTransition.newGeneration,
                    fingerprint: completedTransition.fingerprint,
                    providerConfigured: completedTransition.providerConfigured
                )
            )

            guard let pendingTarget = completedTransition.pendingTarget else {
                completeGenerationTransition(transitionID)
                return GenerationTransitionResult(
                    id: transitionID,
                    generation: lease.generation,
                    revision: lease.revision
                )
            }

            let nextTransitionID = UUID()
            let nextGeneration = lease.generation &+ 1
            generationTransition = GenerationTransition(
                id: nextTransitionID,
                newGeneration: nextGeneration,
                revision: pendingTarget.revision,
                fingerprint: pendingTarget.fingerprint,
                providerConfigured: pendingTarget.providerConfigured,
                pendingTarget: nil,
                waiters: completedTransition.waiters
            )
            transitionID = nextTransitionID
        }
    }

    private func mergeGenerationTransition(
        revision: UInt64,
        fingerprint: String,
        providerConfigured: Bool
    ) {
        guard var transition = generationTransition,
              revision >= transition.revision else { return }
        if revision == transition.revision {
            guard transition.fingerprint == Self.unavailableFingerprint,
                  fingerprint != Self.unavailableFingerprint else {
                return
            }
            transition.fingerprint = fingerprint
            transition.providerConfigured = providerConfigured
            generationTransition = transition
            return
        }

        let target = GenerationTransitionTarget(
            revision: revision,
            fingerprint: fingerprint,
            providerConfigured: providerConfigured
        )
        if let pendingTarget = transition.pendingTarget,
           pendingTarget.revision >= revision {
            guard pendingTarget.revision == revision,
                  pendingTarget.fingerprint == Self.unavailableFingerprint,
                  fingerprint != Self.unavailableFingerprint else {
                return
            }
            transition.pendingTarget = target
        } else {
            transition.pendingTarget = target
        }
        generationTransition = transition
    }

    private func waitForGenerationTransitionIfNeeded() async {
        while let transitionID = generationTransition?.id {
            await waitForGenerationTransition(transitionID)
        }
    }

    private func waitForGenerationTransition(_ transitionID: UUID) async {
        generationTransitionWaitObserver?()
        await withCheckedContinuation { continuation in
            guard var transition = generationTransition,
                  transition.id == transitionID else {
                continuation.resume()
                return
            }
            transition.waiters.append(continuation)
            generationTransition = transition
        }
    }

    private func completeGenerationTransition(_ transitionID: UUID) {
        guard let transition = generationTransition,
              transition.id == transitionID else { return }
        lastCompletedGenerationTransitionID = transitionID
        generationTransition = nil
        transition.waiters.forEach { $0.resume() }
    }

    private func installUnavailableLease(revision: UInt64) -> ProviderRuntimeLease {
        if generation == 0 {
            generation = 1
        }
        let acceptedRevision = highestKnownRevision(atLeast: revision)
        if let currentLease,
           currentLease.generation == generation,
           currentLease.provider == nil,
           currentLease.revision >= acceptedRevision {
            return currentLease
        }
        let lease = ProviderRuntimeLease(
            revision: acceptedRevision,
            generation: generation,
            fingerprint: Self.unavailableFingerprint,
            provider: nil
        )
        currentLease = lease
        leasePublicationPending = false
        rememberRevision(lease.revision)
        return lease
    }

    private func publishLoadedLease(
        _ loaded: ProviderRuntimeLoadResult
    ) -> ProviderRuntimeLease {
        let lease = ProviderRuntimeLease(
            revision: loaded.revision,
            generation: generation,
            fingerprint: loaded.fingerprint,
            provider: loaded.provider
        )
        currentLease = lease
        leasePublicationPending = false
        rememberRevision(lease.revision)
        diagnosticSink.record(event(.loaded, lease: lease))
        return lease
    }

    private func highestKnownRevision(atLeast revision: UInt64 = 0) -> UInt64 {
        max(
            revision,
            latestSignaledRevision ?? 0,
            currentLease?.revision ?? 0
        )
    }

    private func rememberRevision(_ revision: UInt64) {
        latestSignaledRevision = max(latestSignaledRevision ?? 0, revision)
    }

    private func isStable(_ transition: GenerationTransitionResult?) -> Bool {
        guard let transition else { return false }
        return lastCompletedGenerationTransitionID == transition.id
            && generationTransition == nil
            && generation == transition.generation
            && currentLease?.generation == transition.generation
            && currentLease?.revision == transition.revision
            && highestKnownRevision() == transition.revision
    }

    private func isCurrent(_ lease: ProviderRuntimeLease) -> Bool {
        generationTransition == nil
            && generation == lease.generation
            && currentLease?.generation == lease.generation
            && currentLease?.revision == lease.revision
            && currentLease?.fingerprint == lease.fingerprint
            && (currentLease?.provider != nil) == (lease.provider != nil)
            && highestKnownRevision() == lease.revision
    }

    private func event(
        _ stage: ProviderRuntimeDiagnosticStage,
        lease: ProviderRuntimeLease
    ) -> ProviderRuntimeDiagnosticEvent {
        ProviderRuntimeDiagnosticEvent(
            stage: stage,
            revision: lease.revision,
            generation: lease.generation,
            fingerprint: lease.fingerprint,
            providerConfigured: lease.provider != nil
        )
    }
}
