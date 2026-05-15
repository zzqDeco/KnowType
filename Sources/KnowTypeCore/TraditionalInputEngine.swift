import Foundation

public struct TraditionalInputCandidate: Codable, Sendable, Equatable {
    public var text: String
    public var confidence: Double
    public var inputTokens: [String]

    public init(text: String, confidence: Double, inputTokens: [String]) {
        self.text = text
        self.confidence = confidence
        self.inputTokens = inputTokens
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

    public init(scheme: Scheme = .fullPinyin) {
        self.scheme = scheme
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
                        text: joinSegments(state.segments),
                        confidence: state.confidence * tokenizationConfidence(tokens),
                        inputTokens: tokens.map(\.surface)
                    )
                }
        }

        return uniqueSorted(parsed)
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
        let separated = rawInput
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        if separated.count > 1 {
            var paths: [[InputToken]] = [[]]
            for component in separated {
                let componentPaths = tokenizations(forComponent: component, allowCompactSegmentation: false)
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

        if isPassthroughToken(token) {
            return [[InputToken(
                surface: token,
                normalized: token,
                isTypoNormalized: false,
                isPartial: false
            )]]
        }

        return tokenizations(forComponent: token, allowCompactSegmentation: true)
    }

    private func tokenizations(
        forComponent token: String,
        allowCompactSegmentation: Bool
    ) -> [[InputToken]] {
        if isPassthroughToken(token) {
            return [[InputToken(
                surface: token,
                normalized: token,
                isTypoNormalized: false,
                isPartial: false
            )]]
        }

        if !allowCompactSegmentation {
            let normalized = normalize(token)
            return [[InputToken(
                surface: token,
                normalized: normalized,
                isTypoNormalized: isTypo(token),
                isPartial: isPartialPinyinComponent(normalized)
            )]]
        }

        return segmentCompact(token)
    }

    private func segmentCompact(_ token: String) -> [[InputToken]] {
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
                    isTypoNormalized: isTypo(remaining),
                    isPartial: false
                )
                memo[index] = [[token]]
                return [[token]]
            }

            var results: [[InputToken]] = []
            for key in compactSegmentKeys where suffix.hasPrefix(key) {
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
                        states.append(
                            ParseState(
                                segments: [output.text] + tail.segments,
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
                states.append(
                    ParseState(
                        segments: [passthrough] + tail.segments,
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
        return isInitialToken(token) && remainingTokens.allSatisfy(isInitialToken)
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

    private var compactSegmentKeys: [String] {
        switch scheme {
        case .fullPinyin:
            return Self.fullPinyinCompactSegmentKeys
        case .xiaohe:
            return Self.xiaoheCompactSegmentKeys
        }
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

    private static let fullPinyinCompactSegmentKeys: [String] = {
        let keys = pinyinSyllables
            .union(lexiconIndex.knownInputTokens)
            .union(pinyinTypoCorrections.keys)
            .union(pinyinInitialTokens)
        return keys.sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs < rhs
            }
            return lhs.count > rhs.count
        }
    }()

    private static let xiaoheCompactSegmentKeys: [String] = {
        let keys = Set(xiaoheSyllables.keys).union(fullPinyinCompactSegmentKeys)
        return keys.sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs < rhs
            }
            return lhs.count > rhs.count
        }
    }()
}

private struct InputToken: Sendable, Equatable {
    var surface: String
    var normalized: String
    var isTypoNormalized: Bool
    var isPartial: Bool
}

private struct ParseState: Sendable, Equatable {
    var segments: [String]
    var confidence: Double
    var translatedCount: Int
}

private struct LexiconEntry: Sendable, Equatable {
    var pinyin: [String]
    var outputs: [LexiconOutput]
}

private struct LexiconOutput: Sendable, Equatable {
    var text: String
    var confidence: Double
}

private struct LexiconIndex: Sendable {
    var exactByKey: [String: LexiconEntry]
    var entriesByLength: [Int: [LexiconEntry]]
    var entriesByLengthAndFirstToken: [Int: [String: [LexiconEntry]]]
    var knownInputTokens: Set<String>
    var maxEntryLength: Int
    var partialMatchLimit: Int

    init(entries: [LexiconEntry], partialMatchLimit: Int = 64) {
        var exactByKey: [String: LexiconEntry] = [:]
        var orderedKeys: [String] = []
        var entriesByLength: [Int: [LexiconEntry]] = [:]
        var entriesByLengthAndFirstToken: [Int: [String: [LexiconEntry]]] = [:]
        var knownInputTokens = Set<String>()
        var maxEntryLength = 1

        for entry in entries {
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
        }

        self.exactByKey = exactByKey
        self.entriesByLength = entriesByLength
        self.entriesByLengthAndFirstToken = entriesByLengthAndFirstToken
        self.knownInputTokens = knownInputTokens
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

private let lexicon: [LexiconEntry] = [
    entry(["s", "m"], [("什么", 0.99), ("是吗", 0.74)]),
    entry(["z", "m"], [("怎么", 0.98), ("在吗", 0.70)]),
    entry(["z", "m", "b"], [("怎么办", 0.99)]),
    entry(["z", "m", "y"], [("怎么样", 0.98)]),
    entry(["w", "s", "m"], [("为什么", 0.99), ("为啥么", 0.55)]),
    entry(["wo", "jue", "de"], [("我觉得", 0.99)]),
    entry(["wo", "jue"], [("我觉得", 0.94)]),
    entry(["wo", "xiang", "qu"], [("我想去", 0.98)]),
    entry(["wo", "xiang", "qu", "kan"], [("我想去看", 0.99)]),
    entry(["wo", "xiang"], [("我想", 0.99)]),
    entry(["wo", "men"], [("我们", 0.99)]),
    entry(["jue", "de"], [("觉得", 0.96)]),
    entry(["zhege"], [("这个", 0.99)]),
    entry(["zhe", "ge"], [("这个", 0.98)]),
    entry(["zhe"], [("这", 0.96), ("着", 0.74), ("者", 0.68)]),
    entry(["ge"], [("个", 0.98), ("各", 0.76), ("哥", 0.70)]),
    entry(["fangan"], [
        ("方案", 0.99),
        ("方法", 0.84),
        ("方向", 0.80),
        ("计划", 0.68),
        ("思路", 0.64)
    ]),
    entry(["fangfa"], [("方法", 0.98)]),
    entry(["fangxiang"], [("方向", 0.98)]),
    entry(["fang", "an"], [("方案", 0.98)]),
    entry(["fang", "fa"], [("方法", 0.97)]),
    entry(["fang", "xiang"], [("方向", 0.97)]),
    entry(["fang"], [("方", 0.94), ("放", 0.86), ("房", 0.82), ("防", 0.78)]),
    entry(["gongneng"], [
        ("功能", 0.99),
        ("工具", 0.74),
        ("模块", 0.70)
    ]),
    entry(["gong", "neng"], [("功能", 0.98)]),
    entry(["bushi"], [("不是", 0.99)]),
    entry(["bu", "shi"], [("不是", 0.98)]),
    entry(["wending"], [("稳定", 0.99)]),
    entry(["wen", "ding"], [("稳定", 0.98)]),
    entry(["jiekou"], [("接口", 0.99)]),
    entry(["jie", "kou"], [("接口", 0.98)]),
    entry(["yan", "chi"], [("延迟", 0.99)]),
    entry(["yanchi"], [("延迟", 0.99)]),
    entry(["youdian"], [("有点", 0.99)]),
    entry(["you", "dian"], [("有点", 0.98)]),
    entry(["gao"], [("高", 0.99)]),
    entry(["ba"], [("把", 0.99)]),
    entry(["wenti"], [("问题", 0.99)]),
    entry(["wen", "ti"], [("问题", 0.98)]),
    entry(["xiugai"], [("修改", 0.99)]),
    entry(["xiu", "gai"], [("修改", 0.98)]),
    entry(["yixia"], [("一下", 0.99)]),
    entry(["yi", "xia"], [("一下", 0.98)]),
    entry(["xiang"], [("想", 0.96)]),
    entry(["shen", "me"], [("什么", 0.99)]),
    entry(["zen", "me"], [("怎么", 0.99)]),
    entry(["ni"], [
        ("你", 0.99),
        ("尼", 0.76),
        ("呢", 0.74),
        ("泥", 0.70),
        ("拟", 0.68),
        ("逆", 0.66),
        ("腻", 0.64),
        ("妮", 0.62),
        ("倪", 0.60),
        ("霓", 0.58),
        ("匿", 0.56),
        ("昵", 0.54)
    ]),
    entry(["shi"], [
        ("是", 0.99),
        ("时", 0.83),
        ("事", 0.82),
        ("使", 0.76),
        ("式", 0.74),
        ("试", 0.72),
        ("十", 0.70),
        ("实", 0.68),
        ("师", 0.66),
        ("市", 0.64),
        ("识", 0.62),
        ("史", 0.60)
    ]),
    entry(["shei"], [("谁", 0.99)]),
    entry(["shui"], [("谁", 0.92), ("水", 0.88), ("睡", 0.78)]),
    entry(["hao"], [
        ("好", 0.99),
        ("号", 0.72),
        ("耗", 0.60),
        ("浩", 0.58)
    ]),
    entry(["hai"], [("还", 0.96), ("海", 0.80), ("嗨", 0.72)]),
    entry(["hui"], [("会", 0.96), ("回", 0.88), ("灰", 0.70)]),
    entry(["he"], [("和", 0.96), ("何", 0.72), ("合", 0.70)]),
    entry(["hen"], [("很", 0.99), ("狠", 0.65), ("恨", 0.60)]),
    entry(["wo"], [("我", 0.98), ("窝", 0.70), ("握", 0.66), ("沃", 0.62)]),
    entry(["men"], [("们", 0.94), ("门", 0.76)]),
    entry(["de"], [("的", 0.99), ("得", 0.82), ("地", 0.80)]),
    entry(["zai"], [("在", 0.98), ("再", 0.88), ("载", 0.62)]),
    entry(["xian"], [
        ("现", 0.94),
        ("先", 0.90),
        ("线", 0.72),
        ("县", 0.68),
        ("显", 0.66),
        ("限", 0.64)
    ]),
    entry(["xian", "zai"], [("现在", 0.99), ("先在", 0.58)]),
    entry(["xian", "shi"], [("显示", 0.98), ("现实", 0.84), ("限时", 0.62)]),
    entry(["ni", "shi"], [("你是", 0.99), ("尼式", 0.52)]),
    entry(["ni", "shi", "shei"], [("你是谁", 0.995)]),
    entry(["ni", "hao"], [
        ("你好", 0.99),
        ("你号", 0.58)
    ]),
    entry(["nihao"], [
        ("你好", 0.95),
        ("你号", 0.57)
    ]),
    entry(["ni", "wo"], [("你我", 0.95)]),
    entry(["ma"], [("吗", 0.98), ("嘛", 0.86), ("马", 0.72)]),
    entry(["le"], [("了", 0.98), ("乐", 0.74)]),
    entry(["yi"], [("一", 0.97), ("以", 0.78), ("已", 0.76)]),
    entry(["you"], [("有", 0.97), ("又", 0.78), ("由", 0.72)]),
    entry(["jian"], [("见", 0.82), ("件", 0.80), ("间", 0.78), ("建", 0.76)]),
    entry(["kan"], [("看", 0.96), ("刊", 0.62)]),
    entry(["qu"], [("去", 0.98), ("区", 0.78), ("取", 0.74)]),
    entry(["qu", "kan"], [("去看", 0.98)]),
    entry(["ren"], [("人", 0.98), ("任", 0.76), ("认", 0.74)]),
    entry(["dao"], [("到", 0.96), ("道", 0.78), ("导", 0.68)]),
    entry(["guo"], [("过", 0.96), ("国", 0.84), ("果", 0.78)]),
    entry(["ke"], [("可", 0.92), ("课", 0.76), ("客", 0.70)]),
    entry(["yi", "ge"], [("一个", 0.98)]),
    entry(["mei", "you"], [("没有", 0.98)]),
    entry(["ke", "yi"], [("可以", 0.98)]),
    entry(["zhe", "yang"], [("这样", 0.98)]),
    entry(["na", "ge"], [("那个", 0.96)]),
    entry(["shi", "jie"], [("世界", 0.94)]),
    entry(["zhong"], [("中", 0.97), ("种", 0.78), ("重", 0.76)]),
    entry(["zhong", "guo"], [("中国", 0.99)]),
    entry(["zhong", "guo", "ren"], [("中国人", 0.99)]),
    entry(["zhong", "wen"], [("中文", 0.98)]),
    entry(["shu", "ru"], [("输入", 0.98)]),
    entry(["shu", "ru", "fa"], [("输入法", 0.99)])
]

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

private let lexiconIndex = LexiconIndex(entries: lexicon)

private let knownPinyinTokens: Set<String> = {
    pinyinSyllables.union(lexiconIndex.knownInputTokens)
}()

private func lexiconKey(_ pinyin: [String]) -> String {
    pinyin.joined(separator: "\u{1F}")
}

private func isKnownCompleteInputToken(_ token: String) -> Bool {
    pinyinSyllables.contains(token)
        || lexiconIndex.knownInputTokens.contains(token)
        || pinyinTypoCorrections[token] != nil
}

private func isPinyinPrefix(_ token: String) -> Bool {
    pinyinPrefixes.contains(token)
}

private func isPartialPinyinComponent(_ normalizedToken: String) -> Bool {
    if pinyinInitialTokens.contains(normalizedToken) {
        return true
    }
    return !isKnownCompleteInputToken(normalizedToken) && pinyinPrefixes.contains(normalizedToken)
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

private func entry(_ pinyin: [String], _ outputs: [(String, Double)]) -> LexiconEntry {
    LexiconEntry(
        pinyin: pinyin,
        outputs: outputs.map { text, confidence in
            LexiconOutput(text: text, confidence: confidence)
        }
    )
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
