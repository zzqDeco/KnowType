import Foundation

public struct TraditionalInputCandidate: Codable, Sendable, Equatable {
    public var text: String
    public var confidence: Double
    public var inputTokens: [String]
    public var rawRange: TextRange?
    public var segments: [CandidateSegment]

    public init(
        text: String,
        confidence: Double,
        inputTokens: [String],
        rawRange: TextRange? = nil,
        segments: [CandidateSegment] = []
    ) {
        self.text = text
        self.confidence = confidence
        self.inputTokens = inputTokens
        self.rawRange = rawRange
        self.segments = segments
    }
}

public struct TraditionalInputLexiconEntry: Codable, Sendable, Equatable {
    public var pinyin: [String]
    public var outputs: [TraditionalInputLexiconOutput]

    public init(pinyin: [String], outputs: [TraditionalInputLexiconOutput]) {
        self.pinyin = pinyin
        self.outputs = outputs
    }
}

public struct TraditionalInputLexiconOutput: Codable, Sendable, Equatable {
    public var text: String
    public var confidence: Double

    public init(text: String, confidence: Double) {
        self.text = text
        self.confidence = confidence
    }
}

public struct PinyinInputAnalysis: Codable, Sendable, Equatable {
    public var tokenCount: Int
    public var hasPartialToken: Bool
    public var hasInitialAbbreviation: Bool
    public var hasLocalCandidates: Bool
    public var isLikelyPinyinComposition: Bool

    public init(
        tokenCount: Int,
        hasPartialToken: Bool,
        hasInitialAbbreviation: Bool,
        hasLocalCandidates: Bool,
        isLikelyPinyinComposition: Bool
    ) {
        self.tokenCount = tokenCount
        self.hasPartialToken = hasPartialToken
        self.hasInitialAbbreviation = hasInitialAbbreviation
        self.hasLocalCandidates = hasLocalCandidates
        self.isLikelyPinyinComposition = isLikelyPinyinComposition
    }
}

public struct TraditionalInputEngine: Sendable {
    public enum Scheme: String, Codable, Sendable, Equatable {
        case fullPinyin
        case xiaohe
    }

    private let scheme: Scheme
    private let lexiconIndex: LexiconIndex
    private let compactSegmentKeys: [String]
    private let knownPinyinTokens: Set<String>

    public init(
        scheme: Scheme = .fullPinyin,
        additionalLexiconEntries: [TraditionalInputLexiconEntry] = []
    ) {
        self.scheme = scheme
        let seedEntries = TraditionalInputSeedLexicon.entries()
            .map(LexiconEntry.init(publicEntry:))
        let additionalEntries = additionalLexiconEntries
            .map(LexiconEntry.init(publicEntry:))
        let lexiconIndex = LexiconIndex(entries: seedEntries + additionalEntries)
        self.lexiconIndex = lexiconIndex
        self.knownPinyinTokens = pinyinSyllables.union(lexiconIndex.knownInputTokens)
        let fullPinyinKeys = pinyinSyllables
            .union(lexiconIndex.knownInputTokens)
            .union(pinyinTypoCorrections.keys)
            .union(pinyinInitialTokens)
        switch scheme {
        case .fullPinyin:
            self.compactSegmentKeys = Self.sortedCompactSegmentKeys(fullPinyinKeys)
        case .xiaohe:
            self.compactSegmentKeys = Self.sortedCompactSegmentKeys(Set(xiaoheSyllables.keys).union(fullPinyinKeys))
        }
    }

    public func candidates(
        for rawInput: String,
        preserveCapitalizedPinyin: Bool = true
    ) -> [TraditionalInputCandidate] {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let parsed = tokenizations(for: trimmed).flatMap { tokens in
            var memo: [Int: [ParseState]] = [:]
            return parse(
                tokens: tokens,
                from: 0,
                preserveCapitalizedPinyin: preserveCapitalizedPinyin,
                memo: &memo
            )
                .filter { $0.translatedCount > 0 }
                .map { state in
                    TraditionalInputCandidate(
                        text: joinSegments(state.segments.map(\.text)),
                        confidence: state.confidence * tokenizationConfidence(tokens),
                        inputTokens: tokens.map(\.surface),
                        rawRange: TextRange.covering(state.segments.map(\.rawRange)),
                        segments: state.segments
                    )
                }
        }

        return uniqueSorted(parsed)
    }

