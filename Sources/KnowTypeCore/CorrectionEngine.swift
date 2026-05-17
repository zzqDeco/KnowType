import Foundation

public final class CorrectionEngine: Sendable {
    private let cloudProvider: (any LLMProvider)?
    private let traditionalInputEngine: TraditionalInputEngine

    public init(
        cloudProvider: (any LLMProvider)? = nil,
        traditionalInputEngine: TraditionalInputEngine = TraditionalInputEngine()
    ) {
        self.cloudProvider = cloudProvider
        self.traditionalInputEngine = traditionalInputEngine
    }

    public func localCorrect(_ context: InputContext) -> [CorrectionCandidate] {
        let raw = context.rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let protectedRanges = TextProtection.detectProtectedRanges(in: raw)

        if TextProtection.requiresNoCorrection(raw, appBundleID: context.appBundleID) {
            return [
                CorrectionCandidate(
                    text: raw,
                    source: "local-protection",
                    confidence: 1.0,
                    correctionLevel: .none,
                    protectedRanges: protectedRanges
                )
            ]
        }

        return uniqueSorted(
            applySelectionHistory(
                context.userSelectionHistory,
                to: localCandidates(for: raw, locale: context.locale, protectedRanges: protectedRanges)
            )
        )
    }

    public func correct(_ context: InputContext) async -> [CorrectionCandidate] {
        let raw = context.rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates = localCorrect(context)
        let usesPinyinCompletionFallback = shouldAskCloudForPinyinCompletion(context: context)

        if shouldAskCloud(
            context: context,
            usesPinyinCompletionFallback: usesPinyinCompletionFallback
        ), let cloudProvider {
            let request = LLMRequest(
                task: .correction,
                rawInput: raw,
                locale: context.locale,
                appContext: context.appBundleID,
                maxCandidates: 6
            )
            if let cloud = try? await cloudProvider.complete(request) {
                let cloudCandidates = cloud.candidates.map {
                    let confidence = $0.confidence ?? 0.62
                    return CorrectionCandidate(
                        text: $0.text,
                        source: cloudProvider.providerName,
                        confidence: usesPinyinCompletionFallback ? max(confidence, 0.64) : confidence,
                        correctionLevel: usesPinyinCompletionFallback ? .contextual : .strongAlternative,
                        protectedRanges: TextProtection.detectProtectedRanges(in: $0.text)
                    )
                }
                candidates.append(contentsOf: cloudCandidates)
            }
        }

        return uniqueSorted(candidates)
    }

    private func shouldAskCloud(
        context: InputContext,
        usesPinyinCompletionFallback: Bool
    ) -> Bool {
        if TextProtection.requiresNoCorrection(context.rawInput, appBundleID: context.appBundleID) {
            return false
        }
        if usesPinyinCompletionFallback {
            return true
        }
        let tokenCount = correctionTokenCount(context.rawInput, locale: context.locale)
        return tokenCount >= 4 || context.locale == .mixed
    }

    private func shouldAskCloudForPinyinCompletion(context: InputContext) -> Bool {
        guard context.locale == .zhCN else {
            return false
        }
        if isStandaloneProtectedToken(context.rawInput) {
            return false
        }
        let analysis = traditionalInputEngine.analyzePinyinInput(
            context.rawInput,
            preserveCapitalizedPinyin: preservesCapitalizedPinyin(locale: context.locale)
        )
        if analysis.hasInitialAbbreviation && isEnglishLikeAllInitialWord(context.rawInput) {
            return false
        }
        return analysis.isLikelyPinyinComposition
            && !analysis.hasLocalCandidates
            && analysis.hasInitialAbbreviation
    }

    private func correctionTokenCount(_ rawInput: String, locale: KnowTypeLocale) -> Int {
        let words = tokenizeWords(rawInput)
        if words.count != 1 || !usesTraditionalInput(locale: locale) {
            return words.count
        }

        return traditionalInputEngine
            .candidates(
                for: rawInput,
                preserveCapitalizedPinyin: preservesCapitalizedPinyin(locale: locale)
            )
            .map(\.inputTokens.count)
            .max() ?? words.count
    }

