import Foundation
import KnowTypeCore
import KnowTypeProviders

public actor LazyDefaultAIRecommendationRuntime: AIRecommendationProviding {
    private let providerRegistry: ProviderRuntimeRegistry?
    private let providerLoader: (@Sendable () -> (any LLMProvider)?)?
    private let diagnosticSink: any AIRecommendationDiagnosticSink
    private let providerAvailability: AIRecommendationProviderAvailabilityState
    private let debounceMilliseconds: Int
    private var runtime: AIRecommendationRuntime?
    private var runtimeGeneration: UInt64?

    public init(
        providerRegistry: ProviderRuntimeRegistry = .shared,
        diagnosticSink: any AIRecommendationDiagnosticSink = OSLogAIRecommendationDiagnosticSink(),
        providerAvailability: AIRecommendationProviderAvailabilityState = AIRecommendationProviderAvailabilityState(),
        debounceMilliseconds: Int = AIRecommendationRuntime.Defaults.debounceMilliseconds
    ) {
        self.providerRegistry = providerRegistry
        self.providerLoader = nil
        self.diagnosticSink = diagnosticSink
        self.providerAvailability = providerAvailability
        self.debounceMilliseconds = debounceMilliseconds
    }

    public init(
        providerLoader: @escaping @Sendable () -> (any LLMProvider)?,
        diagnosticSink: any AIRecommendationDiagnosticSink = OSLogAIRecommendationDiagnosticSink(),
        providerAvailability: AIRecommendationProviderAvailabilityState = AIRecommendationProviderAvailabilityState(),
        debounceMilliseconds: Int = AIRecommendationRuntime.Defaults.debounceMilliseconds
    ) {
        self.providerRegistry = nil
        self.providerLoader = providerLoader
        self.diagnosticSink = diagnosticSink
        self.providerAvailability = providerAvailability
        self.debounceMilliseconds = debounceMilliseconds
    }

    public func recommendation(for request: AIRecommendationRequest) async -> AIRecommendationState {
        guard AIRecommendationRuntime.isEligibleForProviderDispatch(request) else {
            return await makeRuntime(provider: nil).recommendation(for: request)
        }
        if let providerRegistry {
            return await registryRecommendation(for: request, registry: providerRegistry)
        }
        return await legacyRecommendation(for: request)
    }

    private func registryRecommendation(
        for request: AIRecommendationRequest,
        registry: ProviderRuntimeRegistry
    ) async -> AIRecommendationState {
        let lease = await registry.leaseForEligibleDispatch()
        guard let provider = lease.provider else {
            runtime = nil
            runtimeGeneration = nil
            providerAvailability.update(.unavailable)
            return await makeRuntime(provider: nil).recommendation(for: request)
        }
        providerAvailability.update(.available)
        let runtime: AIRecommendationRuntime
        if let cached = self.runtime, runtimeGeneration == lease.generation {
            runtime = cached
        } else {
            runtime = makeRuntime(
                provider: provider,
                providerIdentity: lease.fingerprint,
                providerGeneration: lease.generation,
                requestGate: registry.requestGate
            )
            self.runtime = runtime
            runtimeGeneration = lease.generation
        }
        do {
            return try await registry.perform(using: lease) { _ in
                await runtime.recommendation(for: request)
            }
        } catch ProviderRuntimeRegistryError.staleGeneration {
            if self.runtime === runtime, runtimeGeneration == lease.generation {
                self.runtime = nil
                runtimeGeneration = nil
                providerAvailability.update(.unknown)
            }
            return .stale
        } catch {
            return .idle
        }
    }

    private func legacyRecommendation(for request: AIRecommendationRequest) async -> AIRecommendationState {
        if let runtime {
            return await runtime.recommendation(for: request)
        }
        let provider = providerLoader?()
        guard provider != nil else {
            providerAvailability.update(.unavailable)
            return await makeRuntime(provider: nil).recommendation(for: request)
        }
        providerAvailability.update(.available)
        let runtime = makeRuntime(provider: provider)
        self.runtime = runtime
        return await runtime.recommendation(for: request)
    }

    private func makeRuntime(
        provider: (any LLMProvider)?,
        providerIdentity: String? = nil,
        providerGeneration: UInt64 = 0,
        requestGate: ProviderRequestGate = .shared
    ) -> AIRecommendationRuntime {
        AIRecommendationRuntime(
            provider: provider,
            debounceMilliseconds: debounceMilliseconds,
            diagnosticSink: diagnosticSink,
            requestGate: requestGate,
            providerIdentity: providerIdentity,
            providerGeneration: providerGeneration
        )
    }
}