    public func segmentCandidates(
        for rawInput: String,
        activeRange: TextRange,
        preserveCapitalizedPinyin: Bool = true
    ) -> [TraditionalInputCandidate] {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !activeRange.isEmpty else {
            return []
        }

        let candidates = tokenizations(for: trimmed).flatMap { tokens -> [TraditionalInputCandidate] in
            guard let startIndex = tokens.firstIndex(where: { token in
                token.rawRange.intersects(activeRange) || token.rawRange.start == activeRange.start
            }) else {
                return []
            }

            var candidates: [TraditionalInputCandidate] = []
            let maxLength = min(lexiconIndex.maxEntryLength, tokens.count - startIndex)
            for length in stride(from: maxLength, through: 1, by: -1) {
                let tokenSlice = tokens[startIndex..<(startIndex + length)]
                guard let rawRange = TextRange.covering(tokenSlice.map(\.rawRange)),
                      activeRange.contains(rawRange) || rawRange.start == activeRange.start else {
                    continue
                }
                if preserveCapitalizedPinyin {
                    guard !tokenSlice.contains(where: { token in
                        isCapitalizedASCIIWord(token.surface) && knownPinyinTokens.contains(token.normalized)
                    }) else {
                        continue
                    }
                }

                let typoPenalty = tokenSlice.contains { $0.isTypoNormalized } ? 0.03 : 0
                let entries = lexiconIndex.matchingEntries(for: tokenSlice)
                for entry in entries {
                    let matchPenalty = typoPenalty + partialMatchPenalty(entry: entry, tokens: tokenSlice)
                    let reading = tokenSlice.map(\.normalized).joined(separator: " ")
                    for output in entry.outputs {
                        let segment = CandidateSegment(
                            rawRange: rawRange,
                            tokenRange: TextRange(start: startIndex, length: length),
                            reading: reading,
                            text: output.text,
                            isPassthrough: false
                        )
                        candidates.append(
                            TraditionalInputCandidate(
                                text: output.text,
                                confidence: max(0.01, output.confidence - matchPenalty),
                                inputTokens: tokenSlice.map(\.surface),
                                rawRange: rawRange,
                                segments: [segment]
                            )
                        )
                    }
                }
            }
            return candidates
        }

        return uniqueSorted(candidates)
    }

    public func analyzePinyinInput(
        _ rawInput: String,
        preserveCapitalizedPinyin: Bool = true
    ) -> PinyinInputAnalysis {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPassthroughToken(trimmed) else {
            return PinyinInputAnalysis(
                tokenCount: 0,
                hasPartialToken: false,
                hasInitialAbbreviation: false,
                hasLocalCandidates: false,
                isLikelyPinyinComposition: false
            )
        }

        let tokenPaths = tokenizations(for: trimmed)
        let localCandidates = candidates(
            for: trimmed,
            preserveCapitalizedPinyin: preserveCapitalizedPinyin
        )
        let tokenCount = max(
            tokenPaths.map(\.count).max() ?? 0,
            localCandidates.map(\.inputTokens.count).max() ?? 0
        )
        let hasPartialToken = tokenPaths.contains { path in
            path.contains(where: \.isPartial)
        }
        let hasInitialAbbreviation = tokenPaths.contains { path in
            path.count >= 2 && path.allSatisfy { pinyinInitialTokens.contains($0.normalized) }
        }
        let hasLocalCandidates = !localCandidates.isEmpty
        let hasPinyinShape = tokenCount >= 2 && (hasLocalCandidates || hasInitialAbbreviation)

        return PinyinInputAnalysis(
            tokenCount: tokenCount,
            hasPartialToken: hasPartialToken,
            hasInitialAbbreviation: hasInitialAbbreviation,
            hasLocalCandidates: hasLocalCandidates,
            isLikelyPinyinComposition: hasPinyinShape
        )
    }

