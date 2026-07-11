import Foundation
import KnowTypeAI
import KnowTypeCore
import KnowTypeProviders

public struct InputAIPolishBinding: Sendable, Equatable {
    public var requestID: UUID
    public var compositionID: Int
    public var rawRevision: Int
    public var providerGeneration: UInt64?

    public init(
        requestID: UUID,
        compositionID: Int,
        rawRevision: Int,
        providerGeneration: UInt64?
    ) {
        self.requestID = requestID
        self.compositionID = compositionID
        self.rawRevision = rawRevision
        self.providerGeneration = providerGeneration
    }
}

public struct InputAIPolishCandidate: Sendable, Equatable {
    public var text: String
    public var confidence: Double
    public var provider: String

    public init(text: String, confidence: Double, provider: String) {
        self.text = text
        self.confidence = confidence
        self.provider = provider
    }
}

public enum InputAIPolishState: Sendable, Equatable {
    case idle
    case pending(InputAIPolishBinding)
    case ready(InputAIPolishBinding, candidates: [InputAIPolishCandidate])
    case unavailable(InputAIPolishBinding, reason: String)

    public var isActive: Bool {
        if case .idle = self {
            return false
        }
        return true
    }

    public var binding: InputAIPolishBinding? {
        switch self {
        case .idle:
            return nil
        case .pending(let binding), .ready(let binding, _), .unavailable(let binding, _):
            return binding
        }
    }

    public var candidates: [InputAIPolishCandidate] {
        guard case .ready(_, let candidates) = self else {
            return []
        }
        return candidates
    }
}

struct InputAIPolishRequestContext: Sendable, Equatable {
    var text: String
    var rawInput: String
    var appBundleID: String?
    var locale: KnowTypeLocale
    var compositionID: Int
    var rawRevision: Int
    var hasActiveComposition: Bool
}

struct InputAIPolishCompositionSnapshot: Sendable, Equatable {
    var rawInput: String
    var compositionID: Int
    var rawRevision: Int
}

enum InputAIPolishGateDecision: Sendable, Equatable {
    case allow
    case deny(reason: String)
}

enum InputAIPolishGate {
    static func decision(for context: InputAIPolishRequestContext) -> InputAIPolishGateDecision {
        let trimmed = context.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard context.hasActiveComposition, !trimmed.isEmpty else {
            return .deny(reason: "当前没有可润色内容")
        }
        guard !TextProtection.requiresNoCorrection("knowtype", appBundleID: context.appBundleID),
              !TextProtection.requiresNoCorrection(context.text, appBundleID: context.appBundleID) else {
            return .deny(reason: "当前内容不可润色")
        }
        guard !TextProtection.containsSecretLikeContent(context.text),
              !TextProtection.containsSecretLikeContent(context.rawInput) else {
            return .deny(reason: "AI 润色已禁用")
        }
        return .allow
    }
}

protocol InputAIPolishProviderRuntime: Sendable {
    func leaseForEligibleDispatch() async -> ProviderRuntimeLease
    func performPolish(_ request: LLMRequest, using lease: ProviderRuntimeLease) async throws -> LLMResponse
    func validateForAcceptance(_ lease: ProviderRuntimeLease) async throws
    func polishRevisionUpdates() async -> AsyncStream<UInt64>
}

extension InputAIPolishProviderRuntime {
    func polishRevisionUpdates() async -> AsyncStream<UInt64> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

extension ProviderRuntimeRegistry: InputAIPolishProviderRuntime {
    func performPolish(_ request: LLMRequest, using lease: ProviderRuntimeLease) async throws -> LLMResponse {
        try await perform(using: lease) { provider in
            try await provider.complete(request)
        }
    }

    func validateForAcceptance(_ lease: ProviderRuntimeLease) async throws {
        _ = try await commitIfCurrent(using: lease) { true }
    }

    func polishRevisionUpdates() async -> AsyncStream<UInt64> {
        DistributedProviderProfileRevisionSignal().revisionUpdates()
    }
}

final class InputAIPolishRuntime: @unchecked Sendable {
    typealias SnapshotProvider = @MainActor @Sendable () -> InputAIPolishCompositionSnapshot
    typealias StateChangeHandler = @MainActor @Sendable (InputAIPolishState) -> Void
    typealias AcceptanceHandler = @MainActor @Sendable (InputAIPolishCandidate) -> Void