public actor AIRecommendationRuntime: AIRecommendationProviding {
    public enum Defaults {
        public static let debounceMilliseconds = 350
        public static let hardTimeoutMilliseconds = 10_000
    }

    private struct CacheKey: Hashable {
        var lockedPrefix: String?
        var rawInput: String
        var appBundleID: String
        var localeRawValue: String
        var environmentHash: String
        var correctionHash: String
        var lexicalHash: String
        var feedbackHash: String
        var payloadFingerprint: String
    }

    private struct CacheEntry {
        var candidate: AIRecommendationCandidate
        var expiresAt: Date
    }

    private let provider: (any LLMProvider)?
    private let environmentStore: EnvironmentDocumentStore
    private let correctionStore: CorrectionInstructionStore
    private let healthMonitor: AIHealthMonitor
    private let debounceNanoseconds: UInt64
    private let hardTimeoutNanoseconds: UInt64
    private let diagnosticSink: any AIRecommendationDiagnosticSink
    private let cacheTTL: TimeInterval
    private let requestGate: ProviderRequestGate
    private let providerIdentity: String
    private let providerGeneration: UInt64
    private var cache: [CacheKey: CacheEntry] = [:]
    private var inFlight: [String: Task<LLMResponse, Error>] = [:]

    public init(
        provider: (any LLMProvider)?,
        environmentStore: EnvironmentDocumentStore = EnvironmentDocumentStore(),
        correctionStore: CorrectionInstructionStore = CorrectionInstructionStore(),
        healthMonitor: AIHealthMonitor = AIHealthMonitor(),
        debounceMilliseconds: Int = Defaults.debounceMilliseconds,
        hardTimeoutMilliseconds: Int = Defaults.hardTimeoutMilliseconds,
        diagnosticSink: any AIRecommendationDiagnosticSink = OSLogAIRecommendationDiagnosticSink(),
        cacheTTL: TimeInterval = 300,
        requestGate: ProviderRequestGate = .shared,
        providerIdentity: String? = nil,
        providerGeneration: UInt64 = 0
    ) {
        self.provider = provider
        self.environmentStore = environmentStore
        self.correctionStore = correctionStore
        self.healthMonitor = healthMonitor
        self.debounceNanoseconds = UInt64(max(0, debounceMilliseconds)) * 1_000_000
        self.hardTimeoutNanoseconds = UInt64(max(1, hardTimeoutMilliseconds)) * 1_000_000
        self.diagnosticSink = diagnosticSink
        self.cacheTTL = max(1, cacheTTL)
        self.requestGate = requestGate
        self.providerIdentity = providerIdentity ?? provider?.providerName ?? "knowtype-provider"
        self.providerGeneration = providerGeneration
    }

    public func recommendation(for request: AIRecommendationRequest) async -> AIRecommendationState {
        let startedAt = Date()
        var request = request
        request.candidateHints = []
        guard !request.rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Self.hasUsableRecommendationContext(in: request) else {
            record(
                .skippedIneligible,
                request: request,
                providerName: provider?.providerName,
                elapsedSince: startedAt,
                reason: "empty_raw_or_context"
            )
            return .ineligible(reason: "AI 不适用")
        }
        guard Data(request.rawInput.utf8).count <= ProviderRequestBudget.rawInput,
              request.lockedPrefix.map({ Data($0.utf8).count <= ProviderRequestBudget.lockedPrefix }) ?? true else {
            record(
                .skippedIneligible,
                request: request,
                providerName: provider?.providerName,
                elapsedSince: startedAt,
                reason: "request_budget_exceeded"
            )
            return .ineligible(reason: "AI 输入过长")
        }
        if Self.containsSecretLikeRecommendationText(request) {
            record(
                .skippedProtectedText,
                request: request,
                providerName: provider?.providerName,
                elapsedSince: startedAt,
                reason: "secret_like_text"
            )
            return .ineligible(reason: "AI 已禁用")
        }
        let triggerDecision = AIRecommendationTriggerPolicy.default.decision(
            rawInput: request.rawInput,
            lockedPrefix: request.lockedPrefix
        )
        guard triggerDecision.isEligible else {
            record(
                .skippedPrefixTooShort,
                request: request,
                providerName: provider?.providerName,
                elapsedSince: startedAt,
                reason: triggerDecision.rejectionReason?.rawValue ?? "prefix_too_short"
            )
            return .ineligible(reason: "AI 无推荐")
        }
        guard let provider else {
            record(
                .skippedNoProvider,
                request: request,
                elapsedSince: startedAt,
                reason: "missing_provider"
            )
            return .unavailable(reason: "AI 未配置")
        }
        if let reason = await healthMonitor.unavailableReason() {
            record(
                .cooldownActive,
                request: request,
                providerName: provider.providerName,
                elapsedSince: startedAt,
                reason: reason
            )
            return .unavailable(reason: reason)
        }

        var waitingForIdle = false
        do {
            if debounceNanoseconds > 0 {
                waitingForIdle = true
                record(
                    .debounceStart,
                    request: request,
                    providerName: provider.providerName,
                    elapsedSince: startedAt,
                    reason: "waiting_for_idle"
                )
                try await Task.sleep(nanoseconds: debounceNanoseconds)
                waitingForIdle = false
                record(
                    .debounceEnd,
                    request: request,
                    providerName: provider.providerName,
                    elapsedSince: startedAt
                )
            }
            try Task.checkCancellation()
            let environment = try environmentStore.loadSnapshot()
            let correction = try correctionStore.loadSnapshot()
            record(
                .contextLoaded,
                request: request,
                providerName: provider.providerName,
                elapsedSince: startedAt
            )
            var contextDocuments = [
                "ENV.md": environment.content,
                "CORRECTION.md": correction.content
            ]
            if let lexicalContext = request.lexicalContext {
                contextDocuments["LEXICAL_PROFILE.md"] = lexicalContext.markdown
            }
            if let feedbackContext = request.feedbackContext {
                contextDocuments["AI_FEEDBACK.md"] = feedbackContext.markdown
            }

            let llmRequest = LLMRequest(
                task: .continuation,
                lockedPrefix: request.lockedPrefix,
                rawInput: request.rawInput,
                candidateHints: [],
                locale: request.locale,
                appContext: request.appBundleID,
                maxCandidates: 1,
                lengthLevel: .medium,
                contextDocuments: contextDocuments
            )
            let payloadFingerprint = try AIRequestBudget.fingerprint(for: llmRequest)
            let key = CacheKey(
                lockedPrefix: request.lockedPrefix,
                rawInput: request.rawInput,
                appBundleID: request.appBundleID ?? "",
                localeRawValue: request.locale.rawValue,
                environmentHash: environment.sha256,
                correctionHash: correction.sha256,
                lexicalHash: request.lexicalContext?.sha256 ?? "",
                feedbackHash: request.feedbackContext?.sha256 ?? "",
                payloadFingerprint: payloadFingerprint
            )
            if let cached = cache[key], cached.expiresAt > Date() {
                record(.cacheHit, request: request, providerName: provider.providerName, elapsedSince: startedAt, candidateCount: 1, acceptedCount: 1)
                return .ready(cached.candidate)
            }
            record(.cacheMiss, request: request, providerName: provider.providerName, elapsedSince: startedAt)
            record(
                .structuredSchemaRequest,
                request: request,
                providerName: provider.providerName,
                elapsedSince: startedAt,
                reason: "json_schema_preferred"
            )
            record(
                .providerRequestStart,
                request: request,
                providerName: provider.providerName,
                elapsedSince: startedAt
            )
            let providerStartedAt = Date()
            let response: LLMResponse
            if let pending = inFlight[payloadFingerprint] {
                response = try await pending.value
            } else {
                let gate = requestGate
                let identity = providerIdentity
                let generation = providerGeneration
                let timeout = hardTimeoutNanoseconds
                let task = Task<LLMResponse, Error> {
                    try await gate.execute(providerIdentity: identity, generation: generation) {
                        try await withTimeout(nanoseconds: timeout) {
                            try await provider.complete(llmRequest)
                        }
                    }
                }
                inFlight[payloadFingerprint] = task
                defer { inFlight[payloadFingerprint] = nil }
                response = try await task.value
            }
            record(
                .providerResponse,
                request: request,
                providerName: provider.providerName,
                elapsedSince: providerStartedAt,
                candidateCount: response.candidates.count
            )
            for diagnostic in response.diagnostics {
                if diagnostic == "structured_schema_unsupported"
                    || diagnostic == "structured_schema_unsupported_cached" {
                    record(
                        .structuredSchemaUnsupported,
                        request: request,
                        providerName: provider.providerName,
                        elapsedSince: startedAt,
                        reason: diagnostic
                    )
                }
            }
            let result = Self.makeCandidate(
                response: response,
                lockedPrefix: request.lockedPrefix,
                providerName: provider.providerName,
                contextVersion: [
                    environment.sha256.prefix(12),
                    correction.sha256.prefix(12),
                    request.lexicalContext?.sha256.prefix(12)
                ]
                .compactMap { $0.map(String.init) }
                .joined(separator: ":")
            )
            if result.repairedCount > 0 {
                record(
                    .sanitizeRepair,
                    request: request,
                    providerName: provider.providerName,
                    elapsedSince: startedAt,
                    candidateCount: response.candidates.count,
                    acceptedCount: result.acceptedCount,
                    reason: ContinuationSanitizationReason.repeatedPrefixRepaired.rawValue
                )
            }
            guard let candidate = result.candidate else {
                let rejectionReason = Self.rejectionSummary(result.rejectionReasons)
                record(
                    .sanitizeReject,
                    request: request,
                    providerName: provider.providerName,
                    elapsedSince: startedAt,
                    candidateCount: response.candidates.count,
                    acceptedCount: 0,
                    reason: "sanitize_reject_\(rejectionReason)"
                )
                record(
                    .sanitizeEmpty,
                    request: request,
                    providerName: provider.providerName,
                    elapsedSince: startedAt,
                    candidateCount: response.candidates.count,
                    acceptedCount: 0,
                    reason: rejectionReason
                )
                await healthMonitor.recordSuccess()
                return .ineligible(reason: "AI 无推荐")
            }
            cache[key] = CacheEntry(candidate: candidate, expiresAt: Date().addingTimeInterval(cacheTTL))
            await healthMonitor.recordSuccess()
            record(
                .ready,
                request: request,
                providerName: provider.providerName,
                elapsedSince: startedAt,
                candidateCount: response.candidates.count,
                acceptedCount: result.acceptedCount
            )
            return .ready(candidate)
        } catch let error as ProviderRequestBudgetError {
            record(.skippedIneligible, request: request, providerName: provider.providerName, elapsedSince: startedAt, reason: "request_budget_\(error.component)")
            return .ineligible(reason: "AI 请求过大")
        } catch ProviderRequestGateError.staleGeneration {
            record(.cancelled, request: request, providerName: provider.providerName, elapsedSince: startedAt, reason: "stale_generation")
            return .stale
        } catch is CancellationError {
            record(
                .cancelled,
                request: request,
                providerName: provider.providerName,
                elapsedSince: startedAt,
                reason: waitingForIdle ? "debounce_cancelled_by_new_input" : "task_cancelled"
            )
            return .idle
        } catch {
            if Self.isCancellation(error) {
                record(
                    .cancelled,
                    request: request,
                    providerName: provider.providerName,
                    elapsedSince: startedAt,
                    reason: "transport_cancelled"
                )
                return .idle
            }
            if let gateError = error as? ProviderRequestGateError {
                switch gateError {
                case .cooldown:
                    record(.cooldownActive, request: request, providerName: provider.providerName, elapsedSince: startedAt, reason: "provider_cooldown")
                    return .unavailable(reason: "AI 暂不可用")
                case .busy:
                    record(.cooldownActive, request: request, providerName: provider.providerName, elapsedSince: startedAt, reason: "provider_busy")
                    return .idle
                case .staleGeneration:
                    record(.cancelled, request: request, providerName: provider.providerName, elapsedSince: startedAt, reason: "stale_generation")
                    return .stale
                }
            }
            await healthMonitor.recordFailure(error)
            if error is TimeoutError {
                record(
                    .timeout,
                    request: request,
                    providerName: provider.providerName,
                    elapsedSince: startedAt,
                    reason: "hard_timeout"
                )
                return .unavailable(reason: "AI 请求超时")
            }
            if Self.diagnosticReason(for: error).hasPrefix("structured_decode_error") {
                record(
                    .structuredDecodeError,
                    request: request,
                    providerName: provider.providerName,
                    elapsedSince: startedAt,
                    reason: Self.diagnosticReason(for: error)
                )
            }
            record(
                .providerError,
                request: request,
                providerName: provider.providerName,
                elapsedSince: startedAt,
                reason: Self.diagnosticReason(for: error)
            )
            return .unavailable(reason: "AI 暂不可用")
        }
    }

    static func isEligibleForProviderDispatch(_ request: AIRecommendationRequest) -> Bool {
        guard !request.rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              hasUsableRecommendationContext(in: request),
              !containsSecretLikeRecommendationText(request) else {
            return false
        }
        return AIRecommendationTriggerPolicy.default.decision(
            rawInput: request.rawInput,
            lockedPrefix: request.lockedPrefix
        ).isEligible
    }

    private static func makeCandidate(
        response: LLMResponse,
        lockedPrefix: String?,
        providerName: String,
        contextVersion: String
    ) -> CandidateBuildResult {
        var acceptedCount = 0
        var firstCandidate: AIRecommendationCandidate?
        var rejectionReasons: [String] = []
        var repairedCount = 0
        for rawCandidate in response.candidates {
            let displayText: String
            let continuation: String?
            let prefixText: String
            if let lockedPrefix,
               !lockedPrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let sanitized = PrefixContinuationEngine.sanitizeContinuationDetailed(
                    rawCandidate.text,
                    lockedPrefix: lockedPrefix
                )
                guard let sanitizedContinuation = sanitized.text else {
                    rejectionReasons.append(sanitized.reason.rawValue)
                    continue
                }
                if sanitized.reason == .repeatedPrefixRepaired {
                    repairedCount += 1
                }
                let joined = join(prefix: lockedPrefix, continuation: sanitizedContinuation)
                guard joined.hasPrefix(lockedPrefix) else {
                    rejectionReasons.append(ContinuationSanitizationReason.stillRepeatsPrefix.rawValue)
                    continue
                }
                displayText = joined
                continuation = sanitizedContinuation
                prefixText = lockedPrefix
            } else {
                let trimmed = rawCandidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    rejectionReasons.append(ContinuationSanitizationReason.empty.rawValue)
                    continue
                }
                displayText = trimmed
                continuation = nil
                prefixText = ""
            }
            acceptedCount += 1
            if firstCandidate == nil {
                firstCandidate = AIRecommendationCandidate(
                    prefixText: prefixText,
                    continuationText: continuation,
                    displayText: displayText,
                    confidence: rawCandidate.confidence ?? 0.7,
                    provider: providerName,
                    contextVersion: contextVersion
                )
            }
        }
        return CandidateBuildResult(
            candidate: firstCandidate,
            acceptedCount: acceptedCount,
            rejectionReasons: rejectionReasons,
            repairedCount: repairedCount
        )
    }

    private static func join(prefix: String, continuation: String) -> String {
        if prefix.range(of: #"\p{Han}$"#, options: .regularExpression) != nil,
           continuation.range(of: #"^[A-Za-z0-9]"#, options: .regularExpression) != nil {
            return "\(prefix) \(continuation)"
        }
        if prefix.range(of: #"[A-Za-z0-9]$"#, options: .regularExpression) != nil,
           continuation.range(of: #"^[A-Za-z0-9]"#, options: .regularExpression) != nil {
            return "\(prefix) \(continuation)"
        }
        return "\(prefix)\(continuation)"
    }

    private func record(
        _ stage: AIRecommendationDiagnosticStage,
        request: AIRecommendationRequest,
        providerName: String? = nil,
        elapsedSince start: Date? = nil,
        candidateCount: Int? = nil,
        acceptedCount: Int? = nil,
        reason: String? = nil
    ) {
        diagnosticSink.record(
            AIRecommendationDiagnosticEvent(
                stage: stage,
                requestID: request.requestID,
                compositionID: request.compositionID,
                rawLength: request.rawInput.count,
                prefixLength: request.lockedPrefix?.count ?? 0,
                appBundleID: request.appBundleID,
                providerName: providerName,
                elapsedMilliseconds: start.map(Self.elapsedMilliseconds(since:)),
                candidateCount: candidateCount,
                acceptedCount: acceptedCount,
                reason: reason
            )
        )
    }

    private static func elapsedMilliseconds(since start: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(start) * 1_000))
    }

    private static func diagnosticReason(for error: Error) -> String {
        guard let providerError = error as? ProviderError else {
            return String(describing: type(of: error))
        }
        switch providerError {
        case .httpStatus(let status, _):
            return "http_\(status)"
        case .invalidResponse(let message):
            if message.hasPrefix("structured_decode_error") {
                return message
            }
            return "invalid_response"
        case .missingAPIKey:
            return "missing_api_key"
        case .invalidTemplate:
            return "invalid_template"
        case .unsupportedKind(let kind):
            return "unsupported_kind_\(kind.rawValue)"
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
            && nsError.code == NSURLErrorCancelled
    }

    private static func hasUsableRecommendationContext(in request: AIRecommendationRequest) -> Bool {
        if request.lockedPrefix?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return true
        }
        return !request.rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func containsSecretLikeRecommendationText(_ request: AIRecommendationRequest) -> Bool {
        if TextProtection.containsSecretLikeContent(request.rawInput) {
            return true
        }
        if let lockedPrefix = request.lockedPrefix,
           TextProtection.containsSecretLikeContent(lockedPrefix) {
            return true
        }
        return false
    }

    private static func rejectionSummary(_ reasons: [String]) -> String {
        guard !reasons.isEmpty else {
            return "no_usable_continuation"
        }
        let priority = [
            ContinuationSanitizationReason.empty.rawValue,
            ContinuationSanitizationReason.sameAsPrefix.rawValue,
            ContinuationSanitizationReason.stillRepeatsPrefix.rawValue,
            ContinuationSanitizationReason.noUsableSuffix.rawValue,
            ContinuationSanitizationReason.repeatedPrefixRepaired.rawValue,
            ContinuationSanitizationReason.accepted.rawValue
        ]
        return priority.first(where: { reasons.contains($0) }) ?? reasons[0]
    }
}

