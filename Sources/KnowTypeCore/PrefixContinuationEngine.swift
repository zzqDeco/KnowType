import Foundation

public final class PrefixContinuationEngine: Sendable {
    private let provider: (any LLMProvider)?

    public init(provider: (any LLMProvider)? = nil) {
        self.provider = provider
    }

    public func continuations(
        for lockedPrefix: LockedPrefix,
        context: InputContext? = nil,
        lengthLevel: ContinuationLengthLevel = .medium,
        maxCandidates: Int = 3
    ) async -> [ContinuationCandidate] {
        if TextProtection.requiresNoCorrection(lockedPrefix.text, appBundleID: context?.appBundleID) {
            return []
        }

        if let context,
           TextProtection.requiresNoCorrection(context.rawInput, appBundleID: context.appBundleID) {
            return []
        }

        if let provider {
            let request = LLMRequest(
                task: .continuation,
                lockedPrefix: lockedPrefix.text,
                rawInput: context?.rawInput,
                locale: context?.locale ?? .mixed,
                appContext: context?.appBundleID,
                maxCandidates: maxCandidates,
                lengthLevel: lengthLevel
            )
            do {
                let response = try await provider.complete(request)
                let sanitized = response.candidates.compactMap { candidate in
                    PrefixContinuationEngine.sanitizeContinuation(candidate.text, lockedPrefix: lockedPrefix.text).map { text in
                        ContinuationCandidate(
                            text: text,
                            lengthLevel: lengthLevel,
                            confidence: candidate.confidence ?? 0.7,
                            provider: provider.providerName,
                            reason: candidate.reason
                        )
                    }
                }
                if !sanitized.isEmpty {
                    return Array(unique(sanitized).prefix(maxCandidates))
                }
                return []
            } catch {
                return []
            }
        }

        return fallbackContinuations(for: lockedPrefix.text, lengthLevel: lengthLevel, maxCandidates: maxCandidates)
    }

    public static func sanitizeContinuation(_ text: String, lockedPrefix: String) -> String? {
        sanitizeContinuationDetailed(text, lockedPrefix: lockedPrefix).text
    }

    public static func sanitizeContinuationDetailed(
        _ text: String,
        lockedPrefix: String
    ) -> ContinuationSanitizationResult {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = lockedPrefix.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !candidate.isEmpty else {
            return ContinuationSanitizationResult(text: nil, reason: .empty)
        }
        guard !prefix.isEmpty else {
            return ContinuationSanitizationResult(text: candidate, reason: .accepted)
        }
        if candidate == prefix {
            return ContinuationSanitizationResult(text: nil, reason: .sameAsPrefix)
        }

        var repaired = false
        if candidate.hasPrefix(prefix) {
            candidate.removeFirst(prefix.count)
            candidate = trimJoiner(candidate)
            repaired = true
        }

        if candidate.isEmpty {
            return ContinuationSanitizationResult(text: nil, reason: .noUsableSuffix)
        }
        if candidate == prefix {
            return ContinuationSanitizationResult(text: nil, reason: .sameAsPrefix)
        }

        if candidate.hasPrefix("|") || candidate.hasPrefix("｜") {
            candidate.removeFirst()
            candidate = trimJoiner(candidate)
        }

        guard !candidate.isEmpty else {
            return ContinuationSanitizationResult(text: nil, reason: .noUsableSuffix)
        }
        if candidate.hasPrefix(prefix) {
            return ContinuationSanitizationResult(text: nil, reason: .stillRepeatsPrefix)
        }

        return ContinuationSanitizationResult(
            text: candidate,
            reason: repaired ? .repeatedPrefixRepaired : .accepted
        )
    }

    public static func hasTechnicalLatencySignal(_ text: String) -> Bool {
        if text.contains("延迟") {
            return true
        }

        let patterns = [
            #"(?i)(^|[^A-Za-z0-9_])API([^A-Za-z0-9_]|$)"#,
            #"(?i)(^|[^A-Za-z0-9_])latency([^A-Za-z0-9_]|$)"#
        ]
        return patterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }

