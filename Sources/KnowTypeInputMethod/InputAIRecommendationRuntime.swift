import Foundation
import KnowTypeAI
import KnowTypeCore

struct InputAIRecommendationRuntimeContext: Sendable {
    var rawInput: String
    var hasResolvedSegments: Bool
    var isFullyResolved: Bool
    var lockedPrefix: String?
    var cloudContinuationEnabled: Bool
    var canRequestAIRecommendations: Bool
    var hasRecommendationProvider: Bool
    var isProviderAvailabilityProbe: Bool
    var appBundleID: String?
    var locale: KnowTypeLocale
    var compositionID: Int
    var rawRevision: Int
    var lexicalContext: LexicalContextSnapshot?
    var feedbackContext: AIAcceptedFeedbackContextSnapshot?
}

struct InputAIRecommendationRuntimeCompositionSnapshot: Sendable, Equatable {
    var compositionID: Int
    var rawRevision: Int
    var rawInput: String
}

final class InputAIRecommendationRuntime: @unchecked Sendable {
    typealias SnapshotProvider = @MainActor @Sendable () -> InputAIRecommendationRuntimeCompositionSnapshot?
    typealias StateChangeHandler = @MainActor @Sendable (AIRecommendationState) -> Void

    enum Defaults {
        static let dispatchDebounceMilliseconds = 450
    }

    private enum FSMState: Equatable {
        case idle
        case debouncing
        case inFlight
        case trailing
    }

    private struct Work: @unchecked Sendable {
        var context: InputAIRecommendationRuntimeContext
        var request: AIRecommendationRequest
        var currentSnapshot: SnapshotProvider
        var onStateChange: StateChangeHandler
        var requestID: UUID
        var generation: Int
        var scheduledAt: Date
    }

    private let provider: (any AIRecommendationProviding)?
    private let providerAvailability: (any AIRecommendationProviderAvailabilitySnapshotting)?
    private let schedulePolicy: InputAIRecommendationSchedulePolicy
    private let diagnosticSink: any AIRecommendationDiagnosticSink
    private let hasEagerProvider: Bool
    private let dispatchDebounceNanoseconds: UInt64
    private var state: FSMState = .idle
    private var generation = 0
    private var activeWork: Work?
    private var trailingWork: Work?
    private var deferredTask: Task<Void, Never>?
    private var transportTask: Task<Void, Never>?

    init(
        provider: (any AIRecommendationProviding)?,
        providerAvailability: (any AIRecommendationProviderAvailabilitySnapshotting)?,
        hasEagerProvider: Bool,
        schedulePolicy: InputAIRecommendationSchedulePolicy = .default,
        dispatchDebounceMilliseconds: Int = Defaults.dispatchDebounceMilliseconds,
        diagnosticSink: any AIRecommendationDiagnosticSink = OSLogAIRecommendationDiagnosticSink()
    ) {
        self.provider = provider
        self.providerAvailability = providerAvailability
        self.hasEagerProvider = hasEagerProvider
        self.schedulePolicy = schedulePolicy
        self.dispatchDebounceNanoseconds = UInt64(max(0, dispatchDebounceMilliseconds)) * 1_000_000
        self.diagnosticSink = diagnosticSink
    }

    var hasKnownProvider: Bool { hasEagerProvider || providerAvailability?.providerAvailability == .available }

    var shouldBuildRecommendationContext: Bool {
        guard provider != nil else { return false }
        if hasEagerProvider { return true }
        guard let providerAvailability else { return true }
        return providerAvailability.providerAvailability != .unavailable
    }

    var shouldScheduleRecommendationRequest: Bool { provider != nil }

