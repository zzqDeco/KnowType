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
        static let dispatchDebounceMilliseconds = 850
    }

    private enum ActiveRequestPhase: Equatable {
        case dispatchDeferred
        case transportStarted
    }

    private let provider: (any AIRecommendationProviding)?
    private let providerAvailability: (any AIRecommendationProviderAvailabilitySnapshotting)?
    private let schedulePolicy: InputAIRecommendationSchedulePolicy
    private let diagnosticSink: any AIRecommendationDiagnosticSink
    private let hasEagerProvider: Bool
    private let dispatchDebounceNanoseconds: UInt64
    private var activeTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var activeRequestPhase: ActiveRequestPhase?
    private var generation = 0

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

    var hasKnownProvider: Bool {
        hasEagerProvider || providerAvailability?.providerAvailability == .available
    }

    var shouldBuildRecommendationContext: Bool {
        guard provider != nil else {
            return false
        }
        if hasEagerProvider {
            return true
        }
        guard let providerAvailability else {
            return true
        }
        switch providerAvailability.providerAvailability {
        case .unknown, .available:
            return true
        case .unavailable:
            return false
        }
    }

    var shouldScheduleRecommendationRequest: Bool {
        provider != nil
    }

    @discardableResult
    func schedule(
        context: InputAIRecommendationRuntimeContext,
        currentSnapshot: @escaping SnapshotProvider,
        onStateChange: @escaping StateChangeHandler
    ) -> AIRecommendationState {
        if let cancelledRequestID = activeRequestID {
            record(
                .cancelPrevious,
                requestID: cancelledRequestID,
                compositionID: context.compositionID,
                rawLength: context.rawInput.count,
                rawRevision: context.rawRevision,
                appBundleID: context.appBundleID,
                reason: "new_schedule"
            )
            switch activeRequestPhase {
            case .dispatchDeferred:
                activeTask?.cancel()
                record(
                    .dispatchCancelledByNewInput,
                    requestID: cancelledRequestID,
                    compositionID: context.compositionID,
                    rawLength: context.rawInput.count,
                    rawRevision: context.rawRevision,
                    appBundleID: context.appBundleID,
                    reason: "new_schedule"
                )
            case .transportStarted:
                record(
                    .transportLeftStale,
                    requestID: cancelledRequestID,
                    compositionID: context.compositionID,
                    rawLength: context.rawInput.count,
                    rawRevision: context.rawRevision,
                    appBundleID: context.appBundleID,
                    reason: "new_schedule"
                )
            case nil:
                activeTask?.cancel()
            }
        } else {
            activeTask?.cancel()
        }
        activeTask = nil
        activeRequestID = nil
        activeRequestPhase = nil
        generation += 1
        let currentGeneration = generation
        let requestID = UUID()

        let scheduleDecision = schedulePolicy.decision(
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
        if case .skip(let skip) = scheduleDecision {
            record(
                skip.diagnosticStage,
                requestID: requestID,
                compositionID: context.compositionID,
                rawLength: context.rawInput.count,
                rawRevision: context.rawRevision,
                prefixLength: context.lockedPrefix?.count,
                appBundleID: context.appBundleID,
                reason: skip.reason
            )
            return skip.state
        }

        guard let provider else {
            record(
                .skippedNoProvider,
                requestID: requestID,
                compositionID: context.compositionID,
                rawLength: context.rawInput.count,
                rawRevision: context.rawRevision,
                prefixLength: context.lockedPrefix?.count,
                appBundleID: context.appBundleID,
                reason: "recommendation_provider_missing"
            )
            return .idle
        }

        let request = AIRecommendationRequest(
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
        )
        record(
            .scheduled,
            requestID: requestID,
            compositionID: context.compositionID,
            rawLength: context.rawInput.count,
            rawRevision: context.rawRevision,
            prefixLength: context.lockedPrefix?.count,
            appBundleID: context.appBundleID
        )
        activeRequestID = requestID
        activeRequestPhase = .dispatchDeferred
        let scheduledAt = Date()
        let task = Task.detached(priority: .utility) { [weak self, provider, diagnosticSink] in
            guard let self else {
                return
            }
            if self.dispatchDebounceNanoseconds > 0 {
                diagnosticSink.record(
                    AIRecommendationDiagnosticEvent(
                        stage: .dispatchDeferred,
                        requestID: requestID,
                        compositionID: context.compositionID,
                        rawLength: context.rawInput.count,
                        rawRevision: context.rawRevision,
                        prefixLength: context.lockedPrefix?.count,
                        appBundleID: context.appBundleID,
                        reason: "waiting_for_stable_input"
                    )
                )
                do {
                    try await Task.sleep(nanoseconds: self.dispatchDebounceNanoseconds)
                } catch {
                    diagnosticSink.record(
                        AIRecommendationDiagnosticEvent(
                            stage: .dispatchCancelledByNewInput,
                            requestID: requestID,
                            compositionID: context.compositionID,
                            rawLength: context.rawInput.count,
                            rawRevision: context.rawRevision,
                            prefixLength: context.lockedPrefix?.count,
                            appBundleID: context.appBundleID,
                            elapsedMilliseconds: Self.elapsedMilliseconds(since: scheduledAt),
                            reason: "debounce_cancelled_by_new_input"
                        )
                    )
                    return
                }
            }
            let shouldDispatch = await MainActor.run { [weak self] in
                guard let self,
                      self.activeRequestID == requestID,
                      self.generation == currentGeneration else {
                    return false
                }
                self.activeRequestPhase = .transportStarted
                if !context.isProviderAvailabilityProbe,
                   self.dispatchDebounceNanoseconds > 0 {
                    onStateChange(.pending(requestID: requestID))
                }
                return true
            }
            guard shouldDispatch else {
                diagnosticSink.record(
                    AIRecommendationDiagnosticEvent(
                        stage: .dispatchCancelledByNewInput,
                        requestID: requestID,
                        compositionID: context.compositionID,
                        rawLength: context.rawInput.count,
                        rawRevision: context.rawRevision,
                        prefixLength: context.lockedPrefix?.count,
                        appBundleID: context.appBundleID,
                        elapsedMilliseconds: Self.elapsedMilliseconds(since: scheduledAt),
                        reason: "request_inactive_before_transport"
                    )
                )
                return
            }
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .transportStarted,
                    requestID: requestID,
                    compositionID: context.compositionID,
                rawLength: context.rawInput.count,
                rawRevision: context.rawRevision,
                prefixLength: context.lockedPrefix?.count,
                appBundleID: context.appBundleID,
                elapsedMilliseconds: Self.elapsedMilliseconds(since: scheduledAt)
            )
            )
            let transportStartedAt = Date()
            let state = await provider.recommendation(for: request)
            let transportElapsedMilliseconds = Self.elapsedMilliseconds(since: transportStartedAt)
            let patch = AIRecommendationPatch(
                requestID: requestID,
                generation: currentGeneration,
                compositionID: context.compositionID,
                rawRevision: context.rawRevision,
                rawInput: context.rawInput,
                state: state
            )
            guard !Task.isCancelled else {
                diagnosticSink.record(
                    AIRecommendationDiagnosticEvent(
                        stage: .cancelled,
                        requestID: requestID,
                        compositionID: context.compositionID,
                        rawLength: context.rawInput.count,
                        rawRevision: context.rawRevision,
                        prefixLength: context.lockedPrefix?.count,
                        appBundleID: context.appBundleID,
                        elapsedMilliseconds: transportElapsedMilliseconds,
                        reason: "task_cancelled_before_apply"
                    )
                )
                return
            }
            Task { @MainActor [weak self, currentSnapshot, onStateChange, diagnosticSink] in
                guard let self,
                      let snapshot = currentSnapshot() else {
                    diagnosticSink.record(
                        AIRecommendationDiagnosticEvent(
                            stage: .staleResultDropped,
                            requestID: requestID,
                            compositionID: context.compositionID,
                            rawLength: context.rawInput.count,
                            rawRevision: context.rawRevision,
                            prefixLength: context.lockedPrefix?.count,
                            appBundleID: context.appBundleID,
                            elapsedMilliseconds: transportElapsedMilliseconds,
                            reason: "coordinator_released"
                        )
                    )
                    return
                }
                guard patch.matches(
                    requestID: self.activeRequestID,
                    generation: self.generation,
                    compositionID: snapshot.compositionID,
                    rawRevision: snapshot.rawRevision,
                    rawInput: snapshot.rawInput
                ) else {
                    let reason = self.activeRequestID == requestID
                        ? Self.diagnosticReason(for: state)
                        : "request_inactive"
                    if self.activeRequestID == requestID {
                        self.activeRequestID = nil
                        self.activeTask = nil
                        self.activeRequestPhase = nil
                    }
                    diagnosticSink.record(
                        AIRecommendationDiagnosticEvent(
                            stage: .staleResultDropped,
                            requestID: requestID,
                            compositionID: context.compositionID,
                            rawLength: context.rawInput.count,
                            rawRevision: context.rawRevision,
                            prefixLength: context.lockedPrefix?.count,
                            appBundleID: context.appBundleID,
                            elapsedMilliseconds: transportElapsedMilliseconds,
                            reason: reason
                        )
                    )
                    return
                }
                if self.activeRequestID == requestID {
                    self.activeRequestID = nil
                    self.activeTask = nil
                    self.activeRequestPhase = nil
                }
                if context.isProviderAvailabilityProbe,
                   !Self.shouldApplyProviderAvailabilityProbeState(patch.state) {
                    diagnosticSink.record(
                        AIRecommendationDiagnosticEvent(
                            stage: .stateApplied,
                            requestID: requestID,
                            compositionID: context.compositionID,
                            rawLength: context.rawInput.count,
                            rawRevision: context.rawRevision,
                            prefixLength: context.lockedPrefix?.count,
                            appBundleID: context.appBundleID,
                            elapsedMilliseconds: transportElapsedMilliseconds,
                            reason: "availability_probe_suppressed_\(Self.diagnosticReason(for: patch.state))"
                        )
                    )
                    return
                }
                diagnosticSink.record(
                    AIRecommendationDiagnosticEvent(
                        stage: .stateApplied,
                        requestID: requestID,
                        compositionID: context.compositionID,
                        rawLength: context.rawInput.count,
                        rawRevision: context.rawRevision,
                        prefixLength: context.lockedPrefix?.count,
                        appBundleID: context.appBundleID,
                        elapsedMilliseconds: transportElapsedMilliseconds,
                        reason: Self.diagnosticReason(for: patch.state)
                    )
                )
                onStateChange(patch.state)
            }
        }
        activeTask = task
        if context.isProviderAvailabilityProbe || dispatchDebounceNanoseconds > 0 {
            return .idle
        }
        return .pending(requestID: requestID)
    }

    @discardableResult
    func reset(compositionID: Int?, rawLength: Int?, reason: String) -> AIRecommendationState {
        let phase = activeRequestPhase
        cancelActiveForDiagnostics(
            compositionID: compositionID,
            rawLength: rawLength,
            reason: reason
        )
        generation += 1
        if phase == .dispatchDeferred {
            activeTask?.cancel()
        }
        activeTask = nil
        activeRequestPhase = nil
        return .idle
    }

    func cancelActiveForDiagnostics(
        compositionID: Int?,
        rawLength: Int?,
        reason: String
    ) {
        guard let requestID = activeRequestID else {
            return
        }
        record(
            .cancelPrevious,
            requestID: requestID,
            compositionID: compositionID,
            rawLength: rawLength,
            reason: reason
        )
        if activeRequestPhase == .transportStarted {
            record(
                .transportLeftStale,
                requestID: requestID,
                compositionID: compositionID,
                rawLength: rawLength,
                reason: reason
            )
        }
        activeRequestID = nil
        activeRequestPhase = nil
    }

    private func record(
        _ stage: AIRecommendationDiagnosticStage,
        requestID: UUID? = nil,
        compositionID: Int? = nil,
        rawLength: Int? = nil,
        rawRevision: Int? = nil,
        prefixLength: Int? = nil,
        appBundleID: String? = nil,
        elapsedMilliseconds: Int? = nil,
        reason: String? = nil
    ) {
        diagnosticSink.record(
            AIRecommendationDiagnosticEvent(
                stage: stage,
                requestID: requestID,
                compositionID: compositionID,
                rawLength: rawLength,
                rawRevision: rawRevision,
                prefixLength: prefixLength,
                appBundleID: appBundleID,
                elapsedMilliseconds: elapsedMilliseconds,
                reason: reason
            )
        )
    }

    private static func elapsedMilliseconds(since start: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(start) * 1_000))
    }

    private static func diagnosticReason(for state: AIRecommendationState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .pending:
            return "pending"
        case .ready:
            return "ready"
        case .ineligible(let reason):
            return "ineligible:\(reason)"
        case .unavailable(let reason):
            return "unavailable:\(reason)"
        }
    }

    private static func shouldApplyProviderAvailabilityProbeState(_ state: AIRecommendationState) -> Bool {
        if case .ready = state {
            return true
        }
        return false
    }
}
