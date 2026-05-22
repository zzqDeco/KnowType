import Foundation
import KnowTypeCore
import KnowTypeProviders

public actor AIRecommendationRuntime: AIRecommendationProviding {
    public enum Defaults {
        public static let hardTimeoutMilliseconds = 10_000
    }

    private struct CacheKey: Hashable {
        var lockedPrefix: String
        var rawInput: String
        var appBundleID: String
        var localeRawValue: String
        var environmentHash: String
        var correctionHash: String
        var lexicalHash: String
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
    private var cache: [CacheKey: CacheEntry] = [:]

    public init(
        provider: (any LLMProvider)?,
        environmentStore: EnvironmentDocumentStore = EnvironmentDocumentStore(),
        correctionStore: CorrectionInstructionStore = CorrectionInstructionStore(),
        healthMonitor: AIHealthMonitor = AIHealthMonitor(),
        debounceMilliseconds: Int = 120,
        hardTimeoutMilliseconds: Int = Defaults.hardTimeoutMilliseconds,
        diagnosticSink: any AIRecommendationDiagnosticSink = OSLogAIRecommendationDiagnosticSink(),
        cacheTTL: TimeInterval = 300
    ) {
        self.provider = provider
        self.environmentStore = environmentStore
        self.correctionStore = correctionStore
        self.healthMonitor = healthMonitor
        self.debounceNanoseconds = UInt64(max(0, debounceMilliseconds)) * 1_000_000
        self.hardTimeoutNanoseconds = UInt64(max(1, hardTimeoutMilliseconds)) * 1_000_000
        self.diagnosticSink = diagnosticSink
        self.cacheTTL = max(1, cacheTTL)
    }

    public func recommendation(for request: AIRecommendationRequest) async -> AIRecommendationState {
        let startedAt = Date()
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
        guard !request.rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.traditionalCandidate.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            record(
                .skippedIneligible,
                request: request,
                providerName: provider.providerName,
                elapsedSince: startedAt,
                reason: "empty_raw_or_prefix"
            )
            return .ineligible(reason: "AI 不适用")
        }
        if TextProtection.requiresNoCorrection(request.rawInput, appBundleID: request.appBundleID)
            || TextProtection.requiresNoCorrection(request.traditionalCandidate.text, appBundleID: request.appBundleID) {
            record(
                .skippedProtectedText,
                request: request,
                providerName: provider.providerName,
                elapsedSince: startedAt,
                reason: "protected_text"
            )
            return .ineligible(reason: "AI 已禁用")
        }

        do {
            if debounceNanoseconds > 0 {
                record(
                    .debounceStart,
                    request: request,
                    providerName: provider.providerName,
                    elapsedSince: startedAt
                )
                try await Task.sleep(nanoseconds: debounceNanoseconds)
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
            let key = CacheKey(
                lockedPrefix: request.traditionalCandidate.text,
                rawInput: request.rawInput,
                appBundleID: request.appBundleID ?? "",
                localeRawValue: request.locale.rawValue,
                environmentHash: environment.sha256,
                correctionHash: correction.sha256,
                lexicalHash: request.lexicalContext?.sha256 ?? ""
            )
            if let cached = cache[key], cached.expiresAt > Date() {
                record(
                    .cacheHit,
                    request: request,
                    providerName: provider.providerName,
                    elapsedSince: startedAt,
                    candidateCount: 1,
                    acceptedCount: 1
                )
                return .ready(cached.candidate)
            }
            record(
                .cacheMiss,
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

            let llmRequest = LLMRequest(
                task: .continuation,
                lockedPrefix: request.traditionalCandidate.text,
                rawInput: request.rawInput,
                locale: request.locale,
                appContext: request.appBundleID,
                maxCandidates: 1,
                lengthLevel: .medium,
                contextDocuments: contextDocuments
            )
            record(
                .providerRequestStart,
                request: request,
                providerName: provider.providerName,
                elapsedSince: startedAt
            )
            let providerStartedAt = Date()
            let response = try await withTimeout(nanoseconds: hardTimeoutNanoseconds) {
                try await provider.complete(llmRequest)
            }
            record(
                .providerResponse,
                request: request,
                providerName: provider.providerName,
                elapsedSince: providerStartedAt,
                candidateCount: response.candidates.count
            )
            guard let result = Self.makeCandidate(
                response: response,
                lockedPrefix: request.traditionalCandidate.text,
                providerName: provider.providerName,
                contextVersion: [
                    environment.sha256.prefix(12),
                    correction.sha256.prefix(12),
                    request.lexicalContext?.sha256.prefix(12)
                ]
                .compactMap { $0.map(String.init) }
                .joined(separator: ":")
            ) else {
                record(
                    .sanitizeEmpty,
                    request: request,
                    providerName: provider.providerName,
                    elapsedSince: startedAt,
                    candidateCount: response.candidates.count,
                    acceptedCount: 0,
                    reason: "no_usable_continuation"
                )
                await healthMonitor.recordSuccess()
                return .ineligible(reason: "AI 无推荐")
            }
            let candidate = result.candidate
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
        } catch is CancellationError {
            record(
                .cancelled,
                request: request,
                providerName: provider.providerName,
                elapsedSince: startedAt,
                reason: "task_cancelled"
            )
            return .idle
        } catch {
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

    private static func makeCandidate(
        response: LLMResponse,
        lockedPrefix: String,
        providerName: String,
        contextVersion: String
    ) -> (candidate: AIRecommendationCandidate, acceptedCount: Int)? {
        var acceptedCount = 0
        var firstCandidate: AIRecommendationCandidate?
        for rawCandidate in response.candidates {
            guard let continuation = PrefixContinuationEngine.sanitizeContinuation(
                rawCandidate.text,
                lockedPrefix: lockedPrefix
            ) else {
                continue
            }
            let displayText = join(prefix: lockedPrefix, continuation: continuation)
            guard displayText.hasPrefix(lockedPrefix) else {
                continue
            }
            acceptedCount += 1
            if firstCandidate == nil {
                firstCandidate = AIRecommendationCandidate(
                    prefixText: lockedPrefix,
                    continuationText: continuation,
                    displayText: displayText,
                    confidence: rawCandidate.confidence ?? 0.7,
                    provider: providerName,
                    contextVersion: contextVersion
                )
            }
        }
        guard let firstCandidate else {
            return nil
        }
        return (firstCandidate, acceptedCount)
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
                prefixLength: request.traditionalCandidate.text.count,
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
        case .invalidResponse:
            return "invalid_response"
        case .missingAPIKey:
            return "missing_api_key"
        case .invalidTemplate:
            return "invalid_template"
        case .unsupportedKind(let kind):
            return "unsupported_kind_\(kind.rawValue)"
        }
    }
}

private func withTimeout<T: Sendable>(
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