    private func tokenizations(for rawInput: String) -> [[InputToken]] {
        let separated = rawComponents(in: rawInput)

        if separated.count > 1 {
            var paths: [[InputToken]] = [[]]
            for component in separated {
                let componentPaths = tokenizations(
                    forComponent: component.surface,
                    rawRange: component.rawRange,
                    allowCompactSegmentation: false
                )
                guard !componentPaths.isEmpty else {
                    return []
                }
                paths = combine(paths, with: componentPaths, limit: 16)
            }
            return paths
        }

        guard let token = separated.first else {
            return []
        }

        if isPassthroughToken(token.surface) {
            return [[InputToken(
                surface: token.surface,
                normalized: token.surface,
                rawRange: token.rawRange,
                isTypoNormalized: false,
                isPartial: false
            )]]
        }

        return tokenizations(
            forComponent: token.surface,
            rawRange: token.rawRange,
            allowCompactSegmentation: true
        )
    }

    private func tokenizations(
        forComponent token: String,
        rawRange: TextRange,
        allowCompactSegmentation: Bool
    ) -> [[InputToken]] {
        if isPassthroughToken(token) {
            return [[InputToken(
                surface: token,
                normalized: token,
                rawRange: rawRange,
                isTypoNormalized: false,
                isPartial: false
            )]]
        }

        if !allowCompactSegmentation {
            let normalized = normalize(token)
            return [[InputToken(
                surface: token,
                normalized: normalized,
                rawRange: rawRange,
                isTypoNormalized: isTypo(token),
                isPartial: isPartialPinyinComponent(normalized)
            )]]
        }

        return segmentCompact(token, baseOffset: rawRange.start)
    }

    private func segmentCompact(_ token: String, baseOffset: Int) -> [[InputToken]] {
        let lower = token.lowercased()
        let end = lower.endIndex
        var memo: [String.Index: [[InputToken]]] = [:]

        func paths(from index: String.Index) -> [[InputToken]] {
            if index == end {
                return [[]]
            }
            if let cached = memo[index] {
                return cached
            }

            let suffix = lower[index...]
            let remaining = String(suffix)
            var results: [[InputToken]] = []
            if pinyinSyllables.contains(remaining) {
                let surface = originalSurface(
                    in: token,
                    lowercasedToken: lower,
                    from: index,
                    length: remaining.count
                )
                let token = InputToken(
                    surface: surface,
                    normalized: normalize(remaining),
                    rawRange: TextRange(start: baseOffset + offset(of: index, in: lower), length: remaining.count),
                    isTypoNormalized: isTypo(remaining),
                    isPartial: false
                )
                results.append([token])
            }

            for key in compactSegmentKeys where suffix.hasPrefix(key) {
                if key == remaining, pinyinSyllables.contains(remaining) {
                    continue
                }
                if pinyinSyllables.contains(remaining),
                   lexiconIndex.ambiguousCompactSplitPrefixes[remaining]?.contains(key) != true {
                    continue
                }
                let next = lower.index(index, offsetBy: key.count)
                let surface = originalSurface(
                    in: token,
                    lowercasedToken: lower,
                    from: index,
                    length: key.count
                )
                let token = InputToken(
                    surface: surface,
                    normalized: normalize(key),
                    rawRange: TextRange(start: baseOffset + offset(of: index, in: lower), length: key.count),
                    isTypoNormalized: isTypo(key),
                    isPartial: pinyinInitialTokens.contains(key)
                )
                for path in paths(from: next) {
                    results.append([token] + path)
                    if results.count >= 16 {
                        break
                    }
                }
                if results.count >= 16 {
                    break
                }
            }

            if isPinyinPrefix(remaining), !isKnownCompleteInputToken(remaining) {
                let surface = originalSurface(
                    in: token,
                    lowercasedToken: lower,
                    from: index,
                    length: remaining.count
                )
                results.append([
                    InputToken(
                        surface: surface,
                        normalized: remaining,
                        rawRange: TextRange(start: baseOffset + offset(of: index, in: lower), length: remaining.count),
                        isTypoNormalized: false,
                        isPartial: true
                    )
                ])
            }
            memo[index] = results
            return results
        }

        return paths(from: lower.startIndex)
    }

