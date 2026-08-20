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
    private let provider: (any LLMProvider)?
    private let providerRegistry: ProviderRuntimeRegistry?
    private let eventStore: TypingEventStore
    private let environmentStore: EnvironmentDocumentStore
    private let batchSize: Int
    private let minimumInterval: TimeInterval
    private let diagnosticSink: @Sendable ([InputDebugDiagnostics.Field]) -> Void
    private let requestGate: ProviderRequestGate
    private let nowProvider: @Sendable () -> Date
    private var providerIdentity = "context-digest"
    private var lastDigestAt: Date?
    private var lastDigestFailureAt: Date?
    private var deferredDiagnosticFailureAt: Date?
    private var digestInFlight = false
    private var activeDigestClaimRawData: Data?
    private var providerGeneration: UInt64?
    private var deadlineTask: Task<Void, Never>?

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
        self.providerIdentity = providerIdentity ?? provider?.providerName ?? "context-digest"
        self.diagnosticSink = { InputDebugDiagnostics.emit(category: .ai, fields: $0) }
    }

    init(
        provider: (any LLMProvider)?,
        eventStore: TypingEventStore,
        environmentStore: EnvironmentDocumentStore,
        batchSize: Int,
        minimumInterval: TimeInterval,
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
        guard !digestInFlight, provider != nil || providerRegistry != nil else { return }
        digestInFlight = true
        defer {
            activeDigestClaimRawData = nil
            digestInFlight = false
        }

        switch await recoverDigestClaim(now: now) {
        case .recovered, .blocked:
            return
        case .none:
            break
        }

        let inventory: TypingEventInventory
        do { inventory = try eventStore.inventory() } catch { return }
        guard inventory.eventCount > 0 else { cancelDeadline(); return }

        if inventory.isProtectedOnly {
            do {
                let snapshot = try eventStore.pendingFullSnapshot()
                try eventStore.archivePendingEvents(matching: snapshot)
                recordDigestSuccess(at: now)
            } catch { return }
            return
        }

        let intervalElapsed: Bool
        if let lastDigestAt {
            intervalElapsed = now.timeIntervalSince(lastDigestAt) >= minimumInterval
        } else {
            intervalElapsed = inventory.eventCount >= batchSize
        }
        guard intervalElapsed else {
            scheduleDeadline(at: (lastDigestAt ?? now).addingTimeInterval(minimumInterval))
            emitDiagnostic(
                stage: "context_digest_deferred",
                fields: [
                    .init(.eventCount, inventory.eventCount),
                    .init(.byteCount, inventory.byteCount),
                    .init(.deadline, Int(ceil((lastDigestAt ?? now).addingTimeInterval(minimumInterval).timeIntervalSince(now))))
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
            do { try eventStore.archivePendingEvents(matching: snapshot) } catch { return }
            return
        }
        if snapshot.events.allSatisfy(TypingEventStore.isProtectedOnlyEvent) {
            do { try eventStore.archivePendingEvents(matching: snapshot); lastDigestAt = now } catch { return }
            return
        }
        guard !snapshot.requestContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            try? eventStore.archivePendingEvents(matching: snapshot)
            return
        }

        var providerGateStarted = false
        var providerGateCompleted = false
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
            let identity = providerIdentity
            let generation = providerGeneration ?? 0
            providerGateStarted = true
            let gated: (LLMResponse, String) = try await requestGate.execute(
                providerIdentity: identity,
                generation: generation
            ) {
                let response: LLMResponse
                if let providerRegistry, let lease {
                    response = try await providerRegistry.perform(using: lease) { provider in
                        try await withTimeout(
                            nanoseconds: UInt64(AIRecommendationRuntime.Defaults.hardTimeoutMilliseconds) * 1_000_000
                        ) {
                            try await provider.complete(request)
                        }
                    }
                } else {
                    response = try await withTimeout(
                        nanoseconds: UInt64(AIRecommendationRuntime.Defaults.hardTimeoutMilliseconds) * 1_000_000
                    ) {
                        try await activeProvider.complete(request)
                    }
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
            let generated = gated.1
            let claim = EnvironmentDigestClaim(
                claimedPrefixSHA256: Self.sha256(snapshot.rawData),
                claimedPrefixByteCount: snapshot.rawData.count,
                claimedEventCount: snapshot.claimedEventCount,
                generatedSHA256: AIDocumentSnapshot.hash(
                    generated.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                providerGeneration: generation
            )
            try environmentStore.saveDigestClaim(claim)
            let persist: @Sendable () throws -> TypingEventArchiveResult = {
                _ = try environmentStore.replaceGeneratedSection(with: generated)
                return try eventStore.commitPendingEvents(matching: snapshot, beforeArchive: {})
            }
            let result: TypingEventArchiveResult
            if let providerRegistry, let lease {
                result = try await providerRegistry.commitIfCurrent(using: lease, operation: persist)
            } else {
                result = try persist()
            }
            try environmentStore.clearDigestClaim()
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
            return
        } catch TypingEventStoreError.pendingContentChanged {
            return
        } catch EnvironmentDocumentError.invalidDigestCandidate {
            markDigestFailure(at: now)
        } catch {
            if error is CancellationError { return }
            markDigestFailure(at: now)
            if providerGateCompleted {
                await requestGate.recordLocalCommitFailure(
                    providerIdentity: providerIdentity,
                    generation: providerGeneration ?? 0
                )
            } else if !providerGateStarted {
                await requestGate.recordLocalCommitFailure(
                    providerIdentity: providerIdentity,
                    generation: providerGeneration ?? 0
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
        guard let claim else { return .none }
        do {
            let environment = try environmentStore.loadSnapshot()
            guard EnvironmentDocumentStore.generatedSectionHash(from: environment.content) == claim.generatedSHA256 else {
                try environmentStore.clearDigestClaim()
                return .none
            }
            let snapshot = try eventStore.pendingDigestSnapshot(
                prefixByteCount: claim.claimedPrefixByteCount,
                eventCount: claim.claimedEventCount
            )
            guard Self.sha256(snapshot.rawData) == claim.claimedPrefixSHA256 else {
                return .blocked
            }
            try eventStore.archivePendingEvents(matching: snapshot)
            try environmentStore.clearDigestClaim()
            recordDigestSuccess(at: now)
            return .recovered
        } catch {
            return .blocked
        }
    }

    private func applyProviderLease(_ lease: ProviderRuntimeLease) {
        providerGeneration = lease.generation
        providerIdentity = lease.fingerprint
    }

    private func invalidateProviderRuntimeState() {
        providerGeneration = nil
        providerIdentity = "context-digest"
    }

    private func recordDigestSuccess(at now: Date) {
        lastDigestAt = now
        lastDigestFailureAt = nil
        deferredDiagnosticFailureAt = nil
        let hasPendingTail: Bool
        do {
            hasPendingTail = try eventStore.inventory().eventCount > 0
        } catch {
            hasPendingTail = true
        }
        if hasPendingTail {
            scheduleDeadline(at: now.addingTimeInterval(minimumInterval))
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
        deadlineTask?.cancel()
        let delay = max(0, date.timeIntervalSince(nowProvider()))
        deadlineTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled, let self else { return }
            await self.processIfNeeded(now: self.nowProvider())
        }
    }

    private func cancelDeadline() {
        deadlineTask?.cancel()
        deadlineTask = nil
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
