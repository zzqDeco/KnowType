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

    private let revisionLoader: RevisionLoader
    private let runtimeLoader: RuntimeLoader
    private let revisionUpdates: RevisionUpdates
    private let capabilityReset: CapabilityReset
    private let diagnosticSink: any ProviderRuntimeDiagnosticSink
    public nonisolated let requestGate: ProviderRequestGate
    private var currentLease: ProviderRuntimeLease?
    private var generation: UInt64 = 0
    private var latestSignaledRevision: UInt64?
    private var observationTask: Task<Void, Never>?
    private var activeOperations: [UUID: @Sendable () -> Void] = [:]

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
        startObservationIfNeeded()
        let diskRevision = await refreshDiskRevisionIfNeeded()
        let expectedRevision = diskRevision ?? latestSignaledRevision

        if let currentLease,
           currentLease.generation == generation,
           currentLease.provider != nil,
           expectedRevision == nil || expectedRevision == currentLease.revision {
            return currentLease
        }

        guard let loaded = runtimeLoader() else {
            if let currentLease,
               currentLease.generation == generation,
               expectedRevision == nil || expectedRevision == currentLease.revision {
                return currentLease
            }
            if let currentLease, currentLease.generation == generation {
                await advanceGeneration(
                    revision: expectedRevision ?? currentLease.revision,
                    fingerprint: String(repeating: "0", count: 64),
                    providerConfigured: false
                )
            }
            return installUnavailableLease(revision: diskRevision ?? expectedRevision ?? 0)
        }

        let providerPresenceChanged = (currentLease?.provider == nil) != (loaded.provider == nil)
        let sourceChanged = currentLease.map {
            $0.revision != loaded.revision || $0.fingerprint != loaded.fingerprint || providerPresenceChanged
        } ?? true
        if sourceChanged,
           currentLease?.generation == generation || currentLease == nil {
            await advanceGeneration(
                revision: loaded.revision,
                fingerprint: loaded.fingerprint,
                providerConfigured: loaded.provider != nil
            )
        }
        if let latestSignaledRevision, latestSignaledRevision > loaded.revision {
            return installUnavailableLease(revision: latestSignaledRevision)
        }
        let lease = ProviderRuntimeLease(
            revision: loaded.revision,
            generation: generation,
            fingerprint: loaded.fingerprint,
            provider: loaded.provider
        )
        currentLease = lease
        latestSignaledRevision = loaded.revision
        diagnosticSink.record(event(.loaded, lease: lease))
        return lease
    }

    public func perform<T: Sendable>(
        using lease: ProviderRuntimeLease,
        operation: @escaping @Sendable (any LLMProvider) async throws -> T
    ) async throws -> T {
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
            if !isCurrent(lease) {
                diagnosticSink.record(event(.staleResultDropped, lease: lease))
                throw ProviderRuntimeRegistryError.staleGeneration
            }
            throw error
        }
        activeOperations[operationID] = nil
        await refreshDiskRevisionIfNeeded()
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
        await refreshDiskRevisionIfNeeded()
        guard isCurrent(lease) else {
            diagnosticSink.record(event(.staleResultDropped, lease: lease))
            throw ProviderRuntimeRegistryError.staleGeneration
        }
        return try operation()
    }

    public func currentGeneration() -> UInt64 {
        generation
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
        let knownRevision = max(latestSignaledRevision ?? 0, currentLease?.revision ?? 0)
        guard revision > knownRevision else {
            return
        }
        latestSignaledRevision = revision
        await advanceGeneration(
            revision: revision,
            fingerprint: String(repeating: "0", count: 64),
            providerConfigured: false
        )
    }

    @discardableResult
    private func refreshDiskRevisionIfNeeded() async -> UInt64? {
        guard let diskRevision = revisionLoader() else {
            return nil
        }
        guard let currentLease,
              currentLease.generation == generation,
              currentLease.revision != diskRevision else {
            return diskRevision
        }
        latestSignaledRevision = max(latestSignaledRevision ?? 0, diskRevision)
        await advanceGeneration(
            revision: diskRevision,
            fingerprint: String(repeating: "0", count: 64),
            providerConfigured: false
        )
        return diskRevision
    }

    private func advanceGeneration(
        revision: UInt64,
        fingerprint: String,
        providerConfigured: Bool
    ) async {
        let oldGeneration = generation
        if let currentLease {
            await requestGate.invalidate(
                providerIdentity: currentLease.fingerprint,
                generation: oldGeneration
            )
        }
        generation &+= 1
        await capabilityReset()
        diagnosticSink.record(
            ProviderRuntimeDiagnosticEvent(
                stage: .generationChanged,
                revision: revision,
                generation: generation,
                fingerprint: fingerprint,
                providerConfigured: providerConfigured
            )
        )
    }

    private func installUnavailableLease(revision: UInt64) -> ProviderRuntimeLease {
        if generation == 0 {
            generation = 1
        }
        let lease = ProviderRuntimeLease(
            revision: revision,
            generation: generation,
            fingerprint: String(repeating: "0", count: 64),
            provider: nil
        )
        currentLease = lease
        return lease
    }

    private func isCurrent(_ lease: ProviderRuntimeLease) -> Bool {
        generation == lease.generation
            && currentLease?.generation == lease.generation
            && currentLease?.revision == lease.revision
            && currentLease?.fingerprint == lease.fingerprint
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
