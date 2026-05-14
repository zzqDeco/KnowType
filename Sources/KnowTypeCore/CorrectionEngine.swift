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
            localCandidates(for: raw, locale: context.locale, protectedRanges: protectedRanges)
        )
    }

    public func correct(_ context: InputContext) async -> [CorrectionCandidate] {
        let raw = context.rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates = localCorrect(context)

        if shouldAskCloud(context: context), let cloudProvider {
            let request = LLMRequest(
                task: .correction,
                rawInput: raw,
                locale: context.locale,
                appContext: context.appBundleID,
                maxCandidates: 6
            )
            if let cloud = try? await cloudProvider.complete(request) {
                let cloudCandidates = cloud.candidates.map {
                    CorrectionCandidate(
                        text: $0.text,
                        source: cloudProvider.providerName,
                        confidence: cloudCorrectionConfidence(
                            $0.confidence,
                            rawInput: raw,
                            locale: context.locale
                        ),
                        correctionLevel: cloudCorrectionLevel(for: raw, locale: context.locale),
                        protectedRanges: TextProtection.detectProtectedRanges(in: $0.text)
                    )
                }
                candidates.append(contentsOf: cloudCandidates)
            }
        }

        return uniqueSorted(candidates)
    }

    private func shouldAskCloud(context: InputContext) -> Bool {
        if TextProtection.requiresNoCorrection(context.rawInput, appBundleID: context.appBundleID) {
            return false
        }
        if usesTraditionalInput(locale: context.locale),
           isLikelyPinyinCompositionInput(
               context.rawInput,
               traditionalInputEngine: traditionalInputEngine,
               locale: context.locale
           ) {
            return true
        }
        let tokenCount = correctionTokenCount(context.rawInput, locale: context.locale)
        return tokenCount >= 4 || context.locale == .mixed
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
                            protectedRanges: TextProtection.detectProtectedRanges(in: candidate.text)
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
        var bestByText: [String: CorrectionCandidate] = [:]
        for candidate in candidates {
            guard let existing = bestByText[candidate.text] else {
                bestByText[candidate.text] = candidate
                continue
            }
            if candidate.confidence > existing.confidence {
                bestByText[candidate.text] = candidate
            }
        }
        return Array(bestByText.values)
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
}

private func cloudCorrectionLevel(for rawInput: String, locale: KnowTypeLocale) -> CorrectionLevel {
    if usesTraditionalInput(locale: locale),
       isLikelyPinyinCompositionInput(rawInput, traditionalInputEngine: TraditionalInputEngine(), locale: locale) {
        return .contextual
    }
    return .strongAlternative
}

private func cloudCorrectionConfidence(
    _ providerConfidence: Double?,
    rawInput: String,
    locale: KnowTypeLocale
) -> Double {
    let confidence = providerConfidence ?? 0.62
    if usesTraditionalInput(locale: locale),
       isLikelyPinyinCompositionInput(rawInput, traditionalInputEngine: TraditionalInputEngine(), locale: locale) {
        return min(confidence, 0.86)
    }
    return confidence
}

private let spellingCorrections: [String: String] = [
    "thikn": "think",
    "approch": "approach",
    "latnecy": "latency"
]

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

private func isLikelyPinyinInitialAbbreviation(_ raw: String) -> Bool {
    let words = tokenizeWords(raw)
    guard words.count == 1,
          let word = words.first,
          (2...6).contains(word.count) else {
        return false
    }

    return word.unicodeScalars.allSatisfy { scalar in
        scalar.value < 128 && pinyinInitialScalars.contains(scalar)
    }
}

private let pinyinInitialScalars = Set("bpmfdtnlgkhjqxzcsryw".unicodeScalars)

private func isLikelyPinyinCompositionInput(
    _ raw: String,
    traditionalInputEngine: TraditionalInputEngine,
    locale: KnowTypeLocale
) -> Bool {
    if isLikelyPinyinInitialAbbreviation(raw) {
        return true
    }
    if traditionalInputEngine.canCompletePinyinPrefix(
        for: raw,
        preserveCapitalizedPinyin: preservesCapitalizedPinyin(locale: locale)
    ) {
        return true
    }
    return isLikelyUncoveredCompactPinyinFragment(raw)
}

private func isLikelyUncoveredCompactPinyinFragment(_ raw: String) -> Bool {
    let words = tokenizeWords(raw)
    guard words.count == 1,
          let word = words.first,
          (4...24).contains(word.count) else {
        return false
    }
    if TextProtection.canonicalTechnicalToken(word) != nil || preservesCodeLikeToken(word) {
        return false
    }

    let lower = word.lowercased()
    guard lower == word,
          lower.unicodeScalars.allSatisfy({ scalar in
              scalar.value < 128 && CharacterSet.lowercaseLetters.contains(scalar)
          }) else {
        return false
    }

    return pinyinFragmentSignals.contains { lower.contains($0) }
}

private let pinyinFragmentSignals = [
    "zh", "ch", "sh",
    "iang", "iong", "uang", "eng", "ang", "ong",
    "ian", "iao", "ing", "uai", "uan", "ue",
    "ai", "ei", "ao", "ou"
]

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