    private func parse(
        tokens: [InputToken],
        from index: Int,
        preserveCapitalizedPinyin: Bool,
        memo: inout [Int: [ParseState]]
    ) -> [ParseState] {
        if index >= tokens.count {
            return [ParseState(segments: [], confidence: 1.0, translatedCount: 0)]
        }
        if let cached = memo[index] {
            return cached
        }

        var states: [ParseState] = []

        for length in stride(from: min(lexiconIndex.maxEntryLength, tokens.count - index), through: 1, by: -1) {
            let tokenSlice = tokens[index..<(index + length)]
            if skipsSingleInitialBeforeAllInitialTail(
                tokenSlice,
                remainingTokens: tokens[(index + length)..<tokens.count]
            ) {
                continue
            }
            if preserveCapitalizedPinyin {
                guard !tokenSlice.contains(where: { token in
                    isCapitalizedASCIIWord(token.surface) && knownPinyinTokens.contains(token.normalized)
                }) else {
                    continue
                }
            }

            let entries = lexiconIndex.matchingEntries(for: tokenSlice)

            let typoPenalty = tokenSlice.contains { $0.isTypoNormalized } ? 0.03 : 0
            for entry in entries {
                let matchPenalty = typoPenalty + partialMatchPenalty(entry: entry, tokens: tokenSlice)
                for output in entry.outputs {
                    for tail in parse(
                        tokens: tokens,
                        from: index + length,
                        preserveCapitalizedPinyin: preserveCapitalizedPinyin,
                        memo: &memo
                    ) {
                        let rawRange = TextRange.covering(tokenSlice.map(\.rawRange))
                            ?? TextRange(start: 0, length: 0)
                        let segment = CandidateSegment(
                            rawRange: rawRange,
                            tokenRange: TextRange(start: index, length: length),
                            reading: tokenSlice.map(\.normalized).joined(separator: " "),
                            text: output.text,
                            isPassthrough: false
                        )
                        states.append(
                            ParseState(
                                segments: [segment] + tail.segments,
                                confidence: max(0.01, output.confidence - matchPenalty) * tail.confidence,
                                translatedCount: tail.translatedCount + 1
                            )
                        )
                    }
                }
            }
        }

        let token = tokens[index]
        if token.isPartial && index == tokens.count - 1 {
            states.append(ParseState(segments: [], confidence: 0.72, translatedCount: 0))
        }
        if let passthrough = passthroughText(
            for: token,
            preserveCapitalizedPinyin: preserveCapitalizedPinyin
        ) {
            for tail in parse(
                tokens: tokens,
                from: index + 1,
                preserveCapitalizedPinyin: preserveCapitalizedPinyin,
                memo: &memo
            ) {
                let segment = CandidateSegment(
                    rawRange: token.rawRange,
                    tokenRange: TextRange(start: index, length: 1),
                    reading: token.normalized,
                    text: passthrough,
                    isPassthrough: true
                )
                states.append(
                    ParseState(
                        segments: [segment] + tail.segments,
                        confidence: 0.96 * tail.confidence,
                        translatedCount: tail.translatedCount
                    )
                )
            }
        }

        let parsed = states
            .sorted { $0.confidence > $1.confidence }
            .prefix(120)
            .map { $0 }
        memo[index] = parsed
        return parsed
    }

    private func skipsSingleInitialBeforeAllInitialTail(
        _ tokens: ArraySlice<InputToken>,
        remainingTokens: ArraySlice<InputToken>
    ) -> Bool {
        guard !remainingTokens.isEmpty,
              tokens.count == 1,
              let token = tokens.first else {
            return false
        }
        guard isInitialToken(token), remainingTokens.allSatisfy(isInitialToken) else {
            return false
        }
        if remainingTokens.count >= 3,
           !lexiconIndex.matchingEntries(for: remainingTokens).isEmpty {
            return false
        }
        return true
    }

    private func partialMatchPenalty(entry: LexiconEntry, tokens: ArraySlice<InputToken>) -> Double {
        var penalty = 0.0
        for (entryToken, inputToken) in zip(entry.pinyin, tokens) where inputToken.isPartial {
            penalty += 0.04
            penalty += Double(max(0, entryToken.count - inputToken.normalized.count)) * 0.02
        }
        if entry.pinyin.count == 1, tokens.contains(where: \.isPartial) {
            penalty += 0.03
        }
        return penalty
    }

    private func normalize(_ token: String) -> String {
        let lower = token.lowercased()
        if scheme == .xiaohe, let fullPinyin = xiaoheSyllables[lower] {
            return fullPinyin
        }
        return pinyinTypoCorrections[lower] ?? lower
    }

