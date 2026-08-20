import CryptoKit
import Foundation
import KnowTypeCore
import KnowTypeProviders

actor AIContextMemoryRuntimeTestProbe {
    private let pausesBeforeGuardedCommit: Bool
    private let pausesAfterGateWaiterInstall: Bool
    private let pausesBeforeClaimRecoveryGatePreflight: Bool
    private var guardedCommitReleased = false
    private var gateWaiterReleased = false
    private var claimRecoveryGatePreflightReleased = false
    private var guardedCommitContinuation: CheckedContinuation<Void, Never>?
    private var gateWaiterContinuation: CheckedContinuation<Void, Never>?
    private var claimRecoveryGatePreflightContinuation: CheckedContinuation<Void, Never>?
    private(set) var guardedCommitPauseCount = 0
    private(set) var gateWaiterPauseCount = 0
    private(set) var claimRecoveryAttemptCount = 0
    private(set) var claimRecoveryClaimLoadCount = 0
    private(set) var claimRecoveryGatePreflightPauseCount = 0
    private(set) var claimRecoveryRetryScheduleCount = 0

    init(
        pausesBeforeGuardedCommit: Bool = false,
        pausesAfterGateWaiterInstall: Bool = false,
        pausesBeforeClaimRecoveryGatePreflight: Bool = false
    ) {
        self.pausesBeforeGuardedCommit = pausesBeforeGuardedCommit
        self.pausesAfterGateWaiterInstall = pausesAfterGateWaiterInstall
        self.pausesBeforeClaimRecoveryGatePreflight = pausesBeforeClaimRecoveryGatePreflight
    }

    func pauseBeforeGuardedCommitIfNeeded() async {
        guardedCommitPauseCount += 1
        guard pausesBeforeGuardedCommit, !guardedCommitReleased else { return }
        await withCheckedContinuation { continuation in
            guardedCommitContinuation = continuation
        }
    }

    func releaseGuardedCommit() {
        guardedCommitReleased = true
        guardedCommitContinuation?.resume()
        guardedCommitContinuation = nil
    }

    func pauseAfterGateWaiterInstallIfNeeded() async {
        gateWaiterPauseCount += 1
        guard pausesAfterGateWaiterInstall, !gateWaiterReleased else { return }
        await withCheckedContinuation { continuation in
            gateWaiterContinuation = continuation
        }
    }

    func releaseGateWaiterInstall() {
        gateWaiterReleased = true
        gateWaiterContinuation?.resume()
        gateWaiterContinuation = nil
    }

    func recordClaimRecoveryClaimLoad() {
        claimRecoveryClaimLoadCount += 1
    }

    func pauseBeforeClaimRecoveryGatePreflightIfNeeded() async {
        claimRecoveryGatePreflightPauseCount += 1
        guard pausesBeforeClaimRecoveryGatePreflight,
              !claimRecoveryGatePreflightReleased else { return }
        await withCheckedContinuation { continuation in
            claimRecoveryGatePreflightContinuation = continuation
        }
    }

    func releaseClaimRecoveryGatePreflight() {
        claimRecoveryGatePreflightReleased = true
        claimRecoveryGatePreflightContinuation?.resume()
        claimRecoveryGatePreflightContinuation = nil
    }

    func recordClaimRecoveryAttempt() {
        claimRecoveryAttemptCount += 1
    }

    func recordClaimRecoveryRetrySchedule() {
        claimRecoveryRetryScheduleCount += 1
    }
}

public actor LazyDefaultAIContextMemoryRuntime: AIContextEventRecording {
    private let providerLoader: @Sendable () -> (any LLMProvider)?
    private let runtimeFactory: @Sendable (any LLMProvider) -> AIContextMemoryRuntime
    private var runtime: AIContextMemoryRuntime?

    public init(
        providerLoader: @escaping @Sendable () -> (any LLMProvider)? = {
            ProviderRuntimeLoader.loadDefaultProvider(createProfileDirectory: false)
        },
        runtimeFactory: @escaping @Sendable (any LLMProvider) -> AIContextMemoryRuntime = {
            AIContextMemoryRuntime(provider: $0)
        }
    ) {
        self.providerLoader = providerLoader
        self.runtimeFactory = runtimeFactory
    }

    public func record(_ event: AITypingEvent) async {
        if let runtime {
            await runtime.record(event)
            return
        }
        guard let provider = providerLoader() else { return }
        let runtime = runtimeFactory(provider)
        self.runtime = runtime
        await runtime.record(event)
    }
}

