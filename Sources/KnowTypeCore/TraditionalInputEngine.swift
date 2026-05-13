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
        let prefixCompletionCandidates = compactPrefixCompletionCandidates(
            for: trimmed,
            preserveCapitalizedPinyin: preserveCapitalizedPinyin
        )
        guard let tokens = tokenize(trimmed) else {
            return uniqueSorted(prefixCompletionCandidates)
        }

        let parsed = parse(
            tokens: tokens,
            from: 0,
            preserveCapitalizedPinyin: preserveCapitalizedPinyin
        )
            .filter { $0.translatedCount > 0 }
            .map { state in
                TraditionalInputCandidate(
                    text: joinSegments(state.segments),
                    confidence: state.confidence,
                    inputTokens: tokens.map(\.surface)
                )
            }

        return uniqueSorted(parsed + prefixCompletionCandidates)
    }

    public func canCompletePinyinPrefix(
        for rawInput: String,
        preserveCapitalizedPinyin: Bool = true
    ) -> Bool {
        !compactPrefixCompletionCandidates(
            for: rawInput,
            preserveCapitalizedPinyin: preserveCapitalizedPinyin
        ).isEmpty
    }

    private func tokenize(_ rawInput: String) -> [InputToken]? {
        let separated = rawInput
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        if separated.count > 1 {
            return separated.map { token in
                InputToken(surface: token, normalized: normalize(token), isTypoNormalized: isTypo(token))
            }
        }

        guard let token = separated.first else {
            return []
        }

        if isPassthroughToken(token) {
            return [InputToken(surface: token, normalized: token, isTypoNormalized: false)]
        }

        return segmentCompact(token)
    }

    private func segmentCompact(_ token: String) -> [InputToken]? {
        let lower = token.lowercased()
        let end = lower.endIndex
        var memo: [String.Index: [[String]]] = [:]

        func paths(from index: String.Index) -> [[String]] {
            if index == end {
                return [[]]
            }
            if let cached = memo[index] {
                return cached
            }

            let suffix = lower[index...]
            var results: [[String]] = []
            for key in compactSegmentKeys where suffix.hasPrefix(key) {
                let next = lower.index(index, offsetBy: key.count)
                for path in paths(from: next) {
                    results.append([key] + path)
                    if results.count >= 8 {
                        break
                    }
                }
                if results.count >= 8 {
                    break
                }
            }
            memo[index] = results
            return results
        }

        guard let firstPath = paths(from: lower.startIndex).first else {
            return nil
        }
        return firstPath.map { key in
            InputToken(surface: key, normalized: normalize(key), isTypoNormalized: isTypo(key))
        }
    }

    private func compactPrefixCompletionCandidates(
        for rawInput: String,
        preserveCapitalizedPinyin: Bool
    ) -> [TraditionalInputCandidate] {
        guard let compactPrefix = compactPinyinPrefixToken(
            rawInput,
            preserveCapitalizedPinyin: preserveCapitalizedPinyin
        ) else {
            return []
        }

        return lexicon.flatMap { entry -> [TraditionalInputCandidate] in
            let compactEntry = entry.pinyin.joined()
            guard compactEntry.hasPrefix(compactPrefix),
                  compactEntry != compactPrefix else {
                return []
            }

            let completionRatio = Double(compactPrefix.count) / Double(compactEntry.count)
            let prefixPenalty = 0.04 + (0.10 * (1.0 - completionRatio))
            return entry.outputs.map { output in
                TraditionalInputCandidate(
                    text: output.text,
                    confidence: max(0.01, output.confidence - prefixPenalty),
                    inputTokens: [rawInput]
                )
            }
        }
    }

    private func compactPinyinPrefixToken(
        _ rawInput: String,
        preserveCapitalizedPinyin: Bool
    ) -> String? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = trimmed.split(whereSeparator: { $0.isWhitespace })
        guard pieces.count == 1,
              let piece = pieces.first else {
            return nil
        }

        let token = String(piece)
        if isPassthroughToken(token) {
            return nil
        }
        if preserveCapitalizedPinyin, isCapitalizedASCIIWord(token) {
            return nil
        }

        let lower = token.lowercased()
        guard lower.count >= 3,
              lower.unicodeScalars.allSatisfy({ scalar in
                  scalar.value < 128 && CharacterSet.lowercaseLetters.contains(scalar)
              }) else {
            return nil
        }

        return normalize(lower)
    }

    private func parse(
        tokens: [InputToken],
        from index: Int,
        preserveCapitalizedPinyin: Bool
    ) -> [ParseState] {
        if index >= tokens.count {
            return [ParseState(segments: [], confidence: 1.0, translatedCount: 0)]
        }

        var states: [ParseState] = []

        for length in stride(from: min(maxEntryLength, tokens.count - index), through: 1, by: -1) {
            let tokenSlice = tokens[index..<(index + length)]
            if preserveCapitalizedPinyin {
                guard !tokenSlice.contains(where: { token in
                    isCapitalizedASCIIWord(token.surface) && knownPinyinTokens.contains(token.normalized)
                }) else {
                    continue
                }
            }

            let normalized = tokenSlice.map(\.normalized)
            guard let entry = lexicon.first(where: { $0.pinyin == normalized }) else {
                continue
            }

            let typoPenalty = tokenSlice.contains { $0.isTypoNormalized } ? 0.03 : 0
            for output in entry.outputs {
                for tail in parse(
                    tokens: tokens,
                    from: index + length,
                    preserveCapitalizedPinyin: preserveCapitalizedPinyin
                ) {
                    states.append(
                        ParseState(
                            segments: [output.text] + tail.segments,
                            confidence: max(0.01, output.confidence - typoPenalty) * tail.confidence,
                            translatedCount: tail.translatedCount + 1
                        )
                    )
                }
            }
        }

        let token = tokens[index]
        if let passthrough = passthroughText(
            for: token,
            preserveCapitalizedPinyin: preserveCapitalizedPinyin
        ) {
            for tail in parse(
                tokens: tokens,
                from: index + 1,
                preserveCapitalizedPinyin: preserveCapitalizedPinyin
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

        return states
            .sorted { $0.confidence > $1.confidence }
            .prefix(12)
            .map { $0 }
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
                if $0.confidence == $1.confidence {
                    return $0.text < $1.text
                }
                return $0.confidence > $1.confidence
            }
    }

    private static let fullPinyinCompactSegmentKeys: [String] = {
        let keys = Set(knownPinyinTokens).union(pinyinTypoCorrections.keys)
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

private let lexicon: [LexiconEntry] = [
    entry(["wo", "jue", "de"], [("我觉得", 0.99)]),
    entry(["wo", "jue"], [("我觉得", 0.94)]),
    entry(["wo", "xiang"], [("我想", 0.99)]),
    entry(["wsm"], [
        ("为什么", 0.98),
        ("我什么", 0.58)
    ]),
    entry(["sm"], [("什么", 0.96)]),
    entry(["zm"], [("怎么", 0.94)]),
    entry(["zmb"], [("怎么办", 0.94)]),
    entry(["zmy"], [("怎么样", 0.94)]),
    entry(["zms"], [("怎么说", 0.90)]),
    entry(["ws"], [("我是", 0.86)]),
    entry(["ns"], [("你是", 0.86)]),
    entry(["jue", "de"], [("觉得", 0.96)]),
    entry(["shen", "me"], [("什么", 0.97)]),
    entry(["zen", "me"], [("怎么", 0.96)]),
    entry(["wei", "shen", "me"], [("为什么", 0.99)]),
    entry(["xian", "zai"], [("现在", 0.99)]),
    entry(["xian", "zhi"], [
        ("限制", 0.94),
        ("先知", 0.56)
    ]),
    entry(["xian", "shi"], [
        ("显示", 0.95),
        ("现实", 0.82)
    ]),
    entry(["xian"], [
        ("先", 0.92),
        ("现", 0.84),
        ("线", 0.78)
    ]),
    entry(["zai"], [("在", 0.96)]),
    entry(["zhi"], [
        ("只", 0.88),
        ("知", 0.76)
    ]),
    entry(["shi"], [
        ("是", 0.94),
        ("时", 0.84),
        ("事", 0.80)
    ]),
    entry(["zhege"], [("这个", 0.99)]),
    entry(["zhe", "ge"], [("这个", 0.98)]),
    entry(["fangan"], [
        ("方案", 0.99),
        ("方法", 0.84),
        ("方向", 0.80),
        ("计划", 0.68),
        ("思路", 0.64)
    ]),
    entry(["fangfa"], [("方法", 0.98)]),
    entry(["fangxiang"], [("方向", 0.98)]),
    entry(["gongneng"], [
        ("功能", 0.99),
        ("工具", 0.74),
        ("模块", 0.70)
    ]),
    entry(["bushi"], [("不是", 0.99)]),
    entry(["hen"], [("很", 0.99)]),
    entry(["wending"], [("稳定", 0.99)]),
    entry(["jiekou"], [("接口", 0.99)]),
    entry(["yan", "chi"], [("延迟", 0.99)]),
    entry(["yanchi"], [("延迟", 0.99)]),
    entry(["youdian"], [("有点", 0.99)]),
    entry(["gao"], [("高", 0.99)]),
    entry(["ba"], [("把", 0.99)]),
    entry(["wenti"], [("问题", 0.99)]),
    entry(["xiugai"], [("修改", 0.99)]),
    entry(["yixia"], [("一下", 0.99)]),
    entry(["xiang"], [("想", 0.96)]),
    entry(["wo"], [("我", 0.95)]),
    entry(["ni", "hao"], [
        ("你好", 0.96),
        ("你号", 0.58)
    ]),
    entry(["nihao"], [
        ("你好", 0.95),
        ("你号", 0.57)
    ])
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

private let maxEntryLength = lexicon.map(\.pinyin.count).max() ?? 1

private let knownPinyinTokens: Set<String> = {
    var tokens = Set<String>()
    for entry in lexicon {
        for token in entry.pinyin {
            tokens.insert(token)
        }
    }
    return tokens
}()

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