    private func isTypo(_ token: String) -> Bool {
        pinyinTypoCorrections[token.lowercased()] != nil
    }

    private func passthroughText(
        for token: InputToken,
        preserveCapitalizedPinyin: Bool
    ) -> String? {
        if token.isPartial {
            return nil
        }
        if let technical = TextProtection.canonicalTechnicalToken(token.surface) {
            return technical
        }
        if let technical = TextProtection.canonicalTechnicalToken(token.normalized) {
            return technical
        }
        if isCodeLikeToken(token.surface) {
            return token.surface
        }
        if preserveCapitalizedPinyin,
           isCapitalizedASCIIWord(token.surface),
           knownPinyinTokens.contains(token.normalized) {
            return token.surface
        }
        if isASCIIWord(token.normalized), !knownPinyinTokens.contains(token.normalized) {
            return token.surface
        }
        return nil
    }

    private func isPassthroughToken(_ token: String) -> Bool {
        TextProtection.canonicalTechnicalToken(token) != nil || isCodeLikeToken(token)
    }

    private func isKnownCompleteInputToken(_ token: String) -> Bool {
        knownPinyinTokens.contains(token) || pinyinTypoCorrections[token] != nil
    }

    private func isPartialPinyinComponent(_ normalizedToken: String) -> Bool {
        if pinyinInitialTokens.contains(normalizedToken) {
            return true
        }
        return !isKnownCompleteInputToken(normalizedToken) && pinyinPrefixes.contains(normalizedToken)
    }

    private func uniqueSorted(_ candidates: [TraditionalInputCandidate]) -> [TraditionalInputCandidate] {
        let bestCandidates = candidates.reduce(into: [String: TraditionalInputCandidate]()) { bestByText, candidate in
            guard let existing = bestByText[candidate.text] else {
                bestByText[candidate.text] = candidate
                return
            }
            if candidate.confidence > existing.confidence {
                bestByText[candidate.text] = candidate
            }
        }
        return bestCandidates.values.sorted {
            if $0.confidence == $1.confidence {
                return $0.text < $1.text
            }
            return $0.confidence > $1.confidence
        }
    }

    private static func sortedCompactSegmentKeys(_ keys: Set<String>) -> [String] {
        keys.sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs < rhs
            }
            return lhs.count > rhs.count
        }
    }
}

private struct InputToken: Sendable, Equatable {
    var surface: String
    var normalized: String
    var rawRange: TextRange
    var isTypoNormalized: Bool
    var isPartial: Bool
}

private struct ParseState: Sendable, Equatable {
    var segments: [CandidateSegment]
    var confidence: Double
    var translatedCount: Int
}

private struct RawInputComponent: Sendable, Equatable {
    var surface: String
    var rawRange: TextRange
}

private struct LexiconEntry: Sendable, Equatable {
    var pinyin: [String]
    var outputs: [LexiconOutput]

    init(pinyin: [String], outputs: [LexiconOutput]) {
        self.pinyin = pinyin
        self.outputs = outputs
    }

    init(publicEntry: TraditionalInputLexiconEntry) {
        self.pinyin = publicEntry.pinyin
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        self.outputs = publicEntry.outputs.map(LexiconOutput.init(publicOutput:))
    }
}

private struct LexiconOutput: Sendable, Equatable {
    var text: String
    var confidence: Double

    init(text: String, confidence: Double) {
        self.text = text
        self.confidence = confidence
    }

    init(publicOutput: TraditionalInputLexiconOutput) {
        self.text = publicOutput.text
        self.confidence = publicOutput.confidence
    }
}

private struct LexiconIndex: Sendable {
    var exactByKey: [String: LexiconEntry]
    var entriesByLength: [Int: [LexiconEntry]]
    var entriesByLengthAndFirstToken: [Int: [String: [LexiconEntry]]]
    var knownInputTokens: Set<String>
    var ambiguousCompactSplitPrefixes: [String: Set<String>]
    var maxEntryLength: Int
    var partialMatchLimit: Int