    public func fallbackContinuations(
        for prefix: String,
        lengthLevel: ContinuationLengthLevel,
        maxCandidates: Int
    ) -> [ContinuationCandidate] {
        let zh = prefix.range(of: #"\p{Han}"#, options: .regularExpression) != nil
        let texts: [String]

        if zh {
            if Self.hasTechnicalLatencySignal(prefix) {
                let technicalTexts: [String]
                switch lengthLevel {
                case .short:
                    technicalTexts = ["需要排查", "可能偏慢", "先看链路", "看 P95", "查缓存", "查数据库"]
                case .medium:
                    technicalTexts = [
                        "需要进一步排查接口链路耗时",
                        "可能和数据库查询耗时有关",
                        "建议先看一下 P95 和 P99 延迟",
                        "可以先确认缓存命中率是否异常",
                        "需要把网关和服务端耗时拆开看",
                        "可能还要检查下游服务的响应时间"
                    ]
                case .long:
                    technicalTexts = [
                        "需要进一步排查接口链路耗时，并结合 P95 和 P99 延迟确认瓶颈。",
                        "可以先把网关、服务端和数据库耗时拆开，再判断主要瓶颈在哪里。",
                        "建议先确认缓存命中率和慢查询，再看是否存在下游服务阻塞。"
                    ]
                }
                return technicalTexts.prefix(maxCandidates).map {
                    ContinuationCandidate(
                        text: $0,
                        lengthLevel: lengthLevel,
                        confidence: 0.5,
                        provider: "local-fallback"
                    )
                }
            }
            switch lengthLevel {
            case .short:
                texts = ["可行", "需要优化", "还有问题", "可以推进", "需要评估", "先验证"]
            case .medium:
                texts = [
                    "还有进一步优化空间",
                    "在落地成本上可能偏高",
                    "需要先验证核心假设",
                    "可以先做一个小范围验证",
                    "需要进一步明确边界条件",
                    "整体方向可以继续推进"
                ]
            case .long:
                texts = [
                    "整体方向是可行的，但需要进一步明确具体的落地路径。",
                    "可以先做一个小范围验证，再根据反馈决定是否继续投入。",
                    "当前判断还需要更多数据支撑，否则后续实现风险会偏高。"
                ]
            }
        } else {
            switch lengthLevel {
            case .short:
                texts = ["works", "is feasible", "needs review", "looks reasonable", "needs cleanup", "can ship"]
            case .medium:
                texts = [
                    "still needs more validation",
                    "could be simplified further",
                    "may introduce extra complexity",
                    "needs a clearer rollout plan",
                    "should be tested against edge cases",
                    "looks reasonable for the MVP"
                ]
            case .long:
                texts = [
                    "is feasible, but we should validate the edge cases before moving forward.",
                    "could work for the MVP, but we should keep the rollout path narrow.",
                    "needs a bit more validation before we treat it as the default approach."
                ]
            }
        }

        return texts.prefix(maxCandidates).map {
            ContinuationCandidate(
                text: $0,
                lengthLevel: lengthLevel,
                confidence: 0.45,
                provider: "local-fallback"
            )
        }
    }

    private func unique(_ candidates: [ContinuationCandidate]) -> [ContinuationCandidate] {
        var seen = Set<String>()
        return candidates.filter {
            if seen.contains($0.text) {
                return false
            }
            seen.insert($0.text)
            return true
        }
    }
}

public enum ContinuationSanitizationReason: String, Codable, Sendable, Equatable {
    case accepted
    case empty
    case sameAsPrefix = "same_as_prefix"
    case repeatedPrefixRepaired = "repeated_prefix_repaired"
    case stillRepeatsPrefix = "still_repeats_prefix"
    case noUsableSuffix = "no_usable_suffix"
}

public struct ContinuationSanitizationResult: Codable, Sendable, Equatable {
    public var text: String?
    public var reason: ContinuationSanitizationReason

    public init(text: String?, reason: ContinuationSanitizationReason) {
        self.text = text
        self.reason = reason
    }
}

private func trimJoiner(_ value: String) -> String {
    value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "，,。.；;：:|｜")))
}