    private let providerRuntime: any InputAIPolishProviderRuntime
    private let diagnosticSink: any AIRecommendationDiagnosticSink
    private var state: InputAIPolishState = .idle
    private var requestTask: Task<Void, Never>?
    private var acceptanceTask: Task<Void, Never>?
    private var providerObservationTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var activeRuntimeGeneration = 0
    private var activeRawInput = ""
    private var activeLease: ProviderRuntimeLease?
    private var isAccepting = false

    init(
        providerRuntime: any InputAIPolishProviderRuntime = ProviderRuntimeRegistry.shared,
        diagnosticSink: any AIRecommendationDiagnosticSink = OSLogAIRecommendationDiagnosticSink()
    ) {
        self.providerRuntime = providerRuntime
        self.diagnosticSink = diagnosticSink
    }

    deinit {
        requestTask?.cancel()
        acceptanceTask?.cancel()
        providerObservationTask?.cancel()
    }

    var currentState: InputAIPolishState {
        state
    }

    @discardableResult
    func request(
        context: InputAIPolishRequestContext,
        currentSnapshot: @escaping SnapshotProvider,
        onStateChange: @escaping StateChangeHandler
    ) -> InputAIPolishState {
        cancelWork()
        activeRuntimeGeneration += 1
        let runtimeGeneration = activeRuntimeGeneration
        let requestID = UUID()
        let localBinding = InputAIPolishBinding(
            requestID: requestID,
            compositionID: context.compositionID,
            rawRevision: context.rawRevision,
            providerGeneration: nil
        )
        activeRequestID = requestID
        activeRawInput = context.rawInput

        if case .deny(let reason) = InputAIPolishGate.decision(for: context) {
            state = .unavailable(localBinding, reason: reason)
            recordDiagnostic(
                .polishUnavailable,
                binding: localBinding,
                rawLength: context.rawInput.count,
                reason: "privacy_gate"
            )
            return state
        }

        state = .pending(localBinding)
        recordDiagnostic(
            .polishRequested,
            binding: localBinding,
            rawLength: context.rawInput.count
        )
        let providerRuntime = providerRuntime
        requestTask = Task.detached(priority: .utility) { [weak self, providerRuntime] in
            guard let self else {
                return
            }
            let lease = await providerRuntime.leaseForEligibleDispatch()
            let binding = InputAIPolishBinding(
                requestID: requestID,
                compositionID: context.compositionID,
                rawRevision: context.rawRevision,
                providerGeneration: lease.generation
            )
            let revisionUpdates = await providerRuntime.polishRevisionUpdates()
            let canDispatch = await MainActor.run { [weak self, currentSnapshot, onStateChange] in
                guard let self,
                      self.matches(
                          requestID: requestID,
                          runtimeGeneration: runtimeGeneration,
                          context: context,
                          snapshot: currentSnapshot()
                      ) else {
                    return false
                }
                self.activeLease = lease
                self.state = .pending(binding)
                self.observeProviderRevisions(
                    revisionUpdates,
                    lease: lease,
                    binding: binding,
                    requestID: requestID,
                    runtimeGeneration: runtimeGeneration,
                    context: context,
                    currentSnapshot: currentSnapshot,
                    onStateChange: onStateChange
                )
                onStateChange(self.state)
                return true
            }
            guard canDispatch, !Task.isCancelled else {
                return
            }
            guard lease.provider != nil else {
                self.recordDiagnostic(
                    .polishUnavailable,
                    binding: binding,
                    rawLength: context.rawInput.count,
                    reason: "no_provider"
                )
                await MainActor.run { [weak self, currentSnapshot, onStateChange] in
                    self?.apply(
                        .unavailable(binding, reason: "AI 润色未配置"),
                        requestID: requestID,
                        runtimeGeneration: runtimeGeneration,
                        context: context,
                        currentSnapshot: currentSnapshot,
                        onStateChange: onStateChange
                    )
                }
                return
            }

            let request = LLMRequest(
                task: .polish,
                lockedPrefix: nil,
                rawInput: context.text,
                candidateHints: [],
                locale: context.locale,
                appContext: context.appBundleID,
                maxCandidates: 3,
                outputSchema: "json"
            )
            do {
                let response = try await providerRuntime.performPolish(request, using: lease)
                guard !Task.isCancelled else {
                    return
                }
                let candidates = Self.candidates(from: response, providerName: lease.provider?.providerName ?? "provider")
                let nextState: InputAIPolishState = candidates.isEmpty
                    ? .unavailable(binding, reason: "AI 无润色结果")
                    : .ready(binding, candidates: candidates)
                self.recordDiagnostic(
                    candidates.isEmpty ? .polishUnavailable : .polishReady,
                    binding: binding,
                    rawLength: context.rawInput.count,
                    candidateCount: candidates.count,
                    reason: candidates.isEmpty ? "empty_response" : nil
                )
                await MainActor.run { [weak self, currentSnapshot, onStateChange] in
                    self?.apply(
                        nextState,
                        requestID: requestID,
                        runtimeGeneration: runtimeGeneration,
                        context: context,
                        currentSnapshot: currentSnapshot,
                        onStateChange: onStateChange
                    )
                }
            } catch is CancellationError {
                return
            } catch ProviderRuntimeRegistryError.staleGeneration {
                self.recordDiagnostic(
                    .polishStaleDropped,
                    binding: binding,
                    rawLength: context.rawInput.count,
                    reason: "provider_generation"
                )
                await MainActor.run { [weak self, currentSnapshot, onStateChange] in
                    self?.apply(
                        .idle,
                        requestID: requestID,
                        runtimeGeneration: runtimeGeneration,
                        context: context,
                        currentSnapshot: currentSnapshot,
                        onStateChange: onStateChange
                    )
                }
            } catch {
                self.recordDiagnostic(
                    .polishUnavailable,
                    binding: binding,
                    rawLength: context.rawInput.count,
                    reason: "provider_error"
                )
                await MainActor.run { [weak self, currentSnapshot, onStateChange] in
                    self?.apply(
                        .unavailable(binding, reason: "AI 润色暂不可用"),
                        requestID: requestID,
                        runtimeGeneration: runtimeGeneration,
                        context: context,
                        currentSnapshot: currentSnapshot,
                        onStateChange: onStateChange
                    )
                }
            }
        }
        return state
    }

