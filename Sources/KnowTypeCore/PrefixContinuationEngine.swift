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
            if let response = try? await provider.complete(request) {
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
            }
        }

        return fallbackContinuations(for: lockedPrefix.text, lengthLevel: lengthLevel, maxCandidates: maxCandidates)
    }

    public static func sanitizeContinuation(_ text: String, lockedPrefix: String) -> String? {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = lockedPrefix.trimmingCharacters(in: .whitespacesAndNewlines)

        if candidate.hasPrefix(prefix) {
            candidate.removeFirst(prefix.count)
            candidate = trimJoiner(candidate)
        }

        if candidate == prefix || candidate.isEmpty {
            return nil
        }

        if candidate.hasPrefix("|") || candidate.hasPrefix("｜") {
            candidate.removeFirst()
            candidate = trimJoiner(candidate)
        }

        if candidate.hasPrefix(prefix) || candidate.isEmpty {
            return nil
        }

        return candidate
    }

    private func fallbackContinuations(
        for prefix: String,
        lengthLevel: ContinuationLengthLevel,
        maxCandidates: Int
    ) -> [ContinuationCandidate] {
        let zh = prefix.range(of: #"\p{Han}"#, options: .regularExpression) != nil
        let texts: [String]

        if zh {
            switch lengthLevel {
            case .short:
                texts = ["可行", "需要优化", "还有问题"]
            case .medium:
                texts = ["还有进一步优化空间", "在落地成本上可能偏高", "需要先验证核心假设"]
            case .long:
                texts = ["整体方向是可行的，但需要进一步明确具体的落地路径。"]
            }
        } else {
            switch lengthLevel {
            case .short:
                texts = ["works", "is feasible", "needs review"]
            case .medium:
                texts = ["still needs more validation", "could be simplified further", "may introduce extra complexity"]
            case .long:
                texts = ["is feasible, but we should validate the edge cases before moving forward."]
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

private func trimJoiner(_ value: String) -> String {
    value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "，,。.；;：:|｜")))
}