    @discardableResult
    func schedule(
        context: InputAIRecommendationRuntimeContext,
        currentSnapshot: @escaping SnapshotProvider,
        onStateChange: @escaping StateChangeHandler
    ) -> AIRecommendationState {
        let requestID = UUID()
        let decision = schedulePolicy.decision(
            for: InputAIRecommendationScheduleContext(
                rawInput: context.rawInput,
                hasResolvedSegments: context.hasResolvedSegments,
                isFullyResolved: context.isFullyResolved,
                lockedPrefix: context.lockedPrefix,
                cloudContinuationEnabled: context.cloudContinuationEnabled,
                canRequestAIRecommendations: context.canRequestAIRecommendations,
                hasRecommendationProvider: context.hasRecommendationProvider
            )
        )
        if case .skip(let skip) = decision {
            cancelDeferredOnly(context: context, reason: "new_schedule")
            trailingWork = nil
            generation += 1
            record(skip.diagnosticStage, requestID: requestID, context: context, reason: skip.reason)
            return skip.state
        }
        guard let provider else {
            record(.skippedNoProvider, requestID: requestID, context: context, reason: "recommendation_provider_missing")
            return .idle
        }

        cancelDeferredOnly(context: context, reason: "new_schedule")
        generation += 1
        let work = Work(
            context: context,
            request: AIRecommendationRequest(
                rawInput: context.rawInput,
                lockedPrefix: context.lockedPrefix,
                candidateHints: [],
                appBundleID: context.appBundleID,
                appName: context.appBundleID,
                locale: context.locale,
                compositionID: context.compositionID,
                requestID: requestID,
                lexicalContext: context.lexicalContext,
                feedbackContext: context.feedbackContext
            ),
            currentSnapshot: currentSnapshot,
            onStateChange: onStateChange,
            requestID: requestID,
            generation: generation,
            scheduledAt: Date()
        )
        record(.scheduled, requestID: requestID, context: context)
        if !context.isProviderAvailabilityProbe {
            record(.pendingPlaceholder, requestID: requestID, context: context, reason: "waiting_for_stable_input")
        }

        if transportTask != nil, activeWork != nil {
            markTransportStale(context: context, requestID: activeWork!.requestID, reason: "new_schedule")
            trailingWork = work
            state = .trailing
            return context.isProviderAvailabilityProbe ? .idle : .pending(requestID: requestID)
        }

        activeWork = work
        state = .debouncing
        startDeferred(work: work, provider: provider)
        return context.isProviderAvailabilityProbe ? .idle : .pending(requestID: requestID)
    }

    private func startDeferred(work: Work, provider: any AIRecommendationProviding) {
        let delay = dispatchDebounceNanoseconds
        deferredTask = Task.detached(priority: .utility) { [weak self, diagnosticSink] in
            if delay > 0 {
                diagnosticSink.record(AIRecommendationDiagnosticEvent(stage: .dispatchDeferred, requestID: work.requestID, compositionID: work.context.compositionID, rawLength: work.context.rawInput.count, rawRevision: work.context.rawRevision, prefixLength: work.context.lockedPrefix?.count, appBundleID: work.context.appBundleID, reason: "waiting_for_stable_input"))
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
            }
            guard let self else { return }
            await MainActor.run { [weak self] in
                guard let self,
                      self.activeWork?.requestID == work.requestID,
                      self.generation == work.generation else { return }
                self.deferredTask = nil
                self.beginTransport(work: work, provider: provider)
            }
        }
    }

    private func beginTransport(work: Work, provider: any AIRecommendationProviding) {
        state = .inFlight
        diagnosticSink.record(AIRecommendationDiagnosticEvent(stage: .transportStarted, requestID: work.requestID, compositionID: work.context.compositionID, rawLength: work.context.rawInput.count, rawRevision: work.context.rawRevision, prefixLength: work.context.lockedPrefix?.count, appBundleID: work.context.appBundleID, elapsedMilliseconds: elapsedMilliseconds(since: work.scheduledAt)))
        let transportStartedAt = Date()
        transportTask = Task.detached(priority: .utility) { [weak self, provider, diagnosticSink] in
            let result = await provider.recommendation(for: work.request)
            let elapsed = Self.elapsedMilliseconds(since: transportStartedAt)
            await MainActor.run { [weak self] in
                self?.finishTransport(work: work, state: result, elapsedMilliseconds: elapsed)
            }
            _ = diagnosticSink
        }
    }

    private func finishTransport(work: Work, state result: AIRecommendationState, elapsedMilliseconds: Int) {
        transportTask = nil
        let isCurrent = activeWork?.requestID == work.requestID && generation == work.generation
        if case .stale = result {
            if activeWork?.requestID == work.requestID { activeWork = nil }
            record(.staleResultDropped, requestID: work.requestID, context: work.context, elapsedMilliseconds: elapsedMilliseconds, reason: "provider_generation_changed")
            dispatchTrailingIfNeeded()
            return
        }
        guard isCurrent, let snapshot = work.currentSnapshot() else {
            if activeWork?.requestID == work.requestID { activeWork = nil }
            record(.staleResultDropped, requestID: work.requestID, context: work.context, elapsedMilliseconds: elapsedMilliseconds, reason: activeWork == nil ? "coordinator_released" : "request_inactive")
            dispatchTrailingIfNeeded()
            return
        }
        guard snapshot.compositionID == work.context.compositionID,
              snapshot.rawRevision == work.context.rawRevision,
              snapshot.rawInput == work.context.rawInput else {
            activeWork = nil
            record(.staleResultDropped, requestID: work.requestID, context: work.context, elapsedMilliseconds: elapsedMilliseconds, reason: "snapshot_mismatch")
            dispatchTrailingIfNeeded()
            return
        }
        activeWork = nil
        if work.context.isProviderAvailabilityProbe,
           !Self.shouldApplyProviderAvailabilityProbeState(result) {
            record(.stateApplied, requestID: work.requestID, context: work.context, elapsedMilliseconds: elapsedMilliseconds, reason: "availability_probe_suppressed_\(Self.diagnosticReason(for: result))")
        } else {
            record(.stateApplied, requestID: work.requestID, context: work.context, elapsedMilliseconds: elapsedMilliseconds, reason: Self.diagnosticReason(for: result))
            work.onStateChange(result)
        }
        dispatchTrailingIfNeeded()
    }