public actor AIContextMemoryRuntime: AIContextEventRecording {
    private static let maximumScheduleInterval: TimeInterval = 24 * 60 * 60
    private static let defaultClaimRecoveryBackoff: TimeInterval = 60
    private static let maximumClaimRecoveryBackoff: TimeInterval = 15 * 60

    private struct GateWaitKey: Equatable {
        var identity: String
        var generation: UInt64
    }

    private enum DigestClaimRecovery: Sendable {
        case none
        case recovered
        case blocked
        case gatePersistenceBlocked
        case superseded
    }

    private struct DigestClaimRecoveryFlight {
        let token: UUID
        var waiters: [CheckedContinuation<DigestClaimRecovery, Never>] = []
    }

    private let provider: (any LLMProvider)?
    private let providerRegistry: ProviderRuntimeRegistry?
    private let eventStore: TypingEventStore
    private let environmentStore: EnvironmentDocumentStore
    private let batchSize: Int
    private let minimumInterval: TimeInterval
    private let diagnosticSink: @Sendable ([InputDebugDiagnostics.Field]) -> Void
    private let requestGate: ProviderRequestGate
    private let nowProvider: @Sendable () -> Date
    private let hardTimeoutNanoseconds: UInt64
    private let testProbe: AIContextMemoryRuntimeTestProbe?
    private let claimRecoveryBackoff: TimeInterval
    private let claimRecoverySleeper: (@Sendable (UInt64) async -> Void)?
    private var providerIdentity = "context-digest"
    private var lastDigestAt: Date?
    private var pendingSince: Date?
    private var nextEligibleAt: Date?
    private var scheduleStateLoaded = false
    private var scheduleStateBlocked = false
    private var lastDigestFailureAt: Date?
    private var deferredDiagnosticFailureAt: Date?
    private var digestInFlight = false
    private var digestRerunRequested = false
    private var digestRerunScheduled = false
    private var activeDigestClaimRawData: Data?
    private var persistedClaimNeedsRecovery = true
    private var providerGeneration: UInt64?
    private var deadlineTask: Task<Void, Never>?
    private var gateWaitKey: GateWaitKey?
    private var claimRecoveryRetryAt: Date?
    private var claimRecoveryBlockedCount = 0
    private var gatePersistenceBlocked = false
    private var digestClaimRecoveryFlight: DigestClaimRecoveryFlight?

    public init(
        provider: (any LLMProvider)?,
        eventStore: TypingEventStore = TypingEventStore(),
        environmentStore: EnvironmentDocumentStore = EnvironmentDocumentStore(),
        batchSize: Int = 50,
        minimumInterval: TimeInterval = 600,
        requestGate: ProviderRequestGate = .shared,
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        providerIdentity: String? = nil
    ) {
        self.provider = provider
        self.providerRegistry = nil
        self.eventStore = eventStore
        self.environmentStore = environmentStore
        self.batchSize = max(1, batchSize)
        self.minimumInterval = Self.boundedMinimumInterval(minimumInterval)
        self.requestGate = requestGate
        self.nowProvider = nowProvider
        self.hardTimeoutNanoseconds = UInt64(AIRecommendationRuntime.Defaults.hardTimeoutMilliseconds) * 1_000_000
        self.testProbe = nil
        self.claimRecoveryBackoff = Self.defaultClaimRecoveryBackoff
        self.claimRecoverySleeper = nil
        self.providerIdentity = providerIdentity ?? provider?.providerName ?? "context-digest"
        self.diagnosticSink = { InputDebugDiagnostics.emit(category: .ai, fields: $0) }
    }

    init(
        provider: (any LLMProvider)?,
        eventStore: TypingEventStore,
        environmentStore: EnvironmentDocumentStore,
        batchSize: Int,
        minimumInterval: TimeInterval,
        hardTimeoutMilliseconds: Int = AIRecommendationRuntime.Defaults.hardTimeoutMilliseconds,
        diagnosticSink: @escaping @Sendable ([InputDebugDiagnostics.Field]) -> Void,
        requestGate: ProviderRequestGate = .shared,
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        testProbe: AIContextMemoryRuntimeTestProbe? = nil,
        claimRecoveryBackoff: TimeInterval = 60,
        claimRecoverySleeper: (@Sendable (UInt64) async -> Void)? = nil
    ) {
        self.provider = provider
        self.providerRegistry = nil
        self.eventStore = eventStore
        self.environmentStore = environmentStore
        self.batchSize = max(1, batchSize)
        self.minimumInterval = Self.boundedMinimumInterval(minimumInterval)
        self.requestGate = requestGate
        self.nowProvider = nowProvider
        self.hardTimeoutNanoseconds = UInt64(max(1, hardTimeoutMilliseconds)) * 1_000_000
        self.testProbe = testProbe
        self.claimRecoveryBackoff = Self.boundedClaimRecoveryBackoff(claimRecoveryBackoff)
        self.claimRecoverySleeper = claimRecoverySleeper
        self.providerIdentity = provider?.providerName ?? "context-digest"
        self.diagnosticSink = diagnosticSink
    }

    public init(
        providerRegistry: ProviderRuntimeRegistry,
        eventStore: TypingEventStore = TypingEventStore(),
        environmentStore: EnvironmentDocumentStore = EnvironmentDocumentStore(),
        batchSize: Int = 50,
        minimumInterval: TimeInterval = 600,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.provider = nil
        self.providerRegistry = providerRegistry
        self.eventStore = eventStore
        self.environmentStore = environmentStore
        self.batchSize = max(1, batchSize)
        self.minimumInterval = Self.boundedMinimumInterval(minimumInterval)
        self.requestGate = providerRegistry.requestGate
        self.nowProvider = nowProvider
        self.hardTimeoutNanoseconds = UInt64(AIRecommendationRuntime.Defaults.hardTimeoutMilliseconds) * 1_000_000
        self.testProbe = nil
        self.claimRecoveryBackoff = Self.defaultClaimRecoveryBackoff
        self.claimRecoverySleeper = nil
        self.diagnosticSink = { InputDebugDiagnostics.emit(category: .ai, fields: $0) }
    }

    func claimRecoveryWaiterCountForTesting() -> Int {
        digestClaimRecoveryFlight?.waiters.count ?? 0
    }

    init(
        providerRegistry: ProviderRuntimeRegistry,
        eventStore: TypingEventStore,
        environmentStore: EnvironmentDocumentStore,
        batchSize: Int,
        minimumInterval: TimeInterval,
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        testProbe: AIContextMemoryRuntimeTestProbe
    ) {
        self.provider = nil
        self.providerRegistry = providerRegistry
        self.eventStore = eventStore
        self.environmentStore = environmentStore
        self.batchSize = max(1, batchSize)
        self.minimumInterval = Self.boundedMinimumInterval(minimumInterval)
        self.requestGate = providerRegistry.requestGate
        self.nowProvider = nowProvider
        self.hardTimeoutNanoseconds = UInt64(AIRecommendationRuntime.Defaults.hardTimeoutMilliseconds) * 1_000_000
        self.testProbe = testProbe
        self.claimRecoveryBackoff = Self.defaultClaimRecoveryBackoff
        self.claimRecoverySleeper = nil
        self.diagnosticSink = { InputDebugDiagnostics.emit(category: .ai, fields: $0) }
    }

    public func record(_ event: AITypingEvent) async {
        guard !gatePersistenceBlocked, claimRecoveryRetryAt == nil else { return }
        if digestInFlight { digestRerunRequested = true }
        guard await preparePersistedClaimForRecord(now: nowProvider()) else { return }
        let lease: ProviderRuntimeLease?
        if let providerRegistry {
            let loaded = await providerRegistry.leaseForEligibleDispatch()
            guard loaded.provider != nil else { return }
            applyProviderLease(loaded)
            lease = loaded
        } else {
            lease = nil
        }
        do {
            let result = try eventStore.appendBounded(
                sanitized(event),
                preservingClaimedPrefix: activeDigestClaimRawData
            )
            emitAppendDiagnostics(result)
            await processIfNeeded(now: nowProvider(), dispatchLease: lease)
        } catch {
            return
        }
    }

    public func processIfNeeded(now: Date = Date()) async {
        await processIfNeeded(now: now, dispatchLease: nil)
    }

    private func processIfNeeded(now: Date, dispatchLease: ProviderRuntimeLease?) async {
        guard provider != nil || providerRegistry != nil else { return }
        guard !gatePersistenceBlocked, claimRecoveryRetryAt == nil else { return }
        if digestInFlight {
            digestRerunRequested = true
            if persistedClaimNeedsRecovery, digestClaimRecoveryFlight != nil {
                _ = await attemptDigestClaimRecovery(now: now)
            }
            return
        }
        guard gateWaitKey == nil, !digestRerunScheduled else { return }
        digestInFlight = true
        defer {
            activeDigestClaimRawData = nil
            digestInFlight = false
            if digestRerunRequested {
                digestRerunRequested = false
                if !gatePersistenceBlocked,
                   claimRecoveryRetryAt == nil,
                   (gateWaitKey == nil || deadlineTask == nil) {
                    scheduleCoalescedRerun()
                }
            }
        }

        loadScheduleStateIfNeeded(now: now)
        guard !scheduleStateBlocked else { return }

        if persistedClaimNeedsRecovery {
            switch await attemptDigestClaimRecovery(now: now) {
            case .recovered:
                return
            case .blocked, .gatePersistenceBlocked, .superseded:
                return
            case .none:
                break
            }
        }

        let inventory: TypingEventInventory
        do { inventory = try eventStore.inventory() } catch { return }
        guard inventory.eventCount > 0 else {
            pendingSince = nil
            nextEligibleAt = nil
            try? persistScheduleState()
            cancelDeadline()
            return
        }

        if inventory.isProtectedOnly {
            do {
                let snapshot = try eventStore.pendingFullSnapshot()
                try eventStore.archivePendingEvents(matching: snapshot)
                try scheduleAfterLocalArchive(now: now)
            } catch { return }
            return
        }

        let intervalElapsed: Bool
        let deferredDeadline: Date
        if let nextEligibleAt, nextEligibleAt > now {
            intervalElapsed = false
            deferredDeadline = nextEligibleAt
        } else if let lastDigestAt {
            intervalElapsed = now.timeIntervalSince(lastDigestAt) >= minimumInterval
            deferredDeadline = nextEligibleAt ?? lastDigestAt.addingTimeInterval(minimumInterval)
        } else {
            if inventory.eventCount >= batchSize {
                intervalElapsed = true
                deferredDeadline = now
            } else {
                if pendingSince == nil {
                    pendingSince = now
                    guard (try? persistScheduleState()) != nil else { return }
                }
                deferredDeadline = pendingSince!.addingTimeInterval(minimumInterval)
                intervalElapsed = now >= deferredDeadline
            }
        }
        guard intervalElapsed else {
            scheduleDeadline(at: deferredDeadline)
            emitDiagnostic(
                stage: "context_digest_deferred",
                fields: [
                    .init(.eventCount, inventory.eventCount),
                    .init(.byteCount, inventory.byteCount),
                    .init(.deadline, Int(ceil(deferredDeadline.timeIntervalSince(now))))
                ]
            )
            return
        }

        let lease: ProviderRuntimeLease?
        let activeProvider: (any LLMProvider)?
        if let providerRegistry {
            let loaded = dispatchLease ?? await providerRegistry.leaseForEligibleDispatch()
            guard let provider = loaded.provider else { return }
            applyProviderLease(loaded)
            lease = loaded
            activeProvider = provider
        } else {
            lease = nil
            activeProvider = provider
        }
        guard let activeProvider else { return }

        let gatePreflight = await requestGate.preflight(
            providerIdentity: providerIdentity,
            generation: providerGeneration ?? 0
        )
        let gateCooldown: Date?
        switch gatePreflight {
        case .available, .busy:
            gateCooldown = nil
        case .cooldown(let deadline, _):
            gateCooldown = deadline
        case .staleGeneration:
            invalidateProviderRuntimeState()
            return
        case .persistenceBlocked:
            latchGatePersistenceBlocked()
            return
        }
        let localCooldown = digestCooldownRemaining(at: now)
        if let deadline = [localCooldown.map { now.addingTimeInterval($0) }, gateCooldown].compactMap({ $0 }).max(), deadline > now {
            scheduleDeadline(at: deadline)
            emitDeferredDiagnostic(inventory: inventory, cooldownRemaining: deadline.timeIntervalSince(now))
            return
        }

        let snapshot: TypingEventSnapshot
        do { snapshot = try eventStore.pendingDigestSnapshot() } catch { return }
        guard !snapshot.rawData.isEmpty else { return }
        guard snapshot.claimedEventCount > 0, !snapshot.events.isEmpty else {
            do {
                try eventStore.archivePendingEvents(matching: snapshot)
                try scheduleAfterLocalArchive(now: now)
            } catch { return }
            return
        }
        if snapshot.events.allSatisfy(TypingEventStore.isProtectedOnlyEvent) {
            do {
                try eventStore.archivePendingEvents(matching: snapshot)
                try scheduleAfterLocalArchive(now: now)
            } catch { return }
            return
        }
        guard !snapshot.requestContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            do {
                try eventStore.archivePendingEvents(matching: snapshot)
                try scheduleAfterLocalArchive(now: now)
            } catch { return }
            return
        }

        var providerGateStarted = false
        var providerGateCompleted = false
        let requestIdentity = providerIdentity
        let requestGeneration = providerGeneration ?? 0
        do {
            let currentEnvironment = try environmentStore.loadSnapshot()
            let request = LLMRequest(
                task: .contextDigest,
                rawInput: snapshot.requestContent,
                locale: .mixed,
                appContext: "KnowTypeContextMemory",
                maxCandidates: 1,
                contextDocuments: ["ENV.md": currentEnvironment.content]
            )
            try ProviderRequestBudget.validate(request)
            activeDigestClaimRawData = snapshot.rawData
            let registry = providerRegistry
            providerGateStarted = true
            let gated: (LLMResponse, String) = try await requestGate.executeWithHardTimeout(
                providerIdentity: requestIdentity,
                generation: requestGeneration,
                timeoutNanoseconds: hardTimeoutNanoseconds
            ) {
                let response: LLMResponse
                if let registry, let lease {
                    response = try await registry.perform(using: lease) { provider in
                        try await provider.complete(request)
                    }
                } else {
                    response = try await activeProvider.complete(request)
                }
                guard response.candidates.count == 1,
                      let candidate = response.candidates.first?.text else {
                    throw EnvironmentDocumentError.invalidDigestCandidate
                }
                try EnvironmentDocumentStore.validateGeneratedMarkdown(candidate)
                return (response, candidate)
            }
            _ = gated.0
            providerGateCompleted = true
            await testProbe?.pauseBeforeGuardedCommitIfNeeded()
            let generated = gated.1
            let claim = EnvironmentDigestClaim(
                claimedPrefixSHA256: Self.sha256(snapshot.rawData),
                claimedPrefixByteCount: snapshot.rawData.count,
                claimedEventCount: snapshot.claimedEventCount,
                generatedSHA256: AIDocumentSnapshot.hash(
                    generated.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                providerGeneration: requestGeneration
            )
            let persistAfterClaim: @Sendable () throws -> TypingEventArchiveResult = {
                _ = try environmentStore.replaceGeneratedSection(with: generated)
                let result = try eventStore.commitPendingEvents(matching: snapshot, beforeArchive: {})
                guard eventStore.hasProcessedArchive(
                    prefixSHA256: Self.sha256(snapshot.rawData),
                    byteCount: snapshot.rawData.count
                ) else {
                    throw TypingEventStoreError.pendingContentChanged
                }
                try environmentStore.saveDigestArchiveReceipt(
                    EnvironmentDigestArchiveReceipt(
                        claimedPrefixSHA256: Self.sha256(snapshot.rawData),
                        claimedPrefixByteCount: snapshot.rawData.count,
                        claimedEventCount: snapshot.claimedEventCount,
                        generatedSHA256: claim.generatedSHA256,
                        archivedByteCount: snapshot.rawData.count
                    )
                )
                let tailCount = try eventStore.inventory().eventCount
                try environmentStore.saveDigestScheduleState(
                    EnvironmentDigestScheduleState(
                        pendingSince: nil,
                        lastSuccessfulDigestAt: now,
                        nextEligibleAt: tailCount > 0 ? now.addingTimeInterval(minimumInterval) : nil,
                        pendingEventCount: tailCount
                    )
                )
                return result
            }
            let result: TypingEventArchiveResult
            if let providerRegistry, let lease {
                persistedClaimNeedsRecovery = true
                result = try await providerRegistry.commitIfCurrent(using: lease) {
                    try environmentStore.saveDigestClaim(claim)
                    return try persistAfterClaim()
                }
            } else {
                try environmentStore.saveDigestClaim(claim)
                persistedClaimNeedsRecovery = true
                result = try persistAfterClaim()
            }
            try environmentStore.clearDigestClaim()
            persistedClaimNeedsRecovery = false
            try? environmentStore.clearDigestArchiveReceipt()
            recordDigestSuccess(at: now)
            emitArchiveDiagnostic(result)
        } catch ProviderRequestBudgetError {
            scheduleDeadline(at: now.addingTimeInterval(minimumInterval))
        } catch ProviderRuntimeRegistryError.staleGeneration {
            invalidateProviderRuntimeState()
        } catch ProviderRequestGateError.staleGeneration {
            invalidateProviderRuntimeState()
        } catch ProviderRequestGateError.cooldown(let deadline, _) {
            scheduleDeadline(at: deadline)
        } catch ProviderRequestGateError.busy {
            scheduleGateAvailabilityWake()
            await testProbe?.pauseAfterGateWaiterInstallIfNeeded()
            return
        } catch ProviderRequestGatePersistenceError.blocked {
            latchGatePersistenceBlocked()
            return
        } catch TypingEventStoreError.pendingContentChanged {
            return
        } catch EnvironmentDocumentError.invalidDigestCandidate {
            markDigestFailure(at: now)
        } catch is TimeoutError {
            markDigestFailure(at: now)
        } catch {
            if error is CancellationError { return }
            markDigestFailure(at: now)
            if providerGateCompleted {
                await requestGate.recordLocalCommitFailure(
                    providerIdentity: requestIdentity,
                    generation: requestGeneration
                )
            } else if !providerGateStarted {
                await requestGate.recordLocalCommitFailure(
                    providerIdentity: requestIdentity,
                    generation: requestGeneration
                )
            }
        }
    }

    private func preparePersistedClaimForRecord(now: Date) async -> Bool {
        guard activeDigestClaimRawData == nil, persistedClaimNeedsRecovery else { return true }
        switch await attemptDigestClaimRecovery(now: now) {
        case .none, .recovered:
            return true
        case .blocked, .gatePersistenceBlocked, .superseded:
            return false
        }
    }

    private func attemptDigestClaimRecovery(now: Date) async -> DigestClaimRecovery {
        if digestClaimRecoveryFlight != nil {
            return await withCheckedContinuation { continuation in
                guard var flight = digestClaimRecoveryFlight else {
                    continuation.resume(returning: .superseded)
                    return
                }
                flight.waiters.append(continuation)
                digestClaimRecoveryFlight = flight
            }
        }

        let token = UUID()
        digestClaimRecoveryFlight = DigestClaimRecoveryFlight(token: token)
        await testProbe?.recordClaimRecoveryAttempt()
        guard isCurrentClaimRecovery(token) else { return .superseded }
        let result = await recoverDigestClaim(now: now, token: token)
        guard isCurrentClaimRecovery(token) else { return .superseded }
        switch result {
        case .none, .recovered:
            persistedClaimNeedsRecovery = false
            clearClaimRecoveryBlock()
        case .blocked:
            await testProbe?.recordClaimRecoveryRetrySchedule()
            guard isCurrentClaimRecovery(token) else { return .superseded }
            persistedClaimNeedsRecovery = true
            scheduleClaimRecoveryRetry(now: now)
        case .gatePersistenceBlocked:
            persistedClaimNeedsRecovery = true
            latchGatePersistenceBlocked()
        case .superseded:
            break
        }
        return completeClaimRecovery(token: token, result: result)
    }

    private func recoverDigestClaim(now: Date, token: UUID) async -> DigestClaimRecovery {
        await testProbe?.recordClaimRecoveryClaimLoad()
        guard isCurrentClaimRecovery(token) else { return .superseded }
        let claim: EnvironmentDigestClaim?
        do {
            claim = try environmentStore.loadDigestClaim()
        } catch {
            return .blocked
        }
        guard let claim else {
            try? environmentStore.clearDigestArchiveReceipt()
            return .none
        }
        await testProbe?.pauseBeforeClaimRecoveryGatePreflightIfNeeded()
        guard isCurrentClaimRecovery(token) else { return .superseded }
        let gatePreflight = await requestGate.persistencePreflight()
        guard isCurrentClaimRecovery(token) else { return .superseded }
        if gatePreflight == .persistenceBlocked {
            return .gatePersistenceBlocked
        }
        do {
            let environment = try environmentStore.loadSnapshot()
            guard EnvironmentDocumentStore.generatedSectionHash(from: environment.content) == claim.generatedSHA256 else {
                return .blocked
            }

            switch eventStore.processedArchiveValidation(
                prefixSHA256: claim.claimedPrefixSHA256,
                byteCount: claim.claimedPrefixByteCount
            ) {
            case .valid:
                switch eventStore.pendingClaimedPrefixValidation(
                    prefixSHA256: claim.claimedPrefixSHA256,
                    byteCount: claim.claimedPrefixByteCount,
                    eventCount: claim.claimedEventCount
                ) {
                case .matching(let snapshot):
                    try eventStore.archivePendingEvents(matching: snapshot)
                case .missing, .notMatching:
                    break
                case .indeterminate:
                    return .blocked
                }
                try persistScheduleState(afterSuccessAt: now)
                try environmentStore.clearDigestClaim()
                try? environmentStore.clearDigestArchiveReceipt()
                recordDigestSuccess(at: now)
                return .recovered
            case .invalid:
                return .blocked
            case .missing:
                break
            }

            let snapshot = try eventStore.pendingDigestSnapshot(
                prefixByteCount: claim.claimedPrefixByteCount,
                eventCount: claim.claimedEventCount
            )
            guard Self.sha256(snapshot.rawData) == claim.claimedPrefixSHA256 else {
                return .blocked
            }
            try eventStore.archivePendingEvents(matching: snapshot)
            guard eventStore.hasProcessedArchive(
                prefixSHA256: claim.claimedPrefixSHA256,
                byteCount: claim.claimedPrefixByteCount
            ) else {
                return .blocked
            }
            try environmentStore.saveDigestArchiveReceipt(
                EnvironmentDigestArchiveReceipt(
                    claimedPrefixSHA256: claim.claimedPrefixSHA256,
                    claimedPrefixByteCount: claim.claimedPrefixByteCount,
                    claimedEventCount: claim.claimedEventCount,
                    generatedSHA256: claim.generatedSHA256,
                    archivedByteCount: claim.claimedPrefixByteCount
                )
            )
            try persistScheduleState(afterSuccessAt: now)
            try environmentStore.clearDigestClaim()
            try? environmentStore.clearDigestArchiveReceipt()
            recordDigestSuccess(at: now)
            return .recovered
        } catch {
            return .blocked
        }
    }

    private func isCurrentClaimRecovery(_ token: UUID) -> Bool {
        digestClaimRecoveryFlight?.token == token
    }

    private func completeClaimRecovery(
        token: UUID,
        result: DigestClaimRecovery
    ) -> DigestClaimRecovery {
        guard let flight = digestClaimRecoveryFlight, flight.token == token else {
            return .superseded
        }
        digestClaimRecoveryFlight = nil
        for continuation in flight.waiters {
            continuation.resume(returning: result)
        }
        return result
    }

    private func invalidateClaimRecoveryFlight() {
        guard let flight = digestClaimRecoveryFlight else { return }
        digestClaimRecoveryFlight = nil
        for continuation in flight.waiters {
            continuation.resume(returning: .superseded)
        }
    }

    private func resetClaimRecoveryState() {
        invalidateClaimRecoveryFlight()
        clearClaimRecoveryBlock()
    }

    private func applyProviderLease(_ lease: ProviderRuntimeLease) {
        let changed = providerGeneration != lease.generation || providerIdentity != lease.fingerprint
        providerGeneration = lease.generation
        providerIdentity = lease.fingerprint
        if changed {
            resetClaimRecoveryState()
            cancelGateAvailabilityWait()
            lastDigestFailureAt = nil
            deferredDiagnosticFailureAt = nil
        }
    }

    private func invalidateProviderRuntimeState() {
        resetClaimRecoveryState()
        cancelGateAvailabilityWait()
        lastDigestFailureAt = nil
        deferredDiagnosticFailureAt = nil
        providerGeneration = nil
        providerIdentity = "context-digest"
    }

    private func recordDigestSuccess(at now: Date) {
        lastDigestAt = now
        pendingSince = nil
        lastDigestFailureAt = nil
        deferredDiagnosticFailureAt = nil
        let hasPendingTail: Bool
        do {
            hasPendingTail = try eventStore.inventory().eventCount > 0
        } catch {
            hasPendingTail = true
        }
        nextEligibleAt = hasPendingTail ? now.addingTimeInterval(minimumInterval) : nil
        try? persistScheduleState()
        if hasPendingTail {
            scheduleDeadline(at: nextEligibleAt!)
        } else {
            cancelDeadline()
        }
    }

    private func markDigestFailure(at now: Date) {
        lastDigestFailureAt = now
        deferredDiagnosticFailureAt = nil
        scheduleDeadline(at: now.addingTimeInterval(60))
    }

    private func digestCooldownRemaining(at now: Date) -> TimeInterval? {
        guard let lastDigestFailureAt else { return nil }
        let remaining = 60 - now.timeIntervalSince(lastDigestFailureAt)
        return remaining > 0 ? remaining : nil
    }

    private func scheduleDeadline(at date: Date) {
        guard !gatePersistenceBlocked, claimRecoveryRetryAt == nil else { return }
        gateWaitKey = nil
        digestRerunScheduled = false
        deadlineTask?.cancel()
        let delay = deadlineNanoseconds(until: date, now: nowProvider())
        deadlineTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            guard !Task.isCancelled, let self else { return }
            await self.processIfNeeded(now: self.nowProvider())
        }
    }

    private func scheduleCoalescedRerun() {
        guard !gatePersistenceBlocked,
              claimRecoveryRetryAt == nil,
              !digestRerunScheduled else { return }
        gateWaitKey = nil
        deadlineTask?.cancel()
        digestRerunScheduled = true
        deadlineTask = Task { [weak self] in
            guard !Task.isCancelled, let self else { return }
            await self.runCoalescedRerun()
        }
    }

    private func runCoalescedRerun() async {
        guard digestRerunScheduled else { return }
        digestRerunScheduled = false
        deadlineTask = nil
        await processIfNeeded(now: nowProvider(), dispatchLease: nil)
    }

    private func scheduleGateAvailabilityWake() {
        guard !gatePersistenceBlocked, claimRecoveryRetryAt == nil else { return }
        let key = GateWaitKey(
            identity: providerIdentity,
            generation: providerGeneration ?? 0
        )
        if gateWaitKey == key, deadlineTask != nil { return }
        deadlineTask?.cancel()
        digestRerunScheduled = false
        gateWaitKey = key
        let gate = requestGate
        deadlineTask = Task { [weak self] in
            await gate.waitForAvailability(
                providerIdentity: key.identity,
                generation: key.generation
            )
            guard !Task.isCancelled, let self else { return }
            await self.gateAvailabilityDidWake(key)
        }
    }

    private func cancelDeadline() {
        guard claimRecoveryRetryAt == nil else { return }
        gateWaitKey = nil
        digestRerunScheduled = false
        deadlineTask?.cancel()
        deadlineTask = nil
    }

    private func cancelGateAvailabilityWait() {
        guard gateWaitKey != nil else { return }
        gateWaitKey = nil
        deadlineTask?.cancel()
        deadlineTask = nil
    }

    private func gateAvailabilityDidWake(_ key: GateWaitKey) async {
        guard gateWaitKey == key else { return }
        gateWaitKey = nil
        deadlineTask = nil
        await processIfNeeded(now: nowProvider())
    }

    private func scheduleClaimRecoveryRetry(now: Date) {
        guard claimRecoveryRetryAt == nil, !gatePersistenceBlocked else { return }
        claimRecoveryBlockedCount = min(500, claimRecoveryBlockedCount + 1)
        let deadline = now.addingTimeInterval(claimRecoveryBackoff)
        claimRecoveryRetryAt = deadline
        gateWaitKey = nil
        digestRerunScheduled = false
        deadlineTask?.cancel()
        let delay = deadlineNanoseconds(until: deadline, now: nowProvider())
        let sleeper = claimRecoverySleeper
        deadlineTask = Task { [weak self] in
            if let sleeper {
                await sleeper(delay)
            } else if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled, let self else { return }
            await self.claimRecoveryDeadlineDidWake(deadline)
        }
        emitDiagnostic(
            stage: "context_claim_recovery_blocked",
            fields: [
                .init(.cooldownRemainingSeconds, Int(ceil(claimRecoveryBackoff))),
                .init(.probeCount, claimRecoveryBlockedCount)
            ]
        )
    }

    private func claimRecoveryDeadlineDidWake(_ deadline: Date) async {
        guard claimRecoveryRetryAt == deadline else { return }
        claimRecoveryRetryAt = nil
        deadlineTask = nil
        await processIfNeeded(now: nowProvider(), dispatchLease: nil)
    }

    private func clearClaimRecoveryBlock() {
        claimRecoveryBlockedCount = 0
        guard claimRecoveryRetryAt != nil else { return }
        claimRecoveryRetryAt = nil
        deadlineTask?.cancel()
        deadlineTask = nil
    }

    private func latchGatePersistenceBlocked() {
        guard !gatePersistenceBlocked else { return }
        gatePersistenceBlocked = true
        gateWaitKey = nil
        digestRerunScheduled = false
        deadlineTask?.cancel()
        deadlineTask = nil
        emitDiagnostic(stage: "context_gate_persistence_blocked", fields: [])
    }

    private func scheduleAfterLocalArchive(now: Date) throws {
        let inventory = try eventStore.inventory()
        guard inventory.eventCount > 0 else {
            pendingSince = nil
            nextEligibleAt = nil
            try persistScheduleState()
            cancelDeadline()
            return
        }

        let deadline: Date
        if let lastDigestAt {
            let eligibleAt = lastDigestAt.addingTimeInterval(minimumInterval)
            nextEligibleAt = eligibleAt
            deadline = max(now, eligibleAt)
        } else if inventory.eventCount >= batchSize {
            pendingSince = pendingSince ?? now
            deadline = now
        } else {
            pendingSince = pendingSince ?? now
            deadline = pendingSince!.addingTimeInterval(minimumInterval)
        }
        try persistScheduleState()
        scheduleDeadline(at: deadline)
    }

    private func loadScheduleStateIfNeeded(now: Date) {
        guard !scheduleStateLoaded else { return }
        scheduleStateLoaded = true
        do {
            guard let state = try environmentStore.loadDigestScheduleState() else { return }
            guard scheduleStateIsSemanticallyValid(state, now: now) else {
                throw EnvironmentDocumentError.claimMismatch
            }
            pendingSince = state.pendingSince
            lastDigestAt = state.lastSuccessfulDigestAt
            nextEligibleAt = state.nextEligibleAt
        } catch {
            pendingSince = now
            lastDigestAt = nil
            let conservativeDeadline = now.addingTimeInterval(minimumInterval)
            nextEligibleAt = conservativeDeadline
            do {
                try environmentStore.saveDigestScheduleState(
                    EnvironmentDigestScheduleState(
                        pendingSince: now,
                        lastSuccessfulDigestAt: nil,
                        nextEligibleAt: conservativeDeadline,
                        pendingEventCount: 0
                    )
                )
                scheduleDeadline(at: conservativeDeadline)
            } catch {
                scheduleStateBlocked = true
            }
        }
    }

    private func scheduleStateIsSemanticallyValid(
        _ state: EnvironmentDigestScheduleState,
        now: Date
    ) -> Bool {
        let maximumFutureDate = now.addingTimeInterval(
            max(15 * 60, minimumInterval)
        )
        let dates = [state.pendingSince, state.lastSuccessfulDigestAt, state.nextEligibleAt]
            .compactMap { $0 }
        guard dates.allSatisfy({
            $0.timeIntervalSince1970.isFinite && $0 <= maximumFutureDate
        }) else { return false }
        if let pendingSince = state.pendingSince, pendingSince > now { return false }
        if let lastSuccessfulDigestAt = state.lastSuccessfulDigestAt,
           lastSuccessfulDigestAt > now { return false }
        guard state.pendingSince == nil || state.lastSuccessfulDigestAt == nil else { return false }

        let expectedDeadline: Date?
        if let lastSuccessfulDigestAt = state.lastSuccessfulDigestAt {
            expectedDeadline = lastSuccessfulDigestAt.addingTimeInterval(minimumInterval)
        } else if let pendingSince = state.pendingSince {
            expectedDeadline = pendingSince.addingTimeInterval(minimumInterval)
        } else {
            expectedDeadline = nil
        }
        switch (state.nextEligibleAt, expectedDeadline) {
        case (nil, _):
            return true
        case (let actual?, let expected?):
            return abs(actual.timeIntervalSince(expected)) < 0.001
        case (.some, nil):
            return false
        }
    }

    private func deadlineNanoseconds(until deadline: Date, now: Date) -> UInt64 {
        let interval = deadline.timeIntervalSince(now)
        guard interval.isFinite, interval > 0 else { return 0 }
        let bounded = min(interval, max(15 * 60, minimumInterval))
        return UInt64((bounded * 1_000_000_000).rounded(.up))
    }

    private static func boundedMinimumInterval(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite else { return 600 }
        return min(max(1, interval), maximumScheduleInterval)
    }

    private static func boundedClaimRecoveryBackoff(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite else { return defaultClaimRecoveryBackoff }
        return min(max(1, interval), maximumClaimRecoveryBackoff)
    }

    private func persistScheduleState() throws {
        let eventCount: Int
        do {
            eventCount = try eventStore.inventory().eventCount
        } catch {
            eventCount = 0
        }
        try environmentStore.saveDigestScheduleState(
            EnvironmentDigestScheduleState(
                pendingSince: pendingSince,
                lastSuccessfulDigestAt: lastDigestAt,
                nextEligibleAt: nextEligibleAt,
                pendingEventCount: max(0, min(500, eventCount))
            )
        )
    }

    private func persistScheduleState(afterSuccessAt now: Date) throws {
        let tailCount = try eventStore.inventory().eventCount
        lastDigestAt = now
        pendingSince = nil
        nextEligibleAt = tailCount > 0 ? now.addingTimeInterval(minimumInterval) : nil
        try environmentStore.saveDigestScheduleState(
            EnvironmentDigestScheduleState(
                pendingSince: nil,
                lastSuccessfulDigestAt: now,
                nextEligibleAt: nextEligibleAt,
                pendingEventCount: tailCount
            )
        )
    }

    private func emitAppendDiagnostics(_ result: TypingEventAppendResult) {
        if result.truncatedScalarCount > 0 {
            emitDiagnostic(stage: "context_event_truncated", fields: [.init(.eventCount, result.inventory.eventCount), .init(.byteCount, result.inventory.byteCount), .init(.truncatedScalarCount, result.truncatedScalarCount)])
        }
        if result.droppedEventCount > 0 || result.droppedByteCount > 0 {
            emitDiagnostic(stage: "context_backlog_trimmed", fields: [.init(.eventCount, result.inventory.eventCount), .init(.byteCount, result.inventory.byteCount), .init(.droppedCount, result.droppedEventCount)])
        }
    }

    private func emitDeferredDiagnostic(inventory: TypingEventInventory, cooldownRemaining: TimeInterval) {
        guard deferredDiagnosticFailureAt != lastDigestFailureAt else { return }
        deferredDiagnosticFailureAt = lastDigestFailureAt
        emitDiagnostic(stage: "context_digest_deferred", fields: [.init(.eventCount, inventory.eventCount), .init(.byteCount, inventory.byteCount), .init(.cooldownRemainingSeconds, Int(ceil(cooldownRemaining)))])
    }

    private func emitArchiveDiagnostic(_ result: TypingEventArchiveResult) {
        guard result.deletedFileCount > 0 else { return }
        emitDiagnostic(stage: "context_archive_pruned", fields: [.init(.byteCount, result.deletedByteCount), .init(.deletedFileCount, result.deletedFileCount)])
    }

    private func emitDiagnostic(stage: String, fields: [InputDebugDiagnostics.Field]) {
        diagnosticSink([.init(.stage, stage), .init(.providerGeneration, providerGeneration ?? 0)] + fields)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func sanitized(_ event: AITypingEvent) -> AITypingEvent {
        var event = event
        if event.commitKind == .externalDelete, event.rawInput == nil, event.committedText == nil,
           TextProtection.requiresNoCorrection("knowtype", appBundleID: event.appBundleID) {
            event.rawInput = "protected:delete"
            event.committedText = "protected:delete"
            event.candidateSource = "protected"
            return event
        }
        if let rawInput = event.rawInput, TextProtection.requiresNoCorrection(rawInput, appBundleID: event.appBundleID) {
            event.rawInput = protectedLabel(for: rawInput)
            event.committedText = event.rawInput
            event.candidateSource = "protected"
        }
        if let committedText = event.committedText, TextProtection.requiresNoCorrection(committedText, appBundleID: event.appBundleID) {
            event.committedText = protectedLabel(for: committedText)
            event.candidateSource = "protected"
        }
        return event
    }

    private func protectedLabel(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") { return "protected:url" }
        if trimmed.contains("/") { return "protected:path" }
        if trimmed.contains("@") { return "protected:email" }
        return "protected:command"
    }
}