    init(entries: [LexiconEntry], partialMatchLimit: Int = 64) {
        var exactByKey: [String: LexiconEntry] = [:]
        var orderedKeys: [String] = []
        var entriesByLength: [Int: [LexiconEntry]] = [:]
        var entriesByLengthAndFirstToken: [Int: [String: [LexiconEntry]]] = [:]
        var knownInputTokens = Set<String>()
        var ambiguousCompactSplitPrefixes: [String: Set<String>] = [:]
        var maxEntryLength = 1

        for entry in entries where !entry.pinyin.isEmpty && !entry.outputs.isEmpty {
            let key = lexiconKey(entry.pinyin)
            if let existing = exactByKey[key] {
                exactByKey[key] = Self.mergedEntry(existing, entry)
            } else {
                exactByKey[key] = entry
                orderedKeys.append(key)
            }
        }

        for key in orderedKeys {
            guard let entry = exactByKey[key] else {
                continue
            }
            entriesByLength[entry.pinyin.count, default: []].append(entry)
            if let firstToken = entry.pinyin.first {
                entriesByLengthAndFirstToken[entry.pinyin.count, default: [:]][firstToken, default: []].append(entry)
            }
            maxEntryLength = max(maxEntryLength, entry.pinyin.count)
            for token in entry.pinyin {
                knownInputTokens.insert(token)
            }
            if entry.pinyin.count > 1 {
                let compact = entry.pinyin.joined()
                if pinyinSyllables.contains(compact) {
                    var prefix = ""
                    for token in entry.pinyin.dropLast() {
                        prefix += token
                        ambiguousCompactSplitPrefixes[compact, default: []].insert(prefix)
                    }
                }
            }
        }

        self.exactByKey = exactByKey
        self.entriesByLength = entriesByLength
        self.entriesByLengthAndFirstToken = entriesByLengthAndFirstToken
        self.knownInputTokens = knownInputTokens
        self.ambiguousCompactSplitPrefixes = ambiguousCompactSplitPrefixes
        self.maxEntryLength = maxEntryLength
        self.partialMatchLimit = partialMatchLimit
    }

    func matchingEntries(for tokens: ArraySlice<InputToken>) -> [LexiconEntry] {
        let tokenArray = Array(tokens)
        let normalized = tokenArray.map(\.normalized)
        if !tokenArray.contains(where: \.isPartial),
           let entry = exactByKey[lexiconKey(normalized)] {
            return [entry]
        }

        return candidateEntries(for: tokenArray)
            .lazy
            .filter { entry in matches(entry, tokens: tokenArray) }
            .prefix(partialMatchLimit)
            .map { $0 }
    }

    private func candidateEntries(for tokens: [InputToken]) -> [LexiconEntry] {
        guard let firstToken = tokens.first else {
            return []
        }
        if firstToken.isPartial {
            return entriesByLength[tokens.count] ?? []
        }
        return entriesByLengthAndFirstToken[tokens.count]?[firstToken.normalized] ?? []
    }

    private func matches(_ entry: LexiconEntry, tokens: [InputToken]) -> Bool {
        guard entry.pinyin.count == tokens.count else {
            return false
        }
        for (entryToken, inputToken) in zip(entry.pinyin, tokens) {
            if inputToken.isPartial {
                guard entryToken.hasPrefix(inputToken.normalized) else {
                    return false
                }
            } else if entryToken != inputToken.normalized {
                return false
            }
        }
        return true
    }

    private static func mergedEntry(_ lhs: LexiconEntry, _ rhs: LexiconEntry) -> LexiconEntry {
        var outputOrder: [String] = []
        var outputsByText: [String: LexiconOutput] = [:]
        for output in lhs.outputs + rhs.outputs {
            if outputsByText[output.text] == nil {
                outputOrder.append(output.text)
                outputsByText[output.text] = output
            } else if let existing = outputsByText[output.text],
                      output.confidence > existing.confidence {
                outputsByText[output.text] = output
            }
        }
        let outputs = outputOrder.compactMap { outputsByText[$0] }
        return LexiconEntry(pinyin: lhs.pinyin, outputs: outputs)
    }
}

private let pinyinTypoCorrections: [String: String] = [
    "fagnan": "fangan",
    "faangan": "fangan",
    "fangam": "fangan",
    "fangn": "fangan"
]

private let xiaoheSyllables: [String: String] = [
    "ni": "ni",
    "hc": "hao",
    "wo": "wo",
    "ve": "zhe",
    "ge": "ge"
]