    private func dispatchTrailingIfNeeded() {
        guard transportTask == nil, let next = trailingWork, let provider else {
            state = activeWork == nil ? .idle : state
            return
        }
        trailingWork = nil
        activeWork = next
        state = .trailing
        beginTransport(work: next, provider: provider)
    }

    @discardableResult
    func reset(compositionID: Int?, rawLength: Int?, reason: String) -> AIRecommendationState {
        cancelActiveForDiagnostics(compositionID: compositionID, rawLength: rawLength, reason: reason)
        generation += 1
        deferredTask?.cancel()
        deferredTask = nil
        trailingWork = nil
        if transportTask == nil { activeWork = nil; state = .idle }
        return .idle
    }

    func cancelActiveForDiagnostics(compositionID: Int?, rawLength: Int?, reason: String) {
        guard let work = activeWork else {
            deferredTask?.cancel()
            deferredTask = nil
            trailingWork = nil
            return
        }
        record(.cancelPrevious, requestID: work.requestID, compositionID: compositionID, rawLength: rawLength, reason: reason)
        if transportTask != nil {
            markTransportStale(context: work.context, requestID: work.requestID, reason: reason)
            generation += 1
        } else {
            deferredTask?.cancel()
            deferredTask = nil
            record(.dispatchCancelledByNewInput, requestID: work.requestID, compositionID: compositionID, rawLength: rawLength, reason: "debounce_cancelled_by_new_input")
            activeWork = nil
            state = .idle
        }
        trailingWork = nil
    }

    private func cancelDeferredOnly(context: InputAIRecommendationRuntimeContext, reason: String) {
        guard transportTask == nil, let work = activeWork else { return }
        deferredTask?.cancel()
        deferredTask = nil
        record(.dispatchCancelledByNewInput, requestID: work.requestID, context: context, reason: reason)
        activeWork = nil
        state = .idle
    }

    private func markTransportStale(context: InputAIRecommendationRuntimeContext, requestID: UUID, reason: String) {
        record(.transportLeftStale, requestID: requestID, context: context, reason: reason)
        activeWork = activeWork
    }

    private func record(
        _ stage: AIRecommendationDiagnosticStage,
        requestID: UUID? = nil,
        context: InputAIRecommendationRuntimeContext? = nil,
        compositionID: Int? = nil,
        rawLength: Int? = nil,
        rawRevision: Int? = nil,
        prefixLength: Int? = nil,
        appBundleID: String? = nil,
        elapsedMilliseconds: Int? = nil,
        reason: String? = nil
    ) {
        let context = context
        diagnosticSink.record(AIRecommendationDiagnosticEvent(
            stage: stage,
            requestID: requestID,
            compositionID: compositionID ?? context?.compositionID,
            rawLength: rawLength ?? context?.rawInput.count,
            rawRevision: rawRevision ?? context?.rawRevision,
            prefixLength: prefixLength ?? context?.lockedPrefix?.count,
            appBundleID: appBundleID ?? context?.appBundleID,
            elapsedMilliseconds: elapsedMilliseconds,
            reason: reason
        ))
    }

    private func elapsedMilliseconds(since start: Date) -> Int { max(0, Int(Date().timeIntervalSince(start) * 1_000)) }

    private static func elapsedMilliseconds(since start: Date) -> Int { max(0, Int(Date().timeIntervalSince(start) * 1_000)) }

    private static func diagnosticReason(for state: AIRecommendationState) -> String {
        switch state {
        case .idle: return "idle"
        case .stale: return "provider_generation_changed"
        case .pending: return "pending"
        case .ready: return "ready"
        case .ineligible(let reason): return "ineligible:\(reason)"
        case .unavailable(let reason): return "unavailable:\(reason)"
        }
    }

    private static func shouldApplyProviderAvailabilityProbeState(_ state: AIRecommendationState) -> Bool {
        if case .ready = state { return true }
        return false
    }
}