    private func localCandidates(
        for raw: String,
        locale: KnowTypeLocale,
        protectedRanges: [ProtectedRange]
    ) -> [CorrectionCandidate] {
        let tokens = tokenizeWords(raw)
        guard !tokens.isEmpty else {
            return []
        }

        var candidates: [CorrectionCandidate] = []

        let normalizedTokens = tokens.map { normalizeToken($0, locale: locale) }
        let normalizedInput = normalizedTokens.joined(separator: " ")
        if usesTraditionalInput(locale: locale) {
            let preserveCapitalizedPinyin = preservesCapitalizedPinyin(locale: locale)
            let traditionalInputs = [normalizedInput, raw]
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { inputs, input in
                    if !inputs.contains(input) {
                        inputs.append(input)
                    }
                }

            for input in traditionalInputs {
                let normalizationBonus = input == normalizedInput && input != raw ? 0.01 : 0
                for candidate in traditionalInputEngine.candidates(
                    for: input,
                    preserveCapitalizedPinyin: preserveCapitalizedPinyin
                ) where candidate.text != raw {
                    candidates.append(
                        CorrectionCandidate(
                            text: candidate.text,
                            source: "local-traditional-input",
                            confidence: min(1.0, candidate.confidence + normalizationBonus),
                            correctionLevel: .contextual,
                            protectedRanges: TextProtection.detectProtectedRanges(in: candidate.text),
                            rawRange: candidate.rawRange,
                            segments: candidate.segments
                        )
                    )
                }
            }
        }

        let english = normalizedTokens.joined(separator: " ")
        if english != raw, isLikelyEnglish(raw), candidates.isEmpty {
            candidates.append(
                CorrectionCandidate(
                    text: english,
                    source: "local-spellcheck",
                    confidence: 0.88,
                    correctionLevel: .light,
                    protectedRanges: protectedRanges
                )
            )
        }

        if candidates.isEmpty {
            candidates.append(
                CorrectionCandidate(
                    text: raw,
                    source: "local-identity",
                    confidence: 0.5,
                    correctionLevel: .none,
                    protectedRanges: protectedRanges
                )
            )
        }

        return candidates
    }

    private func uniqueSorted(_ candidates: [CorrectionCandidate]) -> [CorrectionCandidate] {
        var seen = Set<String>()
        return candidates
            .filter { candidate in
                if seen.contains(candidate.text) {
                    return false
                }
                seen.insert(candidate.text)
                return true
            }
            .sorted {
                if $0.correctionLevel == .strongAlternative, $1.correctionLevel != .strongAlternative {
                    return false
                }
                if $1.correctionLevel == .strongAlternative, $0.correctionLevel != .strongAlternative {
                    return true
                }
                if $0.correctionLevel == $1.correctionLevel {
                    return $0.confidence > $1.confidence
                }
                return $0.confidence > $1.confidence
            }
    }

    private func applySelectionHistory(
        _ history: [String],
        to candidates: [CorrectionCandidate]
    ) -> [CorrectionCandidate] {
        let weights = selectionHistoryWeights(history)
        guard !weights.isEmpty else {
            return candidates
        }

        return candidates.map { candidate in
            guard let weight = weights[candidate.text] else {
                return candidate
            }
            var boosted = candidate
            boosted.confidence = min(1.0, boosted.confidence + weight)
            return boosted
        }
    }

    private func selectionHistoryWeights(_ history: [String]) -> [String: Double] {
        let cappedHistory = history
            .suffix(64)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cappedHistory.isEmpty else {
            return [:]
        }

        var weights: [String: Double] = [:]
        for (offset, text) in cappedHistory.reversed().enumerated() {
            let recency = max(0.0, 0.12 - Double(offset) * 0.01)
            weights[text, default: 0] += 0.08 + recency
        }
        return weights.mapValues { min($0, 0.28) }
    }
}