private func lexiconKey(_ pinyin: [String]) -> String {
    pinyin.joined(separator: "\u{1F}")
}

private func isPinyinPrefix(_ token: String) -> Bool {
    pinyinPrefixes.contains(token)
}

private func isInitialToken(_ token: InputToken) -> Bool {
    token.isPartial && pinyinInitialTokens.contains(token.normalized)
}

private func originalSurface(
    in originalToken: String,
    lowercasedToken: String,
    from lowerIndex: String.Index,
    length: Int
) -> String {
    let offset = lowercasedToken.distance(from: lowercasedToken.startIndex, to: lowerIndex)
    guard let originalStart = originalToken.index(
        originalToken.startIndex,
        offsetBy: offset,
        limitedBy: originalToken.endIndex
    ),
          let originalEnd = originalToken.index(
            originalStart,
            offsetBy: length,
            limitedBy: originalToken.endIndex
          ) else {
        let fallbackEnd = lowercasedToken.index(
            lowerIndex,
            offsetBy: length,
            limitedBy: lowercasedToken.endIndex
        ) ?? lowercasedToken.endIndex
        return String(lowercasedToken[lowerIndex..<fallbackEnd])
    }
    return String(originalToken[originalStart..<originalEnd])
}

private func combine(
    _ prefixPaths: [[InputToken]],
    with suffixPaths: [[InputToken]],
    limit: Int
) -> [[InputToken]] {
    var results: [[InputToken]] = []
    for prefix in prefixPaths {
        for suffix in suffixPaths {
            results.append(prefix + suffix)
            if results.count >= limit {
                return results
            }
        }
    }
    return results
}

private func tokenizationConfidence(_ tokens: [InputToken]) -> Double {
    tokens.reduce(1.0) { score, token in
        if token.isPartial {
            return score * 0.93
        }
        if pinyinInitialTokens.contains(token.normalized) {
            return score * 0.88
        }
        return score
    }
}

private func joinSegments(_ segments: [String]) -> String {
    var output = ""
    var previousWasASCII = false

    for segment in segments {
        let currentIsASCII = isASCIIWord(segment)
        if !output.isEmpty, (previousWasASCII || currentIsASCII) {
            output += " "
        }
        output += segment
        previousWasASCII = currentIsASCII
    }
    return output
}

private func rawComponents(in rawInput: String) -> [RawInputComponent] {
    var components: [RawInputComponent] = []
    var currentStart: String.Index?
    var currentOffset = 0
    var startOffset = 0

    for index in rawInput.indices {
        let character = rawInput[index]
        if character.isWhitespace {
            if let start = currentStart {
                let surface = String(rawInput[start..<index])
                components.append(
                    RawInputComponent(
                        surface: surface,
                        rawRange: TextRange(start: startOffset, length: currentOffset - startOffset)
                    )
                )
                currentStart = nil
            }
        } else if currentStart == nil {
            currentStart = index
            startOffset = currentOffset
        }
        currentOffset += 1
    }

    if let start = currentStart {
        let surface = String(rawInput[start..<rawInput.endIndex])
        components.append(
            RawInputComponent(
                surface: surface,
                rawRange: TextRange(start: startOffset, length: currentOffset - startOffset)
            )
        )
    }

    return components
}

private func offset(of index: String.Index, in string: String) -> Int {
    string.distance(from: string.startIndex, to: index)
}

private func isASCIIWord(_ text: String) -> Bool {
    guard !text.isEmpty else {
        return false
    }
    return text.unicodeScalars.allSatisfy { scalar in
        scalar.value < 128 && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-")
    }
}

private func isCodeLikeToken(_ token: String) -> Bool {
    token.range(of: #"^[a-z]+_[A-Za-z0-9_]+$"#, options: .regularExpression) != nil
        || token.range(of: #"^[a-z]+[A-Z][A-Za-z0-9]*$"#, options: .regularExpression) != nil
}

private func isCapitalizedASCIIWord(_ token: String) -> Bool {
    guard let first = token.unicodeScalars.first,
          CharacterSet.uppercaseLetters.contains(first) else {
        return false
    }
    return token.unicodeScalars.allSatisfy { scalar in
        scalar.value < 128 && CharacterSet.letters.contains(scalar)
    }
}