    @discardableResult
    func acceptCandidate(
        at index: Int,
        currentSnapshot: @escaping SnapshotProvider,
        onStateChange: @escaping StateChangeHandler,
        onAccept: @escaping AcceptanceHandler
    ) -> Bool {
        guard !isAccepting,
              case .ready(let binding, let candidates) = state,
              candidates.indices.contains(index),
              let lease = activeLease,
              lease.generation == binding.providerGeneration else {
            return false
        }
        let candidate = candidates[index]
        let requestID = binding.requestID
        let runtimeGeneration = activeRuntimeGeneration
        let rawLength = activeRawInput.count
        isAccepting = true
        let providerRuntime = providerRuntime
        acceptanceTask = Task.detached(priority: .userInitiated) { [weak self, providerRuntime] in
            do {
                try await providerRuntime.validateForAcceptance(lease)
            } catch {
                self?.recordDiagnostic(
                    .polishStaleDropped,
                    binding: binding,
                    rawLength: rawLength,
                    reason: "acceptance_generation"
                )
                await MainActor.run { [weak self, onStateChange] in
                    guard let self,
                          self.activeRequestID == requestID,
                          self.activeRuntimeGeneration == runtimeGeneration else {
                        return
                    }
                    self.clearActiveState()
                    onStateChange(.idle)
                }
                return
            }
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run { [weak self, currentSnapshot, onStateChange, onAccept] in
                guard let self,
                      self.activeRequestID == requestID,
                      self.activeRuntimeGeneration == runtimeGeneration,
                      let activeBinding = self.state.binding,
                      activeBinding == binding else {
                    return
                }
                let snapshot = currentSnapshot()
                guard snapshot.compositionID == binding.compositionID,
                      snapshot.rawRevision == binding.rawRevision,
                      snapshot.rawInput == self.activeRawInput else {
                    self.clearActiveState()
                    onStateChange(.idle)
                    return
                }
                self.clearActiveState()
                self.recordDiagnostic(
                    .polishAccepted,
                    binding: binding,
                    rawLength: snapshot.rawInput.count,
                    candidateCount: 1
                )
                onStateChange(.idle)
                onAccept(candidate)
            }
        }
        return true
    }