private let spellingCorrections: [String: String] = [
    "thikn": "think",
    "approch": "approach",
    "latnecy": "latency"
]

private func isEnglishLikeAllInitialWord(_ rawInput: String) -> Bool {
    let lower = rawInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard lower.count >= 2,
          lower.range(of: #"^[a-z]+$"#, options: .regularExpression) != nil else {
        return false
    }
    guard lower.allSatisfy({ character in
        pinyinInitialTokens.contains(String(character))
    }) else {
        return false
    }

    let finalYConsonants = "bcdfghjklmnpqrstvwxz"
    if matchesEntire(lower, #"^[\#(finalYConsonants)]{1,3}y$"#) {
        return true
    }

    let medialYOnsets = "bcdfghjklmnpqrstvxz"
    let medialYRimes = "(?:m|n[bcdfghjklmnpqrstvwxz]?|p[st]?|s[st]?|t[hl]?|ck|ll|ph)"
    return matchesEntire(lower, #"^[\#(medialYOnsets)]{1,2}y\#(medialYRimes)$"#)
}

private func isStandaloneProtectedToken(_ rawInput: String) -> Bool {
    let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return false
    }
    let fullLength = trimmed.utf16.count
    let protectedReasons: Set<String> = ["acronym", "camelCase", "snake_case", "technical_term"]
    return TextProtection.detectProtectedRanges(in: trimmed).contains { range in
        range.start == 0 && range.length == fullLength && protectedReasons.contains(range.reason)
    }
}

private func matchesEntire(_ text: String, _ pattern: String) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
}

private func usesTraditionalInput(locale: KnowTypeLocale) -> Bool {
    locale != .enUS
}

private func preservesCapitalizedPinyin(locale: KnowTypeLocale) -> Bool {
    locale != .zhCN
}

private func tokenizeWords(_ raw: String) -> [String] {
    raw
        .split(whereSeparator: { $0.isWhitespace })
        .map(String.init)
}

private func normalizeToken(_ token: String, locale: KnowTypeLocale) -> String {
    if token == "I" {
        return "I"
    }
    if let technical = TextProtection.canonicalTechnicalToken(token) {
        return technical
    }
    if preservesCodeLikeToken(token) {
        return token
    }

    let lower = token.lowercased()
    if let correction = spellingCorrections[lower] {
        return applyCapitalization(from: token, to: correction)
    }
    if preservesCapitalizedPinyin(locale: locale), preservesCapitalizedWord(token) {
        return token
    }
    return lower
}

private func preservesCodeLikeToken(_ token: String) -> Bool {
    token.range(of: #"^[a-z]+_[A-Za-z0-9_]+$"#, options: .regularExpression) != nil
        || token.range(of: #"^[a-z]+[A-Z][A-Za-z0-9]*$"#, options: .regularExpression) != nil
}

private func preservesCapitalizedWord(_ token: String) -> Bool {
    guard token.count > 1,
          let first = token.unicodeScalars.first,
          CharacterSet.uppercaseLetters.contains(first) else {
        return false
    }
    return token.unicodeScalars.allSatisfy { scalar in
        scalar.value < 128 && CharacterSet.letters.contains(scalar)
    }
}

private func applyCapitalization(from source: String, to correction: String) -> String {
    if isAllUppercaseASCIIWord(source) {
        return correction.uppercased()
    }
    if preservesCapitalizedWord(source) {
        guard let first = correction.first else {
            return correction
        }
        return String(first).uppercased() + correction.dropFirst()
    }
    return correction
}

private func isAllUppercaseASCIIWord(_ token: String) -> Bool {
    guard token.count > 1 else {
        return false
    }
    return token.unicodeScalars.allSatisfy { scalar in
        scalar.value < 128 && CharacterSet.uppercaseLetters.contains(scalar)
    }
}

private func isLikelyEnglish(_ raw: String) -> Bool {
    raw.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
}
