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
    private(set) var claimBlockedReevaluationCount = 0

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

    func recordClaimBlockedReevaluation() {
        claimBlockedReevaluationCount += 1
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
    private static let defaultMinimumInterval: TimeInterval = 6 * 60 * 60
    private static let defaultMaximumPendingAge: TimeInterval = 24 * 60 * 60
    private static let defaultDigestBudgetWindow: TimeInterval = 24 * 60 * 60
    private static let maximumScheduleInterval: TimeInterval = 24 * 60 * 60
    private static let maximumBudgetWindow: TimeInterval = 7 * 24 * 60 * 60
    private static let defaultClaimRecoveryBackoff: TimeInterval = 60
    private static let maximumClaimRecoveryBackoff: TimeInterval = 15 * 60

    private struct GateWaitKey: Equatable {
        var identity: String
        var generation: UInt64
    }

    private enum DigestDeferralReason: String {
        case maximumPendingAge = "pending_age"
        case minimumInterval = "minimum_interval"
        case rollingBudget = "rolling_budget"
        case providerCooldown = "provider_cooldown"
        case scheduleRepair = "schedule_repair"
    }

    private struct DigestEligibility {
        var isEligible: Bool
        var deadline: Date?
        var reason: DigestDeferralReason?
    }

    private enum RecordPreparation: Equatable {
        case ready
        case appendWithoutProcessing
        case blocked
    }

    private enum DigestClaimRecovery: Sendable {
        case none
        case recovered
        case blocked
        case gatePersistenceBlocked(retryAt: Date)
        case superseded
    }

    private struct DigestClaimRecoveryFlight {
        let token: UUID
        var waiters: [CheckedContinuation<DigestClaimRecovery, Never>] = []
    }

    private struct DigestClaimProtection {
        let token: UUID
        let rawData: Data
        var processFinished = false
        var attemptFinished = false
    }

    private struct DigestCommitResult: Sendable {
        var archiveResult: TypingEventArchiveResult
        var pendingTailCount: Int
        var pendingTailSince: Date?
    }

    private let provider: (any LLMProvider)?
    private let providerRegistry: ProviderRuntimeRegistry?
    private let eventStore: TypingEventStore
    private let environmentStore: EnvironmentDocumentStore
    private let batchSize: Int
    private let minimumInterval: TimeInterval
    private let maximumPendingAge: TimeInterval
    private let digestBudgetWindow: TimeInterval
    private let maximumDigestsPerWindow: Int
    private let diagnosticSink: @Sendable ([InputDebugDiagnostics.Field]) -> Void
    private let requestGate: ProviderRequestGate
    private let nowProvider: @Sendable () -> Date
    private let hardTimeoutNanoseconds: UInt64
    private let testProbe: AIContextMemoryRuntimeTestProbe?
    private let claimRecoveryBackoff: TimeInterval
    private let claimRecoverySleeper: (@Sendable (UInt64) async -> Void)?
    private var providerIdentity = "context-digest"
    private var lastDigestAt: Date?
    private var successfulDigestTimestamps: [Date] = []
    private var pendingSince: Date?
    private var nextEligibleAt: Date?
    private var conservativeScheduleDeadline: Date?
    private var scheduleStateLoaded = false
    private var scheduleStateBlocked = false
    private var lastDigestFailureAt: Date?
    private var deferredDiagnosticKey: String?
    private var digestInFlight = false
    private var digestRerunRequested = false
    private var digestRerunScheduled = false
    private var digestClaimProtection: DigestClaimProtection?
    private var claimBlockedReevaluationRequested = false
    private var claimBlockedReevaluationScheduled = false
    private var persistedClaimNeedsRecovery = true
    private var providerGeneration: UInt64?
    private var deadlineTask: Task<Void, Never>?
    private var scheduledDeadlineAt: Date?
    private var gateWaitKey: GateWaitKey?
    private var gatePersistenceRetryAt: Date?
    private var claimRecoveryRetryAt: Date?
    private var claimRecoveryBlockedCount = 0
    private var digestClaimRecoveryFlight: DigestClaimRecoveryFlight?

    public init(
        provider: (any LLMProvider)?,
        eventStore: TypingEventStore = TypingEventStore(),
        environmentStore: EnvironmentDocumentStore = EnvironmentDocumentStore(),
        batchSize: Int = 50,
        minimumInterval: TimeInterval = 6 * 60 * 60,
        maximumPendingAge: TimeInterval = 24 * 60 * 60,
        digestBudgetWindow: TimeInterval = 24 * 60 * 60,
        maximumDigestsPerWindow: Int = 4,
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
        self.maximumPendingAge = Self.boundedMaximumPendingAge(maximumPendingAge)
        self.digestBudgetWindow = Self.boundedDigestBudgetWindow(digestBudgetWindow)
        self.maximumDigestsPerWindow = Self.boundedMaximumDigestsPerWindow(
            maximumDigestsPerWindow
        )
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
        maximumPendingAge: TimeInterval = 24 * 60 * 60,
        digestBudgetWindow: TimeInterval = 24 * 60 * 60,
        maximumDigestsPerWindow: Int = 4,
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
        self.maximumPendingAge = Self.boundedMaximumPendingAge(maximumPendingAge)
        self.digestBudgetWindow = Self.boundedDigestBudgetWindow(digestBudgetWindow)
        self.maximumDigestsPerWindow = Self.boundedMaximumDigestsPerWindow(
            maximumDigestsPerWindow
        )
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
        minimumInterval: TimeInterval = 6 * 60 * 60,
        maximumPendingAge: TimeInterval = 24 * 60 * 60,
        digestBudgetWindow: TimeInterval = 24 * 60 * 60,
        maximumDigestsPerWindow: Int = 4,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.provider = nil
        self.providerRegistry = providerRegistry
        self.eventStore = eventStore
        self.environmentStore = environmentStore
        self.batchSize = max(1, batchSize)
        self.minimumInterval = Self.boundedMinimumInterval(minimumInterval)
        self.maximumPendingAge = Self.boundedMaximumPendingAge(maximumPendingAge)
        self.digestBudgetWindow = Self.boundedDigestBudgetWindow(digestBudgetWindow)
        self.maximumDigestsPerWindow = Self.boundedMaximumDigestsPerWindow(
            maximumDigestsPerWindow
        )
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

    func hasActiveDigestClaimProtectionForTesting() -> Bool {
        digestClaimProtection != nil
    }

    func scheduledDeadlineForTesting() -> Date? {
        scheduledDeadlineAt
    }

    func cancelGateAvailabilityWaitForTesting() {
        cancelGateAvailabilityWait()
    }

    init(
        providerRegistry: ProviderRuntimeRegistry,
        eventStore: TypingEventStore,
        environmentStore: EnvironmentDocumentStore,
        batchSize: Int,
        minimumInterval: TimeInterval,
        maximumPendingAge: TimeInterval = 24 * 60 * 60,
        digestBudgetWindow: TimeInterval = 24 * 60 * 60,
        maximumDigestsPerWindow: Int = 4,
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        testProbe: AIContextMemoryRuntimeTestProbe,
        claimRecoverySleeper: (@Sendable (UInt64) async -> Void)? = nil
    ) {
        self.provider = nil
        self.providerRegistry = providerRegistry
        self.eventStore = eventStore
        self.environmentStore = environmentStore
        self.batchSize = max(1, batchSize)
        self.minimumInterval = Self.boundedMinimumInterval(minimumInterval)
        self.maximumPendingAge = Self.boundedMaximumPendingAge(maximumPendingAge)
        self.digestBudgetWindow = Self.boundedDigestBudgetWindow(digestBudgetWindow)
        self.maximumDigestsPerWindow = Self.boundedMaximumDigestsPerWindow(
            maximumDigestsPerWindow
        )
        self.requestGate = providerRegistry.requestGate
        self.nowProvider = nowProvider
        self.hardTimeoutNanoseconds = UInt64(AIRecommendationRuntime.Defaults.hardTimeoutMilliseconds) * 1_000_000
        self.testProbe = testProbe
        self.claimRecoveryBackoff = Self.defaultClaimRecoveryBackoff
        self.claimRecoverySleeper = claimRecoverySleeper
        self.diagnosticSink = { InputDebugDiagnostics.emit(category: .ai, fields: $0) }
    }

    public func record(_ event: AITypingEvent) async {
        guard claimRecoveryRetryAt == nil else { return }
        if digestInFlight { digestRerunRequested = true }
        var preparation = await preparePersistedClaimForRecord(now: nowProvider())
        guard preparation != .blocked else { return }
        let sanitizedEvent = sanitized(event)
        var lease: ProviderRuntimeLease? = nil
        if preparation == .appendWithoutProcessing, let providerRegistry {
            let loaded = await providerRegistry.leaseForEligibleDispatch()
            guard claimRecoveryRetryAt == nil else { return }
            guard loaded.provider != nil else { return }
            preparation = await preparePersistedClaimForRecord(now: nowProvider())
            guard claimRecoveryRetryAt == nil, preparation != .blocked else { return }
            if preparation == .appendWithoutProcessing {
                applyProviderLease(loaded, preservingGatePersistenceRetry: true)
            } else {
                applyProviderLease(loaded)
                lease = loaded
            }
        }
        if preparation == .appendWithoutProcessing {
            do {
                let prefixProtection = digestClaimProtection.map {
                    TypingEventPendingPrefixProtection.claimed($0.rawData)
                } ?? .potentialDigest
                let result = try eventStore.appendBounded(
                    sanitizedEvent,
                    prefixProtection: prefixProtection
                )
                emitAppendDiagnostics(result)
            } catch {}
            return
        }
        if let providerRegistry, lease == nil {
            let loaded = await providerRegistry.leaseForEligibleDispatch()
            guard loaded.provider != nil else { return }
            applyProviderLease(loaded)
            lease = loaded
        }
        do {
            let prefixProtection = digestClaimProtection.map {
                TypingEventPendingPrefixProtection.claimed($0.rawData)
            } ?? .none
            let result = try eventStore.appendBounded(
                sanitizedEvent,
                prefixProtection: prefixProtection
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
        guard claimRecoveryRetryAt == nil else { return }
        if digestInFlight {
            digestRerunRequested = true
            if persistedClaimNeedsRecovery, digestClaimRecoveryFlight != nil {
                _ = await attemptDigestClaimRecovery(now: now)
            }
            return
        }
        guard !digestRerunScheduled else { return }
        var dispatchLease = dispatchLease
        if gateWaitKey != nil {
            if let providerRegistry {
                let loaded: ProviderRuntimeLease
                if let dispatchLease {
                    loaded = dispatchLease
                } else {
                    loaded = await providerRegistry.leaseForEligibleDispatch()
                }
                applyProviderLease(loaded)
                dispatchLease = loaded
            }
            guard gateWaitKey == nil else {
                if digestClaimProtection != nil {
                    claimBlockedReevaluationRequested = true
                }
                if let inventory = try? eventStore.inventory(),
                   inventory.eventCount > 0,
                   !inventory.isProtectedOnly {
                    let remaining = max(
                        0,
                        scheduledDeadlineAt?.timeIntervalSince(now)
                            ?? digestCooldownRemaining(at: now)
                            ?? 0
                    )
                    emitDeferredDiagnostic(
                        inventory: inventory,
                        cooldownRemaining: remaining,
                        reason: .providerCooldown
                    )
                }
                return
            }
        }
        digestInFlight = true
        var ownedClaimProtectionToken: UUID?
        defer {
            if let ownedClaimProtectionToken {
                finishDigestClaimProcess(token: ownedClaimProtectionToken)
            }
            digestInFlight = false
            if digestRerunRequested {
                digestRerunRequested = false
                if claimRecoveryRetryAt == nil,
                   gatePersistenceRetryAt == nil,
                   (gateWaitKey == nil || deadlineTask == nil) {
                    scheduleCoalescedRerun()
                }
            }
        }

        loadScheduleStateIfNeeded(now: now)
        guard !scheduleStateBlocked else { return }
        guard !conservativeScheduleRepairDefersWork(at: now) else { return }

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
        guard digestClaimProtection == nil else {
            claimBlockedReevaluationRequested = true
            return
        }

        let inventory: TypingEventInventory
        do { inventory = try eventStore.inventory() } catch { return }
        guard inventory.eventCount > 0 else {
            pendingSince = nil
            nextEligibleAt = nil
            conservativeScheduleDeadline = nil
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

        let previousPendingSince = pendingSince
        pendingSince = Self.boundedPendingTimestamp(
            inventory.oldestEventTimestamp,
            noLaterThan: now
        ) ?? pendingSince ?? now
        let previousNextEligibleAt = nextEligibleAt
        let eligibility = digestEligibility(for: inventory, now: now)
        nextEligibleAt = eligibility.deadline
        let scheduleChanged = previousPendingSince != pendingSince
            || previousNextEligibleAt != nextEligibleAt
        if conservativeScheduleDeadline == nil, scheduleChanged {
            guard (try? persistScheduleState()) != nil else { return }
        }
        guard eligibility.isEligible else {
            guard let deferredDeadline = eligibility.deadline,
                  let reason = eligibility.reason else { return }
            scheduleDeadline(at: deferredDeadline)
            emitDeferredDiagnostic(
                inventory: inventory,
                cooldownRemaining: deferredDeadline.timeIntervalSince(now),
                reason: reason
            )
            return
        }

        let lease: ProviderRuntimeLease?
        let activeProvider: (any LLMProvider)?
        if let providerRegistry {
            let loaded: ProviderRuntimeLease
            if let dispatchLease {
                loaded = dispatchLease
            } else {
                loaded = await providerRegistry.leaseForEligibleDispatch()
            }
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
        switch gatePreflight {
        case .available, .busy:
            cancelGatePersistenceRetry()
        case .cooldown(let deadline, _):
            cancelGatePersistenceRetry()
            scheduleGateAvailabilityWake(observedDeadline: deadline)
            emitDeferredDiagnostic(
                inventory: inventory,
                cooldownRemaining: deadline.timeIntervalSince(now),
                reason: .providerCooldown
            )
            return
        case .staleGeneration:
            invalidateProviderRuntimeState()
            return
        case .persistenceBlocked(let retryAt):
            scheduleGatePersistenceRetry(at: retryAt)
            return
        }
        let localCooldown = digestCooldownRemaining(at: now)
        if let deadline = localCooldown.map({ now.addingTimeInterval($0) }), deadline > now {
            scheduleDeadline(at: deadline)
            emitDeferredDiagnostic(
                inventory: inventory,
                cooldownRemaining: deadline.timeIntervalSince(now),
                reason: .providerCooldown
            )
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
            let protectionToken = beginDigestClaimProtection(rawData: snapshot.rawData)
            ownedClaimProtectionToken = protectionToken
            let registry = providerRegistry
            providerGateStarted = true
            let gated: (LLMResponse, String) = try await requestGate.executeWithHardTimeout(
                providerIdentity: requestIdentity,
                generation: requestGeneration,
                timeoutNanoseconds: hardTimeoutNanoseconds,
                onAttemptCompletion: {
                    await self.finishDigestClaimAttempt(token: protectionToken)
                }
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
            let successHistory = successfulDigestHistory(adding: now, relativeTo: now)
            let successBatchSize = batchSize
            let successMinimumInterval = minimumInterval
            let successMaximumPendingAge = maximumPendingAge
            let successBudgetWindow = digestBudgetWindow
            let successMaximumDigestsPerWindow = maximumDigestsPerWindow
            let persistAfterClaim: @Sendable () throws -> DigestCommitResult = {
                _ = try self.environmentStore.replaceGeneratedSection(with: generated)
                let result = try self.eventStore.commitPendingEvents(matching: snapshot, beforeArchive: {})
                guard self.eventStore.hasProcessedArchive(
                    prefixSHA256: Self.sha256(snapshot.rawData),
                    byteCount: snapshot.rawData.count
                ) else {
                    throw TypingEventStoreError.pendingContentChanged
                }
                try self.environmentStore.saveDigestArchiveReceipt(
                    EnvironmentDigestArchiveReceipt(
                        claimedPrefixSHA256: Self.sha256(snapshot.rawData),
                        claimedPrefixByteCount: snapshot.rawData.count,
                        claimedEventCount: snapshot.claimedEventCount,
                        generatedSHA256: claim.generatedSHA256,
                        archivedByteCount: snapshot.rawData.count,
                        successfulDigestAt: now
                    )
                )
                let tailInventory = try self.eventStore.inventory()
                let tailCount = tailInventory.eventCount
                let tailPendingSince = tailCount > 0
                    ? Self.boundedPendingTimestamp(
                        tailInventory.oldestEventTimestamp,
                        noLaterThan: now
                    ) ?? now
                    : nil
                try self.environmentStore.saveDigestScheduleState(
                    EnvironmentDigestScheduleState(
                        pendingSince: tailPendingSince,
                        lastSuccessfulDigestAt: now,
                        nextEligibleAt: tailCount > 0
                            ? Self.nextDigestDeadline(
                                eventCount: tailCount,
                                pendingSince: tailPendingSince,
                                successfulDigestTimestamps: successHistory,
                                lastSuccessfulDigestAt: now,
                                batchSize: successBatchSize,
                                minimumInterval: successMinimumInterval,
                                maximumPendingAge: successMaximumPendingAge,
                                digestBudgetWindow: successBudgetWindow,
                                maximumDigestsPerWindow: successMaximumDigestsPerWindow,
                                now: now
                            )
                            : nil,
                        pendingEventCount: tailCount,
                        successfulDigestTimestamps: successHistory
                    )
                )
                return DigestCommitResult(
                    archiveResult: result,
                    pendingTailCount: tailCount,
                    pendingTailSince: tailPendingSince
                )
            }
            let result: DigestCommitResult
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
            applyDigestSuccessState(
                at: now,
                pendingTailCount: result.pendingTailCount,
                pendingAnchor: result.pendingTailSince,
                successfulDigestTimestamps: successHistory
            )
            finishDigestSuccessScheduling()
            emitArchiveDiagnostic(result.archiveResult)
        } catch is ProviderRequestBudgetError {
            scheduleDeadline(at: now.addingTimeInterval(minimumInterval))
        } catch ProviderRuntimeRegistryError.staleGeneration {
            invalidateProviderRuntimeState()
        } catch ProviderRequestGateError.staleGeneration {
            invalidateProviderRuntimeState()
        } catch ProviderRequestGateError.cooldown(let deadline, _) {
            scheduleGateAvailabilityWake(
                for: GateWaitKey(
                    identity: requestIdentity,
                    generation: requestGeneration
                ),
                observedDeadline: deadline
            )
            emitDeferredDiagnostic(
                inventory: inventory,
                cooldownRemaining: deadline.timeIntervalSince(now),
                reason: .providerCooldown
            )
        } catch ProviderRequestGateError.busy {
            scheduleGateAvailabilityWake()
            await testProbe?.pauseAfterGateWaiterInstallIfNeeded()
            return
        } catch ProviderRequestGatePersistenceError.blocked {
            await scheduleGatePersistenceRetryFromGate()
            return
        } catch TypingEventStoreError.pendingContentChanged {
            return
        } catch EnvironmentDocumentError.invalidDigestCandidate {
            await markDigestFailure(
                at: now,
                providerIdentity: requestIdentity,
                generation: requestGeneration
            )
        } catch is TimeoutError {
            await markDigestFailure(
                at: now,
                providerIdentity: requestIdentity,
                generation: requestGeneration
            )
        } catch {
            if error is CancellationError { return }
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
            await markDigestFailure(
                at: now,
                providerIdentity: requestIdentity,
                generation: requestGeneration
            )
        }
    }

    private func preparePersistedClaimForRecord(now: Date) async -> RecordPreparation {
        loadScheduleStateIfNeeded(now: now)
        guard !scheduleStateBlocked else { return .blocked }
        guard !conservativeScheduleRepairDefersWork(at: now) else { return .blocked }
        guard digestClaimProtection == nil, persistedClaimNeedsRecovery else { return .ready }
        switch await attemptDigestClaimRecovery(now: now) {
        case .none, .recovered:
            return .ready
        case .gatePersistenceBlocked:
            return .appendWithoutProcessing
        case .blocked, .superseded:
            return .blocked
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
        case .gatePersistenceBlocked(let retryAt):
            persistedClaimNeedsRecovery = true
            scheduleGatePersistenceRetry(at: retryAt)
        case .superseded:
            break
        }
        return completeClaimRecovery(token: token, result: result)
    }

    private func recoverDigestClaim(now: Date, token: UUID) async -> DigestClaimRecovery {
        await testProbe?.pauseBeforeClaimRecoveryGatePreflightIfNeeded()
        guard isCurrentClaimRecovery(token) else { return .superseded }
        switch await requestGate.persistencePreflight() {
        case .persistenceBlocked(let retryAt):
            return .gatePersistenceBlocked(retryAt: retryAt)
        case .available, .busy, .cooldown, .staleGeneration:
            cancelGatePersistenceRetry()
        }
        guard isCurrentClaimRecovery(token) else { return .superseded }
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
                let successfulDigestAt = try ensureDigestRecoveryReceipt(
                    for: claim,
                    relativeTo: now
                )
                try persistScheduleState(
                    afterSuccessAt: successfulDigestAt,
                    recoveryNow: now
                )
                try environmentStore.clearDigestClaim()
                try? environmentStore.clearDigestArchiveReceipt()
                finishDigestSuccessScheduling()
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
                    archivedByteCount: claim.claimedPrefixByteCount,
                    successfulDigestAt: now
                )
            )
            try persistScheduleState(afterSuccessAt: now, recoveryNow: now)
            try environmentStore.clearDigestClaim()
            try? environmentStore.clearDigestArchiveReceipt()
            finishDigestSuccessScheduling()
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

    private func applyProviderLease(
        _ lease: ProviderRuntimeLease,
        preservingGatePersistenceRetry: Bool = false
    ) {
        let changed = providerGeneration != lease.generation || providerIdentity != lease.fingerprint
        providerGeneration = lease.generation
        providerIdentity = lease.fingerprint
        if changed {
            resetClaimRecoveryState()
            if !preservingGatePersistenceRetry {
                cancelGatePersistenceRetry()
            }
            cancelGateAvailabilityWait()
            lastDigestFailureAt = nil
            deferredDiagnosticKey = nil
        }
    }

    private func invalidateProviderRuntimeState() {
        resetClaimRecoveryState()
        cancelGatePersistenceRetry()
        cancelGateAvailabilityWait()
        lastDigestFailureAt = nil
        deferredDiagnosticKey = nil
        providerGeneration = nil
        providerIdentity = "context-digest"
    }

    private func applyDigestSuccessState(
        at now: Date,
        pendingTailCount: Int,
        pendingAnchor: Date?,
        successfulDigestTimestamps: [Date]
    ) {
        lastDigestAt = now
        self.successfulDigestTimestamps = successfulDigestTimestamps
        pendingSince = pendingTailCount > 0 ? (pendingAnchor ?? now) : nil
        conservativeScheduleDeadline = nil
        nextEligibleAt = pendingTailCount > 0
            ? nextDigestDeadline(
                eventCount: pendingTailCount,
                pendingSince: pendingSince,
                successfulDigestTimestamps: successfulDigestTimestamps,
                now: now
            )
            : nil
        lastDigestFailureAt = nil
        deferredDiagnosticKey = nil
    }

    private func finishDigestSuccessScheduling() {
        if let nextEligibleAt {
            scheduleDeadline(at: nextEligibleAt)
        } else {
            cancelDeadline()
        }
    }

    private func markDigestFailure(
        at now: Date,
        providerIdentity: String,
        generation: UInt64
    ) async {
        lastDigestFailureAt = now
        deferredDiagnosticKey = nil
        let localDeadline = now.addingTimeInterval(60)
        let gateDeadline = await requestGate.cooldownDeadline(
            providerIdentity: providerIdentity,
            generation: generation
        )
        if let gateDeadline {
            scheduleGateAvailabilityWake(
                for: GateWaitKey(
                    identity: providerIdentity,
                    generation: generation
                ),
                observedDeadline: gateDeadline
            )
        } else {
            scheduleDeadline(at: localDeadline)
        }
    }

    private func digestCooldownRemaining(at now: Date) -> TimeInterval? {
        guard let lastDigestFailureAt else { return nil }
        let remaining = 60 - now.timeIntervalSince(lastDigestFailureAt)
        return remaining > 0 ? remaining : nil
    }

    private func digestEligibility(
        for inventory: TypingEventInventory,
        now: Date
    ) -> DigestEligibility {
        successfulDigestTimestamps = normalizedSuccessfulDigestHistory(
            successfulDigestTimestamps,
            relativeTo: now
        )
        var constraints = digestConstraints(
            eventCount: inventory.eventCount,
            pendingSince: pendingSince,
            successfulDigestTimestamps: successfulDigestTimestamps,
            now: now
        )
        if let conservativeScheduleDeadline, conservativeScheduleDeadline > now {
            constraints.append((conservativeScheduleDeadline, .scheduleRepair))
        } else {
            conservativeScheduleDeadline = nil
        }
        guard let deferred = constraints
            .filter({ $0.deadline > now })
            .max(by: { $0.deadline < $1.deadline }) else {
            return DigestEligibility(isEligible: true, deadline: nil, reason: nil)
        }
        return DigestEligibility(
            isEligible: false,
            deadline: deferred.deadline,
            reason: deferred.reason
        )
    }

    private func nextDigestDeadline(
        eventCount: Int,
        pendingSince: Date?,
        successfulDigestTimestamps: [Date],
        now: Date
    ) -> Date {
        Self.nextDigestDeadline(
            eventCount: eventCount,
            pendingSince: pendingSince,
            successfulDigestTimestamps: successfulDigestTimestamps,
            lastSuccessfulDigestAt: lastDigestAt,
            batchSize: batchSize,
            minimumInterval: minimumInterval,
            maximumPendingAge: maximumPendingAge,
            digestBudgetWindow: digestBudgetWindow,
            maximumDigestsPerWindow: maximumDigestsPerWindow,
            now: now
        )
    }

    private static func nextDigestDeadline(
        eventCount: Int,
        pendingSince: Date?,
        successfulDigestTimestamps: [Date],
        lastSuccessfulDigestAt: Date?,
        batchSize: Int,
        minimumInterval: TimeInterval,
        maximumPendingAge: TimeInterval,
        digestBudgetWindow: TimeInterval,
        maximumDigestsPerWindow: Int,
        now: Date
    ) -> Date {
        var deadlines: [Date] = []
        if eventCount < batchSize {
            deadlines.append((pendingSince ?? now).addingTimeInterval(maximumPendingAge))
        }
        if let lastSuccessfulDigestAt = successfulDigestTimestamps.last
            ?? lastSuccessfulDigestAt {
            deadlines.append(lastSuccessfulDigestAt.addingTimeInterval(minimumInterval))
        }
        if successfulDigestTimestamps.count >= maximumDigestsPerWindow {
            let blockingIndex = successfulDigestTimestamps.count - maximumDigestsPerWindow
            deadlines.append(
                successfulDigestTimestamps[blockingIndex]
                    .addingTimeInterval(digestBudgetWindow)
            )
        }
        return deadlines.max() ?? now
    }

    private func digestConstraints(
        eventCount: Int,
        pendingSince: Date?,
        successfulDigestTimestamps: [Date],
        now: Date
    ) -> [(deadline: Date, reason: DigestDeferralReason)] {
        var constraints: [(deadline: Date, reason: DigestDeferralReason)] = []
        if eventCount < batchSize {
            constraints.append((
                (pendingSince ?? now).addingTimeInterval(maximumPendingAge),
                .maximumPendingAge
            ))
        }
        if let lastSuccessfulDigestAt = successfulDigestTimestamps.last ?? lastDigestAt {
            constraints.append((
                lastSuccessfulDigestAt.addingTimeInterval(minimumInterval),
                .minimumInterval
            ))
        }
        if successfulDigestTimestamps.count >= maximumDigestsPerWindow {
            let blockingIndex = successfulDigestTimestamps.count - maximumDigestsPerWindow
            constraints.append((
                successfulDigestTimestamps[blockingIndex]
                    .addingTimeInterval(digestBudgetWindow),
                .rollingBudget
            ))
        }
        return constraints
    }

    private func successfulDigestHistory(
        adding timestamp: Date,
        relativeTo now: Date
    ) -> [Date] {
        normalizedSuccessfulDigestHistory(
            successfulDigestTimestamps + [timestamp],
            relativeTo: now
        )
    }

    private func normalizedSuccessfulDigestHistory(
        _ timestamps: [Date],
        relativeTo now: Date
    ) -> [Date] {
        let cutoff = now.addingTimeInterval(-digestBudgetWindow)
        let maximumFutureTimestamp = now.addingTimeInterval(
            maximumScheduleAnchorOffset
        )
        var result: [Date] = []
        for timestamp in timestamps
            .filter({
                $0.timeIntervalSince1970.isFinite
                    && $0 > cutoff
                    && $0 <= maximumFutureTimestamp
            })
            .sorted() {
            if result.last != timestamp { result.append(timestamp) }
        }
        return result
    }

    private func scheduleDeadline(at date: Date) {
        guard claimRecoveryRetryAt == nil else { return }
        gatePersistenceRetryAt = nil
        gateWaitKey = nil
        digestRerunScheduled = false
        deadlineTask?.cancel()
        scheduledDeadlineAt = date
        let delay = deadlineNanoseconds(until: date, now: nowProvider())
        deadlineTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            guard !Task.isCancelled, let self else { return }
            await self.processIfNeeded(now: self.nowProvider())
        }
    }

    private func scheduleCoalescedRerun() {
        guard claimRecoveryRetryAt == nil,
              gatePersistenceRetryAt == nil,
              !digestRerunScheduled else { return }
        gateWaitKey = nil
        deadlineTask?.cancel()
        digestRerunScheduled = true
        scheduledDeadlineAt = nil
        deadlineTask = Task { [weak self] in
            guard !Task.isCancelled, let self else { return }
            await self.runCoalescedRerun()
        }
    }

    private func runCoalescedRerun() async {
        guard digestRerunScheduled else { return }
        digestRerunScheduled = false
        deadlineTask = nil
        scheduledDeadlineAt = nil
        let recordsClaimBlockedReevaluation = claimBlockedReevaluationScheduled
        claimBlockedReevaluationScheduled = false
        await processIfNeeded(now: nowProvider(), dispatchLease: nil)
        if recordsClaimBlockedReevaluation {
            await testProbe?.recordClaimBlockedReevaluation()
        }
    }

    private func scheduleGateAvailabilityWake(
        for requestedKey: GateWaitKey? = nil,
        observedDeadline: Date? = nil
    ) {
        guard claimRecoveryRetryAt == nil else { return }
        gatePersistenceRetryAt = nil
        let key = requestedKey ?? GateWaitKey(
            identity: providerIdentity,
            generation: providerGeneration ?? 0
        )
        if gateWaitKey == key, deadlineTask != nil {
            if let observedDeadline { scheduledDeadlineAt = observedDeadline }
            return
        }
        deadlineTask?.cancel()
        digestRerunScheduled = false
        gateWaitKey = key
        scheduledDeadlineAt = observedDeadline
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
        gatePersistenceRetryAt = nil
        gateWaitKey = nil
        digestRerunScheduled = false
        deadlineTask?.cancel()
        deadlineTask = nil
        scheduledDeadlineAt = nil
    }

    private func cancelGateAvailabilityWait() {
        guard gateWaitKey != nil else { return }
        gateWaitKey = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        scheduledDeadlineAt = nil
    }

    private func gateAvailabilityDidWake(_ key: GateWaitKey) async {
        guard gateWaitKey == key else { return }
        gateWaitKey = nil
        deadlineTask = nil
        scheduledDeadlineAt = nil
        await processIfNeeded(now: nowProvider())
    }

    private func scheduleClaimRecoveryRetry(now: Date) {
        guard claimRecoveryRetryAt == nil else { return }
        claimRecoveryBlockedCount = min(500, claimRecoveryBlockedCount + 1)
        let deadline = now.addingTimeInterval(claimRecoveryBackoff)
        claimRecoveryRetryAt = deadline
        gatePersistenceRetryAt = nil
        gateWaitKey = nil
        digestRerunScheduled = false
        deadlineTask?.cancel()
        scheduledDeadlineAt = nil
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
        scheduledDeadlineAt = nil
        await processIfNeeded(now: nowProvider(), dispatchLease: nil)
    }

    private func clearClaimRecoveryBlock() {
        claimRecoveryBlockedCount = 0
        guard claimRecoveryRetryAt != nil else { return }
        claimRecoveryRetryAt = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        scheduledDeadlineAt = nil
    }

    private func scheduleGatePersistenceRetry(at retryAt: Date) {
        guard claimRecoveryRetryAt == nil else { return }
        if gatePersistenceRetryAt == retryAt, deadlineTask != nil { return }
        gatePersistenceRetryAt = retryAt
        gateWaitKey = nil
        digestRerunScheduled = false
        deadlineTask?.cancel()
        scheduledDeadlineAt = nil
        let delay = deadlineNanoseconds(until: retryAt, now: nowProvider())
        let sleeper = claimRecoverySleeper
        deadlineTask = Task { [weak self] in
            if let sleeper {
                await sleeper(delay)
            } else if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled, let self else { return }
            await self.gatePersistenceRetryDidWake(retryAt)
        }
        emitDiagnostic(
            stage: "context_gate_persistence_blocked",
            fields: [
                .init(
                    .cooldownRemainingSeconds,
                    max(0, Int(ceil(retryAt.timeIntervalSince(nowProvider()))))
                )
            ]
        )
    }

    private func scheduleGatePersistenceRetryFromGate() async {
        if case .persistenceBlocked(let retryAt) = await requestGate.persistencePreflight() {
            scheduleGatePersistenceRetry(at: retryAt)
        }
    }

    private func gatePersistenceRetryDidWake(_ retryAt: Date) async {
        guard gatePersistenceRetryAt == retryAt else { return }
        gatePersistenceRetryAt = nil
        deadlineTask = nil
        scheduledDeadlineAt = nil
        await processIfNeeded(now: nowProvider(), dispatchLease: nil)
    }

    private func cancelGatePersistenceRetry() {
        guard gatePersistenceRetryAt != nil else { return }
        gatePersistenceRetryAt = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        scheduledDeadlineAt = nil
    }

    private func scheduleAfterLocalArchive(now: Date) throws {
        let inventory = try eventStore.inventory()
        guard inventory.eventCount > 0 else {
            pendingSince = nil
            nextEligibleAt = nil
            conservativeScheduleDeadline = nil
            try persistScheduleState()
            cancelDeadline()
            return
        }

        pendingSince = Self.boundedPendingTimestamp(
            inventory.oldestEventTimestamp,
            noLaterThan: now
        ) ?? pendingSince ?? now
        let eligibility = digestEligibility(for: inventory, now: now)
        nextEligibleAt = eligibility.deadline
        try persistScheduleState()
        scheduleDeadline(at: eligibility.deadline ?? now)
    }

    private func loadScheduleStateIfNeeded(now: Date) {
        guard !scheduleStateLoaded else { return }
        scheduleStateLoaded = true
        do {
            guard let state = try environmentStore.loadDigestScheduleState() else { return }
            guard scheduleStateIsSemanticallyValid(state, now: now) else {
                throw EnvironmentDocumentError.claimMismatch
            }
            var persistedHistory = state.successfulDigestTimestamps
            if persistedHistory.isEmpty, let legacySuccess = state.lastSuccessfulDigestAt {
                persistedHistory = [legacySuccess]
            }
            successfulDigestTimestamps = normalizedSuccessfulDigestHistory(
                persistedHistory,
                relativeTo: now
            )
            lastDigestAt = state.lastSuccessfulDigestAt
                ?? successfulDigestTimestamps.last
            if state.pendingEventCount > 0 {
                pendingSince = state.pendingSince
                    ?? state.lastSuccessfulDigestAt
                    ?? now
            } else {
                pendingSince = state.pendingSince
            }
            nextEligibleAt = state.nextEligibleAt
            if state.pendingEventCount == 0,
               state.lastSuccessfulDigestAt == nil,
               state.successfulDigestTimestamps.isEmpty,
               let repairedDeadline = state.nextEligibleAt,
               repairedDeadline > now {
                conservativeScheduleDeadline = repairedDeadline
            }
        } catch {
            pendingSince = now
            lastDigestAt = nil
            successfulDigestTimestamps = []
            let conservativeDeadline = now.addingTimeInterval(
                max(minimumInterval, max(maximumPendingAge, digestBudgetWindow))
            )
            nextEligibleAt = conservativeDeadline
            conservativeScheduleDeadline = conservativeDeadline
            do {
                try environmentStore.saveDigestScheduleState(
                    EnvironmentDigestScheduleState(
                        pendingSince: now,
                        lastSuccessfulDigestAt: nil,
                        nextEligibleAt: conservativeDeadline,
                        pendingEventCount: 0,
                        successfulDigestTimestamps: []
                    )
                )
                scheduleDeadline(at: conservativeDeadline)
            } catch {
                scheduleStateBlocked = true
            }
        }
    }

    private func conservativeScheduleRepairDefersWork(at now: Date) -> Bool {
        guard let deadline = conservativeScheduleDeadline else { return false }
        guard deadline > now else {
            conservativeScheduleDeadline = nil
            return false
        }
        scheduleDeadline(at: deadline)
        return true
    }

    private func scheduleStateIsSemanticallyValid(
        _ state: EnvironmentDigestScheduleState,
        now: Date
    ) -> Bool {
        let maximumFutureAnchorDate = now.addingTimeInterval(
            maximumScheduleAnchorOffset
        )
        let maximumFutureDeadline = maximumFutureAnchorDate.addingTimeInterval(
            maximumScheduleAnchorOffset
        )
        let anchorDates = [state.pendingSince, state.lastSuccessfulDigestAt]
            .compactMap { $0 } + state.successfulDigestTimestamps
        guard anchorDates.allSatisfy({
            $0.timeIntervalSince1970.isFinite && $0 <= maximumFutureAnchorDate
        }) else { return false }
        if let nextEligibleAt = state.nextEligibleAt,
           (!nextEligibleAt.timeIntervalSince1970.isFinite
               || nextEligibleAt > maximumFutureDeadline) {
            return false
        }
        if let lastSuccessfulDigestAt = state.lastSuccessfulDigestAt,
           let latestPersistedSuccess = state.successfulDigestTimestamps.max(),
           abs(lastSuccessfulDigestAt.timeIntervalSince(latestPersistedSuccess)) >= 0.001 {
            return false
        }
        if state.pendingSince == nil,
           state.lastSuccessfulDigestAt == nil,
           state.nextEligibleAt == nil,
           state.pendingEventCount > 0 {
            return false
        }
        if let nextEligibleAt = state.nextEligibleAt {
            if let pendingSince = state.pendingSince, nextEligibleAt < pendingSince {
                return false
            }
            if let lastSuccessfulDigestAt = state.lastSuccessfulDigestAt,
               nextEligibleAt < lastSuccessfulDigestAt {
                return false
            }
        }
        return true
    }

    private var maximumScheduleAnchorOffset: TimeInterval {
        max(minimumInterval, max(maximumPendingAge, digestBudgetWindow))
    }

    private func deadlineNanoseconds(until deadline: Date, now: Date) -> UInt64 {
        let interval = deadline.timeIntervalSince(now)
        guard interval.isFinite, interval > 0 else { return 0 }
        let maximumSeconds = Double(UInt64.max) / 1_000_000_000
        return UInt64((min(interval, maximumSeconds) * 1_000_000_000).rounded(.up))
    }

    private static func boundedMinimumInterval(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite else { return defaultMinimumInterval }
        return min(max(1, interval), maximumScheduleInterval)
    }

    private static func boundedMaximumPendingAge(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite else { return defaultMaximumPendingAge }
        return min(max(1, interval), maximumBudgetWindow)
    }

    private static func boundedDigestBudgetWindow(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite else { return defaultDigestBudgetWindow }
        return min(max(1, interval), maximumBudgetWindow)
    }

    private static func boundedMaximumDigestsPerWindow(_ count: Int) -> Int {
        min(max(1, count), 64)
    }

    private static func boundedPendingTimestamp(
        _ timestamp: Date?,
        noLaterThan now: Date
    ) -> Date? {
        guard let timestamp,
              timestamp.timeIntervalSince1970.isFinite,
              timestamp <= now else {
            return nil
        }
        return timestamp
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
                pendingEventCount: max(0, min(500, eventCount)),
                successfulDigestTimestamps: successfulDigestTimestamps
            )
        )
    }

    private func ensureDigestRecoveryReceipt(
        for claim: EnvironmentDigestClaim,
        relativeTo now: Date
    ) throws -> Date {
        if let receipt = try environmentStore.loadDigestArchiveReceipt() {
            guard receipt.claimedPrefixSHA256 == claim.claimedPrefixSHA256,
                  receipt.claimedPrefixByteCount == claim.claimedPrefixByteCount,
                  receipt.claimedEventCount == claim.claimedEventCount,
                  receipt.generatedSHA256 == claim.generatedSHA256,
                  receipt.archivedByteCount == claim.claimedPrefixByteCount else {
                throw EnvironmentDocumentError.claimMismatch
            }
            if let successfulDigestAt = receipt.successfulDigestAt {
                guard let boundedTimestamp = boundedScheduleAnchorTimestamp(
                    successfulDigestAt,
                    relativeTo: now
                ) else {
                    throw EnvironmentDocumentError.claimMismatch
                }
                return boundedTimestamp
            }

            guard let successfulDigestAt = boundedScheduleAnchorTimestamp(
                now,
                relativeTo: now
            ) else {
                throw EnvironmentDocumentError.claimMismatch
            }
            var upgradedReceipt = receipt
            upgradedReceipt.successfulDigestAt = successfulDigestAt
            try environmentStore.saveDigestArchiveReceipt(upgradedReceipt)
            return successfulDigestAt
        }

        let receipt = EnvironmentDigestArchiveReceipt(
            claimedPrefixSHA256: claim.claimedPrefixSHA256,
            claimedPrefixByteCount: claim.claimedPrefixByteCount,
            claimedEventCount: claim.claimedEventCount,
            generatedSHA256: claim.generatedSHA256,
            archivedByteCount: claim.claimedPrefixByteCount,
            successfulDigestAt: now
        )
        try environmentStore.saveDigestArchiveReceipt(receipt)
        return now
    }

    private func boundedScheduleAnchorTimestamp(
        _ timestamp: Date,
        relativeTo now: Date
    ) -> Date? {
        guard timestamp.timeIntervalSince1970.isFinite,
              timestamp <= now.addingTimeInterval(maximumScheduleAnchorOffset) else {
            return nil
        }
        return timestamp
    }

    private func persistScheduleState(
        afterSuccessAt successfulDigestAt: Date,
        recoveryNow: Date
    ) throws {
        let tailInventory = try eventStore.inventory()
        let tailCount = tailInventory.eventCount
        let tailPendingSince = tailCount > 0
            ? Self.boundedPendingTimestamp(
                tailInventory.oldestEventTimestamp,
                noLaterThan: recoveryNow
            ) ?? recoveryNow
            : nil
        let history = successfulDigestHistory(
            adding: successfulDigestAt,
            relativeTo: recoveryNow
        )
        let latestSuccessAnchor = history.last ?? successfulDigestAt
        applyDigestSuccessState(
            at: latestSuccessAnchor,
            pendingTailCount: tailCount,
            pendingAnchor: tailPendingSince,
            successfulDigestTimestamps: history
        )
        try environmentStore.saveDigestScheduleState(
            EnvironmentDigestScheduleState(
                pendingSince: pendingSince,
                lastSuccessfulDigestAt: latestSuccessAnchor,
                nextEligibleAt: nextEligibleAt,
                pendingEventCount: tailCount,
                successfulDigestTimestamps: history
            )
        )
    }

    private func beginDigestClaimProtection(rawData: Data) -> UUID {
        let token = UUID()
        digestClaimProtection = DigestClaimProtection(token: token, rawData: rawData)
        return token
    }

    private func finishDigestClaimProcess(token: UUID) {
        guard var protection = digestClaimProtection,
              protection.token == token else { return }
        protection.processFinished = true
        finishDigestClaimProtectionIfComplete(protection)
    }

    private func finishDigestClaimAttempt(token: UUID) {
        guard var protection = digestClaimProtection,
              protection.token == token else { return }
        protection.attemptFinished = true
        finishDigestClaimProtectionIfComplete(protection)
    }

    private func finishDigestClaimProtectionIfComplete(_ protection: DigestClaimProtection) {
        if protection.processFinished, protection.attemptFinished {
            digestClaimProtection = nil
            scheduleClaimBlockedReevaluationIfNeeded()
        } else {
            digestClaimProtection = protection
        }
    }

    private func scheduleClaimBlockedReevaluationIfNeeded() {
        guard claimBlockedReevaluationRequested else { return }
        claimBlockedReevaluationRequested = false
        let pendingEventCount = (try? eventStore.inventory().eventCount) ?? 0
        guard claimRecoveryRetryAt == nil,
              gatePersistenceRetryAt == nil,
              pendingEventCount > 0 else { return }
        claimBlockedReevaluationScheduled = true
        scheduleCoalescedRerun()
    }

    private func emitAppendDiagnostics(_ result: TypingEventAppendResult) {
        if result.truncatedScalarCount > 0 {
            emitDiagnostic(stage: "context_event_truncated", fields: [.init(.eventCount, result.inventory.eventCount), .init(.byteCount, result.inventory.byteCount), .init(.truncatedScalarCount, result.truncatedScalarCount)])
        }
        if result.droppedEventCount > 0 || result.droppedByteCount > 0 {
            emitDiagnostic(stage: "context_backlog_trimmed", fields: [.init(.eventCount, result.inventory.eventCount), .init(.byteCount, result.inventory.byteCount), .init(.droppedCount, result.droppedEventCount)])
        }
    }

    private func emitDeferredDiagnostic(
        inventory: TypingEventInventory,
        cooldownRemaining: TimeInterval,
        reason: DigestDeferralReason
    ) {
        let deadline = nowProvider().addingTimeInterval(max(0, cooldownRemaining))
        let key = "\(reason.rawValue):\(Int(deadline.timeIntervalSince1970.rounded()))"
        guard deferredDiagnosticKey != key else { return }
        deferredDiagnosticKey = key
        emitDiagnostic(
            stage: "context_digest_deferred",
            fields: [
                .init(.eventCount, inventory.eventCount),
                .init(.byteCount, inventory.byteCount),
                .init(.probeCount, successfulDigestTimestamps.count),
                .init(.reason, reason.rawValue),
                .init(.cooldownRemainingSeconds, Int(ceil(cooldownRemaining)))
            ]
        )
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
