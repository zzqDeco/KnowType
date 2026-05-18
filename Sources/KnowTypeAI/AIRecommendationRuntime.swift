import Foundation
import KnowTypeCore
import KnowTypeProviders

public actor AIRecommendationRuntime: AIRecommendationProviding {
    private struct CacheKey: Hashable {
        var lockedPrefix: String
        var appBundleID: String
        var localeRawValue: String
        var environmentHash: String
        var correctionHash: String
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
    private let cacheTTL: TimeInterval
    private var cache: [CacheKey: CacheEntry] = [:]

    public init(
        provider: (any LLMProvider)?,
        environmentStore: EnvironmentDocumentStore = EnvironmentDocumentStore(),
        correctionStore: CorrectionInstructionStore = CorrectionInstructionStore(),
        healthMonitor: AIHealthMonitor = AIHealthMonitor(),
        debounceMilliseconds: Int = 120,
        hardTimeoutMilliseconds: Int = 2_500,
        cacheTTL: TimeInterval = 300
    ) {
        self.provider = provider
        self.environmentStore = environmentStore
        self.correctionStore = correctionStore
        self.healthMonitor = healthMonitor
        self.debounceNanoseconds = UInt64(max(0, debounceMilliseconds)) * 1_000_000
        self.hardTimeoutNanoseconds = UInt64(max(1, hardTimeoutMilliseconds)) * 1_000_000
        self.cacheTTL = max(1, cacheTTL)
    }

    public func recommendation(for request: AIRecommendationRequest) async -> AIRecommendationState {
        guard let provider else {
            return .unavailable(reason: "AI 未配置")
        }
        if let reason = await healthMonitor.unavailableReason() {
            return .unavailable(reason: reason)
        }
        guard !request.rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.traditionalCandidate.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .ineligible(reason: "AI 不适用")
        }
        if TextProtection.requiresNoCorrection(request.rawInput, appBundleID: request.appBundleID)
            || TextProtection.requiresNoCorrection(request.traditionalCandidate.text, appBundleID: request.appBundleID) {
            return .ineligible(reason: "AI 已禁用")
        }

        do {
            if debounceNanoseconds > 0 {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            try Task.checkCancellation()
            let environment = try environmentStore.loadSnapshot()
            let correction = try correctionStore.loadSnapshot()
            let key = CacheKey(
                lockedPrefix: request.traditionalCandidate.text,
                appBundleID: request.appBundleID ?? "",
                localeRawValue: request.locale.rawValue,
                environmentHash: environment.sha256,
                correctionHash: correction.sha256
            )
            if let cached = cache[key], cached.expiresAt > Date() {
                return .ready(cached.candidate)
            }

            let llmRequest = LLMRequest(
                task: .continuation,
                lockedPrefix: request.traditionalCandidate.text,
                rawInput: request.rawInput,
                locale: request.locale,
                appContext: request.appBundleID,
                maxCandidates: 1,
                lengthLevel: .medium,
                contextDocuments: [
                    "ENV.md": environment.content,
                    "CORRECTION.md": correction.content
                ]
            )
            let response = try await withTimeout(nanoseconds: hardTimeoutNanoseconds) {
                try await provider.complete(llmRequest)
            }
            guard let candidate = Self.makeCandidate(
                response: response,
                lockedPrefix: request.traditionalCandidate.text,
                providerName: provider.providerName,
                contextVersion: "\(environment.sha256.prefix(12)):\(correction.sha256.prefix(12))"
            ) else {
                throw ProviderError.invalidResponse("empty AI recommendation")
            }
            cache[key] = CacheEntry(candidate: candidate, expiresAt: Date().addingTimeInterval(cacheTTL))
            await healthMonitor.recordSuccess()
            return .ready(candidate)
        } catch is CancellationError {
            return .idle
        } catch {
            await healthMonitor.recordFailure(error)
            if error is TimeoutError {
                return .unavailable(reason: "AI 请求超时")
            }
            return .unavailable(reason: "AI 暂不可用")
        }
    }

    private static func makeCandidate(
        response: LLMResponse,
        lockedPrefix: String,
        providerName: String,
        contextVersion: String
    ) -> AIRecommendationCandidate? {
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
            return AIRecommendationCandidate(
                prefixText: lockedPrefix,
                continuationText: continuation,
                displayText: displayText,
                confidence: rawCandidate.confidence ?? 0.7,
                provider: providerName,
                contextVersion: contextVersion
            )
        }
        return nil
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
}

private func withTimeout<T: Sendable>(
    nanoseconds: UInt64,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: nanoseconds)
            throw TimeoutError()
        }
        guard let result = try await group.next() else {
            throw TimeoutError()
        }
        group.cancelAll()
        return result
    }
}