    @discardableResult
    func reset() -> InputAIPolishState {
        if let binding = state.binding {
            recordDiagnostic(
                .polishCancelled,
                binding: binding,
                rawLength: activeRawInput.count
            )
        }
        cancelWork()
        activeRuntimeGeneration += 1
        clearActiveState()
        return state
    }

    @MainActor
    private func apply(
        _ nextState: InputAIPolishState,
        requestID: UUID,
        runtimeGeneration: Int,
        context: InputAIPolishRequestContext,
        currentSnapshot: SnapshotProvider,
        onStateChange: StateChangeHandler
    ) {
        guard matches(
            requestID: requestID,
            runtimeGeneration: runtimeGeneration,
            context: context,
            snapshot: currentSnapshot()
        ) else {
            return
        }
        requestTask = nil
        state = nextState
        if case .idle = nextState {
            clearActiveState()
        }
        onStateChange(nextState)
    }

    private func matches(
        requestID: UUID,
        runtimeGeneration: Int,
        context: InputAIPolishRequestContext,
        snapshot: InputAIPolishCompositionSnapshot
    ) -> Bool {
        activeRequestID == requestID
            && activeRuntimeGeneration == runtimeGeneration
            && snapshot.compositionID == context.compositionID
            && snapshot.rawRevision == context.rawRevision
            && snapshot.rawInput == context.rawInput
    }

    private func cancelWork() {
        requestTask?.cancel()
        acceptanceTask?.cancel()
        providerObservationTask?.cancel()
        requestTask = nil
        acceptanceTask = nil
        providerObservationTask = nil
        isAccepting = false
    }

    private func observeProviderRevisions(
        _ updates: AsyncStream<UInt64>,
        lease: ProviderRuntimeLease,
        binding: InputAIPolishBinding,
        requestID: UUID,
        runtimeGeneration: Int,
        context: InputAIPolishRequestContext,
        currentSnapshot: @escaping SnapshotProvider,
        onStateChange: @escaping StateChangeHandler
    ) {
        providerObservationTask?.cancel()
        providerObservationTask = Task.detached(priority: .utility) { [weak self] in
            for await revision in updates {
                guard !Task.isCancelled else {
                    return
                }
                guard revision != lease.revision else {
                    continue
                }
                await MainActor.run { [weak self, currentSnapshot, onStateChange] in
                    guard let self,
                          self.matches(
                              requestID: requestID,
                              runtimeGeneration: runtimeGeneration,
                              context: context,
                              snapshot: currentSnapshot()
                          ) else {
                        return
                    }
                    self.recordDiagnostic(
                        .polishStaleDropped,
                        binding: binding,
                        rawLength: context.rawInput.count,
                        reason: "provider_revision"
                    )
                    self.clearActiveState()
                    onStateChange(.idle)
                }
                return
            }
        }
    }

    private func clearActiveState() {
        cancelWork()
        activeRequestID = nil
        activeRawInput = ""
        activeLease = nil
        state = .idle
    }

    private static func candidates(from response: LLMResponse, providerName: String) -> [InputAIPolishCandidate] {
        var seen = Set<String>()
        return response.candidates.compactMap { candidate in
            let text = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, seen.insert(text).inserted else {
                return nil
            }
            return InputAIPolishCandidate(
                text: text,
                confidence: candidate.confidence ?? 0.7,
                provider: providerName
            )
        }
    }

    private func recordDiagnostic(
        _ stage: AIRecommendationDiagnosticStage,
        binding: InputAIPolishBinding,
        rawLength: Int,
        candidateCount: Int? = nil,
        reason: String? = nil
    ) {
        diagnosticSink.record(
            AIRecommendationDiagnosticEvent(
                stage: stage,
                requestID: binding.requestID,
                compositionID: binding.compositionID,
                rawLength: rawLength,
                rawRevision: binding.rawRevision,
                candidateCount: candidateCount,
                reason: reason
            )
        )
    }
}
