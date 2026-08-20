import CryptoKit
import Foundation
import KnowTypeCore
import KnowTypeProviders

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
    private struct GateWaitKey: Equatable {
        var identity: String
        var generation: UInt64
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
    private var providerIdentity = "context-digest"
    private var lastDigestAt: Date?
    private var pendingSince: Date?
    private var nextEligibleAt: Date?
    private var scheduleStateLoaded = false
    private var scheduleStateBlocked = false
    private var lastDigestFailureAt: Date?
    private var deferredDiagnosticFailureAt: Date?
    private var digestInFlight = false
    private var activeDigestClaimRawData: Data?
    private var providerGeneration: UInt64?
    private var deadlineTask: Task<Void, Never>?
    private var gateWaitKey: GateWaitKey?

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
        self.minimumInterval = max(1, minimumInterval)
        self.requestGate = requestGate
        self.nowProvider = nowProvider
        self.hardTimeoutNanoseconds = UInt64(AIRecommendationRuntime.Defaults.hardTimeoutMilliseconds) * 1_000_000
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
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.provider = provider
        self.providerRegistry = nil
        self.eventStore = eventStore
        self.environmentStore = environmentStore
        self.batchSize = max(1, batchSize)
        self.minimumInterval = max(1, minimumInterval)
        self.requestGate = requestGate
        self.nowProvider = nowProvider
        self.hardTimeoutNanoseconds = UInt64(max(1, hardTimeoutMilliseconds)) * 1_000_000
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
        self.minimumInterval = max(1, minimumInterval)
        self.requestGate = providerRegistry.requestGate
        self.nowProvider = nowProvider
        self.hardTimeoutNanoseconds = UInt64(AIRecommendationRuntime.Defaults.hardTimeoutMilliseconds) * 1_000_000
        self.diagnosticSink = { InputDebugDiagnostics.emit(category: .ai, fields: $0) }
    }

    public func record(_ event: AITypingEvent) async {
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
        guard gateWaitKey == nil,
              !digestInFlight,
              provider != nil || providerRegistry != nil else { return }
        digestInFlight = true
        defer {
            activeDigestClaimRawData = nil
            digestInFlight = false
        }

        loadScheduleStateIfNeeded(now: now)
        guard !scheduleStateBlocked else { return }

        switch await recoverDigestClaim(now: now) {
        case .recovered, .blocked:
            return
        case .none:
            break
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

        let localCooldown = digestCooldownRemaining(at: now)
        let gateCooldown = await requestGate.cooldownDeadline(
            providerIdentity: providerIdentity,
            generation: providerGeneration ?? 0
        )
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
            let timeout = hardTimeoutNanoseconds
            let registry = providerRegistry
            providerGateStarted = true
            let gated: (LLMResponse, String) = try await withTimeout(nanoseconds: timeout) {
                try await requestGate.execute(
                    providerIdentity: requestIdentity,
                    generation: requestGeneration
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
            }
            _ = gated.0
            providerGateCompleted = true
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
            try environmentStore.saveDigestClaim(claim)
            let persist: @Sendable () throws -> TypingEventArchiveResult = {
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
                result = try await providerRegistry.commitIfCurrent(using: lease, operation: persist)
            } else {
                result = try persist()
            }
            try environmentStore.clearDigestClaim()
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
            return
        } catch TypingEventStoreError.pendingContentChanged {
            return
        } catch EnvironmentDocumentError.invalidDigestCandidate {
            markDigestFailure(at: now)
        } catch let error as TimeoutError {
            markDigestFailure(at: now)
            await requestGate.recordFailure(
                providerIdentity: requestIdentity,
                generation: requestGeneration,
                failure: error
            )
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

    private enum DigestClaimRecovery {
        case none
        case recovered
        case blocked
    }

    private func recoverDigestClaim(now: Date) async -> DigestClaimRecovery {
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
                if let snapshot = try? eventStore.pendingDigestSnapshot(
                    prefixByteCount: claim.claimedPrefixByteCount,
                    eventCount: claim.claimedEventCount
                ), Self.sha256(snapshot.rawData) == claim.claimedPrefixSHA256 {
                    try eventStore.archivePendingEvents(matching: snapshot)
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

    private func applyProviderLease(_ lease: ProviderRuntimeLease) {
        let changed = providerGeneration != lease.generation || providerIdentity != lease.fingerprint
        providerGeneration = lease.generation
        providerIdentity = lease.fingerprint
        if changed {
            cancelGateAvailabilityWait()
            lastDigestFailureAt = nil
            deferredDiagnosticFailureAt = nil
        }
    }

    private func invalidateProviderRuntimeState() {
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
        gateWaitKey = nil
        deadlineTask?.cancel()
        let delay = max(0, date.timeIntervalSince(nowProvider()))
        deadlineTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled, let self else { return }
            await self.processIfNeeded(now: self.nowProvider())
        }
    }

    private func scheduleGateAvailabilityWake() {
        let key = GateWaitKey(
            identity: providerIdentity,
            generation: providerGeneration ?? 0
        )
        if gateWaitKey == key, deadlineTask != nil { return }
        deadlineTask?.cancel()
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
        gateWaitKey = nil
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
