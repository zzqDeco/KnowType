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
        guard let provider = providerLoader() else {
            return
        }
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
    private var lastDigestAt: Date?
    private var lastDigestFailureAt: Date?
    private var deferredDiagnosticFailureAt: Date?
    private var digestInFlight = false
    private var activeDigestClaimRawData: Data?
    private var providerGeneration: UInt64?

    public init(
        provider: (any LLMProvider)?,
        eventStore: TypingEventStore = TypingEventStore(),
        environmentStore: EnvironmentDocumentStore = EnvironmentDocumentStore(),
        batchSize: Int = 50,
        minimumInterval: TimeInterval = 600
    ) {
        self.provider = provider
        self.providerRegistry = nil
        self.eventStore = eventStore
        self.environmentStore = environmentStore
        self.batchSize = max(1, batchSize)
        self.minimumInterval = max(1, minimumInterval)
        self.diagnosticSink = {
            InputDebugDiagnostics.emit(category: .ai, fields: $0)
        }
    }

    init(
        provider: (any LLMProvider)?,
        eventStore: TypingEventStore,
        environmentStore: EnvironmentDocumentStore,
        batchSize: Int,
        minimumInterval: TimeInterval,
        diagnosticSink: @escaping @Sendable ([InputDebugDiagnostics.Field]) -> Void
    ) {
        self.provider = provider
        self.providerRegistry = nil
        self.eventStore = eventStore
        self.environmentStore = environmentStore
        self.batchSize = max(1, batchSize)
        self.minimumInterval = max(1, minimumInterval)
        self.diagnosticSink = diagnosticSink
    }

    public init(
        providerRegistry: ProviderRuntimeRegistry,
        eventStore: TypingEventStore = TypingEventStore(),
        environmentStore: EnvironmentDocumentStore = EnvironmentDocumentStore(),
        batchSize: Int = 50,
        minimumInterval: TimeInterval = 600
    ) {
        self.provider = nil
        self.providerRegistry = providerRegistry
        self.eventStore = eventStore
        self.environmentStore = environmentStore
        self.batchSize = max(1, batchSize)
        self.minimumInterval = max(1, minimumInterval)
        self.diagnosticSink = {
            InputDebugDiagnostics.emit(category: .ai, fields: $0)
        }
    }

    public func record(_ event: AITypingEvent) async {
        let dispatchLease: ProviderRuntimeLease?
        if let providerRegistry {
            let lease = await providerRegistry.leaseForEligibleDispatch()
            guard lease.provider != nil else {
                return
            }
            applyProviderLease(lease)
            dispatchLease = lease
        } else {
            dispatchLease = nil
        }
        do {
            let appendResult = try eventStore.appendBounded(
                sanitized(event),
                preservingClaimedPrefix: activeDigestClaimRawData
            )
            emitAppendDiagnostics(appendResult)
            await processIfNeeded(now: Date(), dispatchLease: dispatchLease)
        } catch {
            return
        }
    }

    public func processIfNeeded(now: Date = Date()) async {
        await processIfNeeded(now: now, dispatchLease: nil)
    }

    private func processIfNeeded(
        now: Date,
        dispatchLease: ProviderRuntimeLease?
    ) async {
        guard !digestInFlight,
              provider != nil || providerRegistry != nil else {
            return
        }
        digestInFlight = true
        defer {
            activeDigestClaimRawData = nil
            digestInFlight = false
        }

        let inventory: TypingEventInventory
        do {
            inventory = try eventStore.inventory()
        } catch {
            return
        }
        guard inventory.eventCount > 0 else {
            return
        }
        if lastDigestAt == nil, inventory.eventCount < batchSize {
            lastDigestAt = now
            return
        }
        let intervalElapsed = lastDigestAt.map { now.timeIntervalSince($0) >= minimumInterval } ?? false
        guard inventory.eventCount >= batchSize || intervalElapsed else {
            return
        }
        if inventory.isProtectedOnly {
            do {
                let snapshot = try eventStore.pendingFullSnapshot()
                try eventStore.archivePendingEvents(matching: snapshot)
                lastDigestAt = now
            } catch {
                return
            }
            return
        }

        let lease: ProviderRuntimeLease?
        let activeProvider: (any LLMProvider)?
        if let providerRegistry {
            let loadedLease: ProviderRuntimeLease
            if let dispatchLease {
                loadedLease = dispatchLease
            } else {
                loadedLease = await providerRegistry.leaseForEligibleDispatch()
            }
            applyProviderLease(loadedLease)
            lease = loadedLease
            activeProvider = loadedLease.provider
        } else {
            lease = nil
            activeProvider = provider
        }
        guard let activeProvider else {
            return
        }
        if let cooldownRemaining = digestCooldownRemaining(at: now) {
            emitDeferredDiagnostic(
                inventory: inventory,
                cooldownRemaining: cooldownRemaining
            )
            return
        }

        let snapshot: TypingEventSnapshot
        do {
            snapshot = try eventStore.pendingDigestSnapshot()
        } catch {
            return
        }
        guard !snapshot.rawData.isEmpty else {
            return
        }
        guard snapshot.claimedEventCount > 0, !snapshot.events.isEmpty else {
            do {
                try eventStore.archivePendingEvents(matching: snapshot)
            } catch {
                return
            }
            return
        }
        if snapshot.events.allSatisfy(TypingEventStore.isProtectedOnlyEvent) {
            do {
                try eventStore.archivePendingEvents(matching: snapshot)
                lastDigestAt = now
            } catch {
                return
            }
            return
        }
        let rawEvents = snapshot.requestContent
        guard !rawEvents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastDigestAt = now
            return
        }

        do {
            let currentEnvironment = try environmentStore.loadSnapshot()
            let request = LLMRequest(
                task: .contextDigest,
                rawInput: rawEvents,
                locale: .mixed,
                appContext: "KnowTypeContextMemory",
                maxCandidates: 1,
                contextDocuments: [
                    "ENV.md": currentEnvironment.content
                ]
            )
            activeDigestClaimRawData = snapshot.rawData
            let response: LLMResponse
            if let providerRegistry, let lease {
                response = try await providerRegistry.perform(using: lease) { provider in
                    try await provider.complete(request)
                }
            } else {
                response = try await activeProvider.complete(request)
            }
            guard let generated = Self.generatedDigestText(from: response) else {
                markDigestFailure(at: now)
                return
            }
            let eventStore = self.eventStore
            let environmentStore = self.environmentStore
            let persist: @Sendable () throws -> TypingEventArchiveResult = {
                try eventStore.commitPendingEvents(matching: snapshot) {
                    _ = try environmentStore.replaceGeneratedSection(with: generated)
                }
            }
            let archiveResult: TypingEventArchiveResult
            if let providerRegistry, let lease {
                archiveResult = try await providerRegistry.commitIfCurrent(using: lease, operation: persist)
            } else {
                archiveResult = try persist()
            }
            lastDigestAt = now
            lastDigestFailureAt = nil
            deferredDiagnosticFailureAt = nil
            emitArchiveDiagnostic(archiveResult)
        } catch ProviderRuntimeRegistryError.staleGeneration {
            invalidateProviderRuntimeState()
            return
        } catch TypingEventStoreError.pendingContentChanged {
            return
        } catch {
            markDigestFailure(at: now)
            return
        }
    }

    private func applyProviderLease(_ lease: ProviderRuntimeLease) {
        guard providerGeneration != lease.generation else {
            return
        }
        lastDigestAt = nil
        lastDigestFailureAt = nil
        deferredDiagnosticFailureAt = nil
        providerGeneration = lease.generation
    }

    private func invalidateProviderRuntimeState() {
        lastDigestAt = nil
        lastDigestFailureAt = nil
        deferredDiagnosticFailureAt = nil
        providerGeneration = nil
    }

    private func markDigestFailure(at now: Date) {
        lastDigestFailureAt = now
        deferredDiagnosticFailureAt = nil
    }

    private func digestCooldownRemaining(at now: Date) -> TimeInterval? {
        guard let lastDigestFailureAt else {
            return nil
        }
        let remaining = minimumInterval - now.timeIntervalSince(lastDigestFailureAt)
        return remaining > 0 ? remaining : nil
    }

    private func emitAppendDiagnostics(_ result: TypingEventAppendResult) {
        if result.truncatedScalarCount > 0 {
            emitDiagnostic(
                stage: "context_event_truncated",
                fields: [
                    .init(.eventCount, result.inventory.eventCount),
                    .init(.byteCount, result.inventory.byteCount),
                    .init(.truncatedScalarCount, result.truncatedScalarCount)
                ]
            )
        }
        if result.droppedEventCount > 0 || result.droppedByteCount > 0 {
            emitDiagnostic(
                stage: "context_backlog_trimmed",
                fields: [
                    .init(.eventCount, result.inventory.eventCount),
                    .init(.byteCount, result.inventory.byteCount),
                    .init(.droppedCount, result.droppedEventCount)
                ]
            )
        }
    }

    private func emitDeferredDiagnostic(
        inventory: TypingEventInventory,
        cooldownRemaining: TimeInterval
    ) {
        guard deferredDiagnosticFailureAt != lastDigestFailureAt else {
            return
        }
        deferredDiagnosticFailureAt = lastDigestFailureAt
        emitDiagnostic(
            stage: "context_digest_deferred",
            fields: [
                .init(.eventCount, inventory.eventCount),
                .init(.byteCount, inventory.byteCount),
                .init(.cooldownRemainingSeconds, Int(ceil(cooldownRemaining)))
            ]
        )
    }

    private func emitArchiveDiagnostic(_ result: TypingEventArchiveResult) {
        guard result.deletedFileCount > 0 else {
            return
        }
        emitDiagnostic(
            stage: "context_archive_pruned",
            fields: [
                .init(.byteCount, result.deletedByteCount),
                .init(.deletedFileCount, result.deletedFileCount)
            ]
        )
    }

    private func emitDiagnostic(
        stage: String,
        fields: [InputDebugDiagnostics.Field]
    ) {
        diagnosticSink(
            [
                .init(.stage, stage),
                .init(.providerGeneration, providerGeneration ?? 0)
            ] + fields
        )
    }

    private static func generatedDigestText(from response: LLMResponse) -> String? {
        let parts = response.candidates
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            return nil
        }
        return parts.joined(separator: "\n")
    }

    private func sanitized(_ event: AITypingEvent) -> AITypingEvent {
        var event = event
        if event.commitKind == .externalDelete,
           event.rawInput == nil,
           event.committedText == nil,
           TextProtection.requiresNoCorrection("knowtype", appBundleID: event.appBundleID) {
            event.rawInput = "protected:delete"
            event.committedText = "protected:delete"
            event.candidateSource = "protected"
            return event
        }
        if let rawInput = event.rawInput,
           TextProtection.requiresNoCorrection(rawInput, appBundleID: event.appBundleID) {
            event.rawInput = protectedLabel(for: rawInput)
            event.committedText = event.rawInput
            event.candidateSource = "protected"
        }
        if let committedText = event.committedText,
           TextProtection.requiresNoCorrection(committedText, appBundleID: event.appBundleID) {
            event.committedText = protectedLabel(for: committedText)
            event.candidateSource = "protected"
        }
        return event
    }

    private func protectedLabel(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") {
            return "protected:url"
        }
        if trimmed.contains("/") {
            return "protected:path"
        }
        if trimmed.contains("@") {
            return "protected:email"
        }
        return "protected:command"
    }
}
