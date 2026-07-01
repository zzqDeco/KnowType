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

    private let provider: (any AIRecommendationProviding)?
    private let providerAvailability: (any AIRecommendationProviderAvailabilitySnapshotting)?
    private let schedulePolicy: InputAIRecommendationSchedulePolicy
    private let diagnosticSink: any AIRecommendationDiagnosticSink
    private let hasEagerProvider: Bool
    private var activeTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var generation = 0

    init(
        provider: (any AIRecommendationProviding)?,
        providerAvailability: (any AIRecommendationProviderAvailabilitySnapshotting)?,
        hasEagerProvider: Bool,
        schedulePolicy: InputAIRecommendationSchedulePolicy = .default,
        diagnosticSink: any AIRecommendationDiagnosticSink = OSLogAIRecommendationDiagnosticSink()
    ) {
        self.provider = provider
        self.providerAvailability = providerAvailability
        self.hasEagerProvider = hasEagerProvider
        self.schedulePolicy = schedulePolicy
        self.diagnosticSink = diagnosticSink
    }

    var hasKnownProvider: Bool {
        hasEagerProvider || providerAvailability?.providerAvailability == .available
    }

    var shouldBuildRecommendationContext: Bool {
        if hasEagerProvider {
            return true
        }
        guard provider != nil else {
            return false
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
        hasEagerProvider || provider != nil
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
                appBundleID: context.appBundleID,
                reason: "new_schedule"
            )
        }
        activeTask?.cancel()
        activeTask = nil
        activeRequestID = nil
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
            prefixLength: context.lockedPrefix?.count,
            appBundleID: context.appBundleID
        )
        activeRequestID = requestID
        let task = Task.detached(priority: .utility) { [weak self, provider, diagnosticSink] in
            let state = await provider.recommendation(for: request)
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
                        prefixLength: context.lockedPrefix?.count,
                        appBundleID: context.appBundleID,
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
                            prefixLength: context.lockedPrefix?.count,
                            appBundleID: context.appBundleID,
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
                    }
                    diagnosticSink.record(
                        AIRecommendationDiagnosticEvent(
                            stage: .staleResultDropped,
                            requestID: requestID,
                            compositionID: context.compositionID,
                            rawLength: context.rawInput.count,
                            prefixLength: context.lockedPrefix?.count,
                            appBundleID: context.appBundleID,
                            reason: reason
                        )
                    )
                    return
                }
                if self.activeRequestID == requestID {
                    self.activeRequestID = nil
                    self.activeTask = nil
                }
                if context.isProviderAvailabilityProbe,
                   !Self.shouldApplyProviderAvailabilityProbeState(patch.state) {
                    diagnosticSink.record(
                        AIRecommendationDiagnosticEvent(
                            stage: .stateApplied,
                            requestID: requestID,
                            compositionID: context.compositionID,
                            rawLength: context.rawInput.count,
                            prefixLength: context.lockedPrefix?.count,
                            appBundleID: context.appBundleID,
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
                        prefixLength: context.lockedPrefix?.count,
                        appBundleID: context.appBundleID,
                        reason: Self.diagnosticReason(for: patch.state)
                    )
                )
                onStateChange(patch.state)
            }
        }
        activeTask = task
        return context.isProviderAvailabilityProbe ? .idle : .pending(requestID: requestID)
    }

    @discardableResult
    func reset(compositionID: Int?, rawLength: Int?, reason: String) -> AIRecommendationState {
        cancelActiveForDiagnostics(
            compositionID: compositionID,
            rawLength: rawLength,
            reason: reason
        )
        generation += 1
        activeTask?.cancel()
        activeTask = nil
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
        activeRequestID = nil
    }

    private func record(
        _ stage: AIRecommendationDiagnosticStage,
        requestID: UUID? = nil,
        compositionID: Int? = nil,
        rawLength: Int? = nil,
        prefixLength: Int? = nil,
        appBundleID: String? = nil,
        reason: String? = nil
    ) {
        diagnosticSink.record(
            AIRecommendationDiagnosticEvent(
                stage: stage,
                requestID: requestID,
                compositionID: compositionID,
                rawLength: rawLength,
                prefixLength: prefixLength,
                appBundleID: appBundleID,
                reason: reason
            )
        )
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
