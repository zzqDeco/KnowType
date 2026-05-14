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

    public static func preloadResources() {
        _ = lexicon.count
        _ = lexiconOutputIndex.count
        _ = compactPrefixBuckets.count
        _ = knownPinyinTokens.count
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
        guard let tokenizations = tokenizations(trimmed), !tokenizations.isEmpty else {
            return uniqueSorted(prefixCompletionCandidates)
        }

        let parsed = tokenizations.flatMap { tokens in
            parse(
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
        }
        let partialPrefixes = tokenizations.flatMap { partialPrefixCandidates(from: $0) }

        return uniqueSorted(parsed + prefixCompletionCandidates + partialPrefixes)
    }

    public func canCompletePinyinPrefix(
        for rawInput: String,
        preserveCapitalizedPinyin: Bool = true
    ) -> Bool {
        !compactPrefixCompletionCandidates(
            for: rawInput,
            preserveCapitalizedPinyin: preserveCapitalizedPinyin
        ).isEmpty
            || tokenizations(rawInput)?.contains { tokens in
                tokens.contains { $0.completionPenalty > 0 }
            } == true
    }

    private func tokenizations(_ rawInput: String) -> [[InputToken]]? {
        let separated = rawInput
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        if separated.count > 1 {
            return [separated.map { token in
                InputToken(
                    surface: token,
                    normalized: normalize(token),
                    isTypoNormalized: isTypo(token),
                    completionPenalty: 0
                )
            }]
        }

        guard let token = separated.first else {
            return []
        }

        if isPassthroughToken(token) {
            return [
                [InputToken(
                    surface: token,
                    normalized: token,
                    isTypoNormalized: false,
                    completionPenalty: 0
                )]
            ]
        }

        return segmentCompact(token)
    }

    private func segmentCompact(_ token: String) -> [[InputToken]]? {
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
            var results: [[InputToken]] = []
            for key in compactSegmentKeys where suffix.hasPrefix(key) {
                let next = lower.index(index, offsetBy: key.count)
                for path in paths(from: next) {
                    results.append([
                        InputToken(
                            surface: key,
                            normalized: normalize(key),
                            isTypoNormalized: isTypo(key),
                            completionPenalty: 0
                        )
                    ] + path)
                    if results.count >= Self.maxCompactSegmentPaths {
                        break
                    }
                }
                if results.count >= Self.maxCompactSegmentPaths {
                    break
                }
            }
            if results.isEmpty {
                let suffixText = String(suffix)
                for key in completionKeys(for: suffixText) {
                    let completionRatio = Double(suffixText.count) / Double(key.count)
                    let completionPenalty = 0.10 + (0.18 * (1.0 - completionRatio))
                    results.append([
                        InputToken(
                            surface: suffixText,
                            normalized: normalize(key),
                            isTypoNormalized: false,
                            completionPenalty: completionPenalty
                        )
                    ])
                    if results.count >= Self.maxCompactSegmentPaths {
                        break
                    }
                }
            }
            memo[index] = results
            return results
        }

        let paths = paths(from: lower.startIndex)
        guard !paths.isEmpty else {
            return nil
        }
        return Array(paths.prefix(Self.maxCompactSegmentPaths))
    }

    private func completionKeys(for suffixText: String) -> [String] {
        guard !suffixText.isEmpty else {
            return []
        }

        var seen = Set<String>()
        var keys: [String] = []
        for key in preferredCompletionKeys[suffixText] ?? [] where key.hasPrefix(suffixText) && key != suffixText {
            keys.append(key)
            seen.insert(key)
        }
        for key in compactPrefixCompletionKeys where key.hasPrefix(suffixText) && key != suffixText && !seen.contains(key) {
            keys.append(key)
        }
        return keys
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

        let bucketKey = compactPrefixBucketKey(for: compactPrefix)
        let entries = compactPrefixBuckets[bucketKey] ?? []
        return entries.flatMap { compactEntry, entry -> [TraditionalInputCandidate] in
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

    private func partialPrefixCandidates(from tokens: [InputToken]) -> [TraditionalInputCandidate] {
        guard let completionIndex = tokens.firstIndex(where: { $0.completionPenalty > 0 }),
              completionIndex > 0 else {
            return []
        }

        let prefixTokens = Array(tokens.prefix(upTo: completionIndex))
        return parse(
            tokens: prefixTokens,
            from: 0,
            preserveCapitalizedPinyin: false
        )
        .filter { $0.translatedCount > 0 }
            .map { state in
                TraditionalInputCandidate(
                    text: joinSegments(state.segments),
                    confidence: state.confidence * 0.78,
                    inputTokens: prefixTokens.map(\.surface)
                )
            }
    }

    private func parse(
        tokens: [InputToken],
        from index: Int,
        preserveCapitalizedPinyin: Bool
    ) -> [ParseState] {
        var memo: [Int: [ParseState]] = [:]
        return parse(
            tokens: tokens,
            from: index,
            preserveCapitalizedPinyin: preserveCapitalizedPinyin,
            memo: &memo
        )
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
            let outputs = cappedOutputs(
                lexiconOutputs(for: normalized),
                tokenLength: length,
                totalTokenCount: tokens.count
            )
            guard !outputs.isEmpty else {
                continue
            }

            let typoPenalty = tokenSlice.contains { $0.isTypoNormalized } ? 0.03 : 0
            let completionPenalty = tokenSlice.map(\.completionPenalty).reduce(0, +)
            for output in outputs {
                let singleCharacterTokenPenalty = length == 1 && tokens.count > 1 && output.text.count == 1
                    ? 0.82
                    : 1.0
                for tail in parse(
                    tokens: tokens,
                    from: index + length,
                    preserveCapitalizedPinyin: preserveCapitalizedPinyin,
                    memo: &memo
                ) {
                    states.append(
                        ParseState(
                            segments: [output.text] + tail.segments,
                            confidence: max(0.01, output.confidence - typoPenalty - completionPenalty)
                                * singleCharacterTokenPenalty
                                * tail.confidence,
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

        let ranked = states
            .sorted { $0.confidence > $1.confidence }
            .prefix(16)
            .map { $0 }
        memo[index] = ranked
        return ranked
    }

    private func cappedOutputs(
        _ outputs: [LexiconOutput],
        tokenLength: Int,
        totalTokenCount: Int
    ) -> [LexiconOutput] {
        if totalTokenCount == 1 {
            return Array(outputs.prefix(32))
        }
        let limit = tokenLength == 1 ? 8 : 6
        return Array(outputs.prefix(limit))
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
        var bestByText: [String: TraditionalInputCandidate] = [:]
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

    private static let maxCompactSegmentPaths = 8
}

private struct InputToken: Sendable, Equatable {
    var surface: String
    var normalized: String
    var isTypoNormalized: Bool
    var completionPenalty: Double
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

private enum LexiconResourceLoader {
    static func loadEntries() -> [LexiconEntry] {
        guard let url = resourceURL(),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        return contents.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3,
                  let confidence = Double(fields[2]) else {
                return nil
            }
            let pinyin = fields[0].split(separator: " ").map(String.init)
            guard !pinyin.isEmpty else {
                return nil
            }
            return LexiconEntry(
                pinyin: pinyin,
                outputs: [LexiconOutput(text: String(fields[1]), confidence: confidence)]
            )
        }
    }

    private static func resourceURL() -> URL? {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "pinyin_lexicon", withExtension: "tsv") {
            return url
        }
        #endif
        if let url = Bundle.main.url(forResource: "pinyin_lexicon", withExtension: "tsv") {
            return url
        }

        let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceResourceURL = cwdURL
            .appendingPathComponent("Sources")
            .appendingPathComponent("KnowTypeCore")
            .appendingPathComponent("Resources")
            .appendingPathComponent("pinyin_lexicon.tsv")
        if FileManager.default.fileExists(atPath: sourceResourceURL.path) {
            return sourceResourceURL
        }
        return nil
    }
}

private let seedLexicon: [LexiconEntry] = [
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
    ]),
    entry(["ni", "shi"], [("你是", 0.93)]),
    entry(["ni", "xiang"], [("你想", 0.92)]),
    entry(["ni", "yao"], [("你要", 0.90)]),
    entry(["ni", "wo"], [("你我", 0.88)]),
    entry(["ni", "shi", "shei"], [("你是谁", 0.94)]),
    entry(["wo", "shi"], [("我是", 0.94)]),
    entry(["wo", "men"], [("我们", 0.96)]),
    entry(["wo", "xiang", "qu"], [("我想去", 0.93)]),
    entry(["xiang", "qu"], [("想去", 0.92)]),
    entry(["qu", "kan"], [("去看", 0.90)]),
    entry(["ni", "men"], [("你们", 0.94)]),
    entry(["ta", "men"], [("他们", 0.92), ("她们", 0.80)]),
    entry(["zhong", "guo"], [("中国", 0.96)]),
    entry(["zhong", "guo", "ren"], [("中国人", 0.95)]),
    entry(["zhong", "wen"], [("中文", 0.96)]),
    entry(["ying", "wen"], [("英文", 0.94)]),
    entry(["jin", "tian"], [("今天", 0.95)]),
    entry(["ming", "tian"], [("明天", 0.94)]),
    entry(["zuo", "tian"], [("昨天", 0.92)]),
    entry(["mei", "you"], [("没有", 0.96)]),
    entry(["ke", "yi"], [("可以", 0.96)]),
    entry(["bu", "neng"], [("不能", 0.94)]),
    entry(["bu", "shi"], [("不是", 0.94)]),
    entry(["xie", "xie"], [("谢谢", 0.96)]),
    entry(["zai", "jian"], [("再见", 0.94)]),
    entry(["mei", "wen", "ti"], [("没问题", 0.94)]),
    entry(["kan", "yi", "xia"], [("看一下", 0.92)]),
    entry(["deng", "yi", "xia"], [("等一下", 0.92)]),
    entry(["shuo", "yi", "xia"], [("说一下", 0.90)]),
    entry(["you", "dian"], [("有点", 0.94)]),
    entry(["yi", "ge"], [("一个", 0.94)]),
    entry(["zhe", "li"], [("这里", 0.92)]),
    entry(["na", "li"], [("哪里", 0.90), ("那里", 0.82)]),
    entry(["zhe", "yang"], [("这样", 0.94)]),
    entry(["na", "yang"], [("那样", 0.90)]),
    entry(["ru", "guo"], [("如果", 0.94)]),
    entry(["yin", "wei"], [("因为", 0.94)]),
    entry(["suo", "yi"], [("所以", 0.94)]),
    entry(["dan", "shi"], [("但是", 0.94)]),
    entry(["ran", "hou"], [("然后", 0.94)]),
    entry(["ying", "gai"], [("应该", 0.94)]),
    entry(["xu", "yao"], [("需要", 0.94)]),
    entry(["wen", "ti"], [("问题", 0.94)]),
    entry(["fang", "an"], [("方案", 0.94), ("方安", 0.52)]),
    entry(["jie", "kou"], [("接口", 0.94)]),
    entry(["shu", "ju"], [("数据", 0.94)]),
    entry(["xi", "tong"], [("系统", 0.94)]),
    entry(["xiang", "mu"], [("项目", 0.92)]),
    entry(["gong", "neng"], [("功能", 0.94)]),
    entry(["ce", "shi"], [("测试", 0.94)]),
    entry(["kai", "fa"], [("开发", 0.94)]),
    entry(["wen", "dang"], [("文档", 0.92)]),
    entry(["shi", "jian"], [("时间", 0.92), ("实践", 0.76)]),
    entry(["jie", "guo"], [("结果", 0.92)]),
    entry(["qian", "mian"], [("前面", 0.88)]),
    entry(["hou", "mian"], [("后面", 0.88)])
]

private let lexicon: [LexiconEntry] = seedLexicon + LexiconResourceLoader.loadEntries()

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

private let syllableFallbackOutputs: [String: [LexiconOutput]] = [
    "a": makeOutputs([("啊", 0.78)]),
    "ai": makeOutputs([("爱", 0.82), ("矮", 0.64)]),
    "an": makeOutputs([("安", 0.78), ("按", 0.72)]),
    "ba": makeOutputs([("把", 0.86), ("吧", 0.78), ("八", 0.70)]),
    "bai": makeOutputs([("白", 0.80), ("百", 0.72)]),
    "ban": makeOutputs([("办", 0.82), ("半", 0.74), ("版", 0.70)]),
    "bang": makeOutputs([("帮", 0.80), ("棒", 0.68)]),
    "bao": makeOutputs([("包", 0.78), ("保", 0.72), ("报", 0.70)]),
    "bei": makeOutputs([("被", 0.82), ("北", 0.72), ("备", 0.70)]),
    "ben": makeOutputs([("本", 0.82), ("笨", 0.62)]),
    "bi": makeOutputs([("比", 0.78), ("必", 0.72), ("笔", 0.68)]),
    "bian": makeOutputs([("变", 0.80), ("边", 0.74), ("便", 0.68)]),
    "biao": makeOutputs([("表", 0.78), ("标", 0.72)]),
    "bie": makeOutputs([("别", 0.82)]),
    "bing": makeOutputs([("并", 0.80), ("病", 0.70)]),
    "bo": makeOutputs([("不", 0.60), ("波", 0.58)]),
    "bu": makeOutputs([("不", 0.90), ("部", 0.70), ("步", 0.66)]),
    "cai": makeOutputs([("才", 0.82), ("菜", 0.70)]),
    "can": makeOutputs([("参", 0.72), ("残", 0.62)]),
    "cao": makeOutputs([("草", 0.70)]),
    "ce": makeOutputs([("测", 0.78), ("策", 0.70)]),
    "ceng": makeOutputs([("层", 0.78), ("曾", 0.70)]),
    "cha": makeOutputs([("查", 0.78), ("差", 0.70)]),
    "chan": makeOutputs([("产", 0.78), ("单", 0.56)]),
    "chang": makeOutputs([("常", 0.82), ("长", 0.76), ("场", 0.70)]),
    "chao": makeOutputs([("超", 0.78), ("朝", 0.64)]),
    "che": makeOutputs([("车", 0.80)]),
    "chen": makeOutputs([("陈", 0.70), ("沉", 0.64)]),
    "cheng": makeOutputs([("成", 0.84), ("程", 0.78), ("城", 0.68)]),
    "chi": makeOutputs([("吃", 0.80), ("持", 0.70)]),
    "chong": makeOutputs([("重", 0.78), ("冲", 0.68)]),
    "chu": makeOutputs([("出", 0.82), ("处", 0.72)]),
    "chuan": makeOutputs([("传", 0.76), ("穿", 0.66)]),
    "chuang": makeOutputs([("创", 0.76), ("窗", 0.64)]),
    "ci": makeOutputs([("次", 0.80), ("此", 0.74)]),
    "cong": makeOutputs([("从", 0.82)]),
    "cuo": makeOutputs([("错", 0.82)]),
    "da": makeOutputs([("大", 0.84), ("打", 0.78), ("达", 0.64)]),
    "dai": makeOutputs([("带", 0.80), ("代", 0.74), ("待", 0.68)]),
    "dan": makeOutputs([("但", 0.82), ("单", 0.76)]),
    "dang": makeOutputs([("当", 0.82), ("党", 0.66)]),
    "dao": makeOutputs([("到", 0.84), ("道", 0.78), ("导", 0.66)]),
    "de": makeOutputs([("的", 0.90), ("得", 0.82), ("地", 0.76)]),
    "deng": makeOutputs([("等", 0.82)]),
    "di": makeOutputs([("第", 0.80), ("地", 0.74), ("低", 0.66)]),
    "dian": makeOutputs([("点", 0.84), ("电", 0.76)]),
    "ding": makeOutputs([("定", 0.82), ("顶", 0.66)]),
    "dong": makeOutputs([("动", 0.80), ("东", 0.72)]),
    "dou": makeOutputs([("都", 0.82)]),
    "du": makeOutputs([("度", 0.78), ("读", 0.70)]),
    "dui": makeOutputs([("对", 0.84)]),
    "duo": makeOutputs([("多", 0.82)]),
    "er": makeOutputs([("而", 0.78), ("二", 0.72)]),
    "fa": makeOutputs([("发", 0.78), ("法", 0.72)]),
    "fan": makeOutputs([("反", 0.78), ("饭", 0.66)]),
    "fang": makeOutputs([("方", 0.82), ("放", 0.72)]),
    "fei": makeOutputs([("非", 0.76), ("费", 0.70)]),
    "fen": makeOutputs([("分", 0.82), ("份", 0.70)]),
    "feng": makeOutputs([("风", 0.76), ("封", 0.66)]),
    "gai": makeOutputs([("该", 0.82), ("改", 0.74)]),
    "gan": makeOutputs([("感", 0.78), ("干", 0.72)]),
    "gang": makeOutputs([("刚", 0.78)]),
    "gao": makeOutputs([("高", 0.86), ("搞", 0.68)]),
    "ge": makeOutputs([("个", 0.88), ("各", 0.70)]),
    "gei": makeOutputs([("给", 0.84)]),
    "gen": makeOutputs([("跟", 0.82), ("根", 0.66)]),
    "geng": makeOutputs([("更", 0.82)]),
    "gong": makeOutputs([("工", 0.78), ("公", 0.72)]),
    "gou": makeOutputs([("够", 0.78), ("沟", 0.58)]),
    "gu": makeOutputs([("股", 0.70), ("故", 0.66)]),
    "guan": makeOutputs([("关", 0.82), ("管", 0.76)]),
    "guo": makeOutputs([("国", 0.82), ("过", 0.78)]),
    "hai": makeOutputs([("还", 0.84), ("海", 0.70)]),
    "han": makeOutputs([("含", 0.72), ("汉", 0.70)]),
    "hao": makeOutputs([("好", 0.90), ("号", 0.72), ("浩", 0.60)]),
    "he": makeOutputs([("和", 0.84), ("核", 0.66)]),
    "hen": makeOutputs([("很", 0.88)]),
    "hou": makeOutputs([("后", 0.82), ("候", 0.68)]),
    "hua": makeOutputs([("话", 0.80), ("化", 0.72)]),
    "huan": makeOutputs([("换", 0.78), ("还", 0.68)]),
    "hui": makeOutputs([("会", 0.84), ("回", 0.76)]),
    "ji": makeOutputs([("机", 0.78), ("几", 0.74), ("级", 0.68)]),
    "jia": makeOutputs([("加", 0.78), ("家", 0.74)]),
    "jian": makeOutputs([("见", 0.78), ("间", 0.72), ("件", 0.70)]),
    "jiang": makeOutputs([("将", 0.76), ("讲", 0.70)]),
    "jiao": makeOutputs([("交", 0.76), ("叫", 0.72)]),
    "jie": makeOutputs([("接", 0.78), ("结", 0.72), ("解", 0.70)]),
    "jin": makeOutputs([("进", 0.80), ("今", 0.74)]),
    "jing": makeOutputs([("经", 0.78), ("精", 0.66)]),
    "jiu": makeOutputs([("就", 0.84), ("九", 0.64)]),
    "ju": makeOutputs([("据", 0.76), ("句", 0.70)]),
    "jue": makeOutputs([("觉", 0.76), ("决", 0.72)]),
    "kan": makeOutputs([("看", 0.86)]),
    "kai": makeOutputs([("开", 0.82)]),
    "ke": makeOutputs([("可", 0.84), ("科", 0.70)]),
    "kou": makeOutputs([("口", 0.82)]),
    "kuai": makeOutputs([("快", 0.80), ("块", 0.70)]),
    "lai": makeOutputs([("来", 0.84)]),
    "lan": makeOutputs([("蓝", 0.66), ("栏", 0.62)]),
    "lao": makeOutputs([("老", 0.80)]),
    "le": makeOutputs([("了", 0.88), ("乐", 0.66)]),
    "li": makeOutputs([("里", 0.80), ("理", 0.74)]),
    "lian": makeOutputs([("连", 0.76), ("联", 0.70)]),
    "liang": makeOutputs([("量", 0.76), ("两", 0.72)]),
    "liao": makeOutputs([("了", 0.74), ("聊", 0.68)]),
    "lie": makeOutputs([("列", 0.74)]),
    "lin": makeOutputs([("林", 0.68), ("临", 0.62)]),
    "ling": makeOutputs([("零", 0.72), ("令", 0.66)]),
    "liu": makeOutputs([("流", 0.72), ("六", 0.66)]),
    "long": makeOutputs([("龙", 0.66)]),
    "lu": makeOutputs([("路", 0.74), ("录", 0.66)]),
    "ma": makeOutputs([("吗", 0.84), ("嘛", 0.70)]),
    "mai": makeOutputs([("买", 0.76), ("卖", 0.72)]),
    "man": makeOutputs([("慢", 0.76), ("满", 0.70)]),
    "mang": makeOutputs([("忙", 0.76)]),
    "mao": makeOutputs([("毛", 0.64)]),
    "mei": makeOutputs([("没", 0.84), ("每", 0.78), ("美", 0.70)]),
    "men": makeOutputs([("们", 0.84), ("门", 0.70)]),
    "meng": makeOutputs([("梦", 0.62)]),
    "mian": makeOutputs([("面", 0.80), ("免", 0.66)]),
    "ming": makeOutputs([("明", 0.80), ("名", 0.74)]),
    "mu": makeOutputs([("目", 0.72), ("母", 0.62)]),
    "na": makeOutputs([("那", 0.82), ("哪", 0.78), ("拿", 0.70)]),
    "nai": makeOutputs([("乃", 0.58), ("奶", 0.56)]),
    "nan": makeOutputs([("难", 0.76), ("南", 0.70)]),
    "nei": makeOutputs([("内", 0.78), ("那", 0.60)]),
    "neng": makeOutputs([("能", 0.84)]),
    "ni": makeOutputs([
        ("你", 0.90),
        ("呢", 0.82),
        ("尼", 0.78),
        ("拟", 0.76),
        ("泥", 0.74),
        ("逆", 0.72),
        ("妮", 0.70),
        ("腻", 0.68),
        ("倪", 0.66),
        ("匿", 0.64),
        ("霓", 0.62),
        ("溺", 0.60),
        ("昵", 0.58),
        ("铌", 0.56),
        ("鲵", 0.54)
    ]),
    "nian": makeOutputs([("年", 0.82), ("念", 0.70)]),
    "nin": makeOutputs([("您", 0.82)]),
    "ning": makeOutputs([("宁", 0.70)]),
    "pai": makeOutputs([("排", 0.76), ("拍", 0.70)]),
    "pan": makeOutputs([("盘", 0.70), ("判", 0.66)]),
    "pao": makeOutputs([("跑", 0.74)]),
    "pei": makeOutputs([("配", 0.72), ("陪", 0.68)]),
    "peng": makeOutputs([("朋", 0.70)]),
    "pi": makeOutputs([("批", 0.72), ("皮", 0.66)]),
    "pian": makeOutputs([("片", 0.76), ("篇", 0.70)]),
    "ping": makeOutputs([("平", 0.78), ("屏", 0.70)]),
    "qi": makeOutputs([("起", 0.78), ("其", 0.72), ("期", 0.70)]),
    "qian": makeOutputs([("前", 0.82), ("钱", 0.68)]),
    "qiang": makeOutputs([("强", 0.74)]),
    "qiao": makeOutputs([("桥", 0.66), ("巧", 0.62)]),
    "qie": makeOutputs([("且", 0.76), ("切", 0.70)]),
    "qin": makeOutputs([("亲", 0.72), ("请", 0.62)]),
    "qing": makeOutputs([("请", 0.82), ("清", 0.70)]),
    "qiu": makeOutputs([("求", 0.72)]),
    "qu": makeOutputs([("去", 0.84), ("区", 0.72)]),
    "quan": makeOutputs([("全", 0.78), ("权", 0.70)]),
    "ran": makeOutputs([("然", 0.82)]),
    "rang": makeOutputs([("让", 0.82)]),
    "ren": makeOutputs([("人", 0.84), ("任", 0.70)]),
    "ri": makeOutputs([("日", 0.78)]),
    "rong": makeOutputs([("容", 0.72)]),
    "ru": makeOutputs([("入", 0.74), ("如", 0.72)]),
    "sa": makeOutputs([("撒", 0.58)]),
    "san": makeOutputs([("三", 0.78)]),
    "se": makeOutputs([("色", 0.74)]),
    "shan": makeOutputs([("山", 0.70), ("删", 0.62)]),
    "shang": makeOutputs([("上", 0.84), ("商", 0.66)]),
    "shao": makeOutputs([("少", 0.78)]),
    "she": makeOutputs([("设", 0.78), ("社", 0.70)]),
    "shei": makeOutputs([("谁", 0.84)]),
    "shen": makeOutputs([("什", 0.78), ("深", 0.66)]),
    "sheng": makeOutputs([("生", 0.80), ("声", 0.70)]),
    "shi": makeOutputs([("是", 0.90), ("时", 0.80), ("事", 0.76), ("十", 0.72), ("使", 0.70), ("试", 0.68)]),
    "shou": makeOutputs([("手", 0.76), ("收", 0.70)]),
    "shu": makeOutputs([("数", 0.74), ("书", 0.72), ("输", 0.66)]),
    "shui": makeOutputs([("水", 0.76), ("谁", 0.70)]),
    "shuo": makeOutputs([("说", 0.84)]),
    "si": makeOutputs([("思", 0.74), ("四", 0.68)]),
    "song": makeOutputs([("送", 0.74)]),
    "suan": makeOutputs([("算", 0.80)]),
    "sui": makeOutputs([("随", 0.74), ("岁", 0.66)]),
    "suo": makeOutputs([("所", 0.80), ("缩", 0.64)]),
    "ta": makeOutputs([("他", 0.84), ("她", 0.80), ("它", 0.72)]),
    "tai": makeOutputs([("太", 0.78), ("台", 0.70)]),
    "tan": makeOutputs([("谈", 0.72), ("探", 0.66)]),
    "tang": makeOutputs([("堂", 0.66), ("躺", 0.58)]),
    "tao": makeOutputs([("套", 0.72), ("讨", 0.66)]),
    "ti": makeOutputs([("提", 0.78), ("题", 0.74)]),
    "tian": makeOutputs([("天", 0.82), ("填", 0.66)]),
    "tiao": makeOutputs([("条", 0.76), ("调", 0.70)]),
    "tie": makeOutputs([("贴", 0.70)]),
    "ting": makeOutputs([("听", 0.78), ("停", 0.70)]),
    "tong": makeOutputs([("同", 0.80), ("通", 0.74)]),
    "tou": makeOutputs([("头", 0.76)]),
    "tu": makeOutputs([("图", 0.76), ("土", 0.62)]),
    "wai": makeOutputs([("外", 0.78)]),
    "wan": makeOutputs([("完", 0.78), ("晚", 0.72)]),
    "wang": makeOutputs([("网", 0.78), ("往", 0.72)]),
    "wei": makeOutputs([("为", 0.80), ("未", 0.74), ("位", 0.70), ("微", 0.66)]),
    "wen": makeOutputs([("问", 0.78), ("文", 0.74)]),
    "wo": makeOutputs([("我", 0.90)]),
    "xi": makeOutputs([("系", 0.76), ("西", 0.70)]),
    "xia": makeOutputs([("下", 0.84), ("夏", 0.62)]),
    "xian": makeOutputs([("先", 0.88), ("现", 0.80), ("线", 0.74)]),
    "xiang": makeOutputs([("想", 0.88), ("像", 0.70), ("项", 0.68)]),
    "xiao": makeOutputs([("小", 0.82), ("笑", 0.66)]),
    "xie": makeOutputs([("写", 0.78), ("谢", 0.72)]),
    "xin": makeOutputs([("新", 0.80), ("信", 0.72)]),
    "xing": makeOutputs([("行", 0.78), ("性", 0.72)]),
    "xiu": makeOutputs([("修", 0.74)]),
    "xu": makeOutputs([("需", 0.78), ("许", 0.70)]),
    "xue": makeOutputs([("学", 0.80), ("雪", 0.62)]),
    "yao": makeOutputs([("要", 0.86), ("摇", 0.58)]),
    "ye": makeOutputs([("也", 0.82), ("业", 0.70)]),
    "yi": makeOutputs([("一", 0.84), ("以", 0.80), ("已", 0.74)]),
    "ying": makeOutputs([("应", 0.80), ("英", 0.70)]),
    "yong": makeOutputs([("用", 0.82), ("永", 0.60)]),
    "you": makeOutputs([("有", 0.88), ("又", 0.72), ("由", 0.66)]),
    "yuan": makeOutputs([("原", 0.76), ("远", 0.70)]),
    "yue": makeOutputs([("月", 0.78), ("越", 0.70)]),
    "yun": makeOutputs([("云", 0.70), ("运", 0.66)]),
    "zai": makeOutputs([("在", 0.88), ("再", 0.76)]),
    "zan": makeOutputs([("咱", 0.70), ("赞", 0.66)]),
    "zao": makeOutputs([("早", 0.78), ("造", 0.66)]),
    "ze": makeOutputs([("则", 0.76), ("责", 0.66)]),
    "zen": makeOutputs([("怎", 0.80)]),
    "zeng": makeOutputs([("增", 0.72), ("曾", 0.66)]),
    "zha": makeOutputs([("查", 0.60), ("扎", 0.58)]),
    "zhan": makeOutputs([("站", 0.74), ("展", 0.70)]),
    "zhang": makeOutputs([("张", 0.74), ("章", 0.66)]),
    "zhao": makeOutputs([("找", 0.78), ("照", 0.70)]),
    "zhe": makeOutputs([("这", 0.88), ("着", 0.70), ("者", 0.66)]),
    "zhen": makeOutputs([("真", 0.78), ("阵", 0.66)]),
    "zheng": makeOutputs([("正", 0.82), ("整", 0.74)]),
    "zhi": makeOutputs([("只", 0.82), ("知", 0.72), ("之", 0.70)]),
    "zhong": makeOutputs([("中", 0.82), ("种", 0.70)]),
    "zhou": makeOutputs([("周", 0.72), ("州", 0.66)]),
    "zhu": makeOutputs([("主", 0.78), ("住", 0.70)]),
    "zhuan": makeOutputs([("转", 0.76), ("专", 0.70)]),
    "zhuang": makeOutputs([("装", 0.72), ("状", 0.66)]),
    "zi": makeOutputs([("自", 0.80), ("字", 0.74)]),
    "zong": makeOutputs([("总", 0.78)]),
    "zou": makeOutputs([("走", 0.78)]),
    "zu": makeOutputs([("组", 0.74), ("足", 0.64)]),
    "zuo": makeOutputs([("做", 0.82), ("作", 0.76), ("左", 0.62)])
]

private let maxEntryLength = lexicon.map(\.pinyin.count).max() ?? 1

private let knownPinyinTokens: Set<String> = {
    var tokens = Set<String>()
    for entry in lexicon {
        for token in entry.pinyin {
            tokens.insert(token)
        }
    }
    for token in syllableFallbackOutputs.keys {
        tokens.insert(token)
    }
    return tokens
}()

private let compactPrefixCompletionKeys: [String] = {
    knownPinyinTokens.sorted { lhs, rhs in
        if lhs.count == rhs.count {
            return lhs < rhs
        }
        return lhs.count < rhs.count
    }
}()

private let lexiconOutputIndex: [[String]: [LexiconOutput]] = {
    var index: [[String]: [LexiconOutput]] = [:]
    for entry in lexicon {
        index[entry.pinyin, default: []].append(contentsOf: entry.outputs)
    }
    return index.mapValues { outputs in
        rankedUniqueOutputs(outputs, limit: 24)
    }
}()

private let compactPrefixBuckets: [String: [(String, LexiconEntry)]] = {
    var buckets: [String: [(String, LexiconEntry)]] = [:]
    for entry in lexicon {
        let compact = entry.pinyin.joined()
        guard compact.count >= 3 else {
            continue
        }
        buckets[compactPrefixBucketKey(for: compact), default: []].append((compact, entry))
    }
    return buckets
}()

private func compactPrefixBucketKey(for compact: String) -> String {
    String(compact.prefix(3))
}

private let preferredCompletionKeys: [String: [String]] = [
    "b": ["bu", "ba", "bei", "bi", "bao"],
    "c": ["cong", "cai", "cuo", "cheng"],
    "ch": ["chu", "chi", "chang", "cheng", "chong"],
    "d": ["de", "dao", "dui", "da", "di"],
    "f": ["fa", "fang", "fei", "fen"],
    "g": ["ge", "gao", "guo", "gei", "gong"],
    "h": ["hao", "hen", "hui", "he", "hai"],
    "j": ["jiu", "ji", "jia", "jian", "jin"],
    "k": ["kan", "ke", "kai", "kuai"],
    "l": ["le", "lai", "li", "liang"],
    "m": ["ma", "mei", "men", "ming"],
    "n": ["ni", "na", "neng", "nei"],
    "p": ["ping", "pai", "pao"],
    "q": ["qu", "qing", "qian", "qi"],
    "r": ["ren", "rang", "ru"],
    "s": ["shi", "shuo", "suo", "si"],
    "sh": ["shi", "shuo", "shu", "shang"],
    "t": ["ta", "tian", "tong", "ti"],
    "w": ["wo", "wei", "wen", "wang"],
    "x": ["xiang", "xian", "xue", "xi", "xin"],
    "y": ["you", "yao", "yi", "ying"],
    "z": ["zai", "zhe", "zhi", "zuo", "zhong"],
    "zh": ["zhe", "zhi", "zhong", "zhao"]
]

private func entry(_ pinyin: [String], _ outputs: [(String, Double)]) -> LexiconEntry {
    LexiconEntry(
        pinyin: pinyin,
        outputs: makeOutputs(outputs)
    )
}

private func makeOutputs(_ outputs: [(String, Double)]) -> [LexiconOutput] {
    outputs.map { text, confidence in
        LexiconOutput(text: text, confidence: confidence)
    }
}

private func lexiconOutputs(for pinyin: [String]) -> [LexiconOutput] {
    var collected = lexiconOutputIndex[pinyin] ?? []
    if pinyin.count == 1,
       let fallbackOutputs = syllableFallbackOutputs[pinyin[0]] {
        collected.append(contentsOf: fallbackOutputs)
    }
    return rankedUniqueOutputs(collected, limit: pinyin.count == 1 ? 32 : 18)
}

private func uniqueOutputs(_ outputs: [LexiconOutput]) -> [LexiconOutput] {
    var seen = Set<String>()
    return outputs.filter { output in
        if seen.contains(output.text) {
            return false
        }
        seen.insert(output.text)
        return true
    }
}

private func rankedUniqueOutputs(_ outputs: [LexiconOutput], limit: Int) -> [LexiconOutput] {
    var bestByText: [String: LexiconOutput] = [:]
    for output in outputs {
        guard let existing = bestByText[output.text] else {
            bestByText[output.text] = output
            continue
        }
        if output.confidence > existing.confidence {
            bestByText[output.text] = output
        }
    }
    return Array(bestByText.values)
        .sorted {
            if $0.confidence == $1.confidence {
                if $0.text.count == $1.text.count {
                    return $0.text < $1.text
                }
                return $0.text.count < $1.text.count
            }
            return $0.confidence > $1.confidence
        }
        .prefix(limit)
        .map { $0 }
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