private struct CandidateBuildResult {
    var candidate: AIRecommendationCandidate?
    var acceptedCount: Int
    var rejectionReasons: [String]
    var repairedCount: Int
}

func withTimeout<T: Sendable>(
    nanoseconds: UInt64,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let race = TimeoutRace<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            guard race.setContinuation(continuation) else {
                return
            }
            let operationTask = Task {
                do {
                    let value = try await operation()
                    race.complete(.success(value))
                } catch {
                    race.complete(.failure(error))
                }
            }
            let timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                    race.complete(.failure(TimeoutError()))
                } catch {
                    return
                }
            }
            race.setTasks([operationTask, timeoutTask])
        }
    } onCancel: {
        race.cancel()
    }
}

private final class TimeoutRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var tasks: [Task<Void, Never>] = []
    private var completed = false

    func setContinuation(_ continuation: CheckedContinuation<T, Error>) -> Bool {
        lock.lock()
        if completed {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func setTasks(_ tasks: [Task<Void, Never>]) {
        lock.lock()
        if completed {
            lock.unlock()
            tasks.forEach { $0.cancel() }
            return
        }
        self.tasks = tasks
        lock.unlock()
    }

    func complete(_ result: Result<T, Error>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let continuation = continuation
        self.continuation = nil
        let tasks = tasks
        self.tasks = []
        lock.unlock()

        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }

    func cancel() {
        complete(.failure(CancellationError()))
    }
}
