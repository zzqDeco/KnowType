import Foundation

public final class CorrectionEngine: Sendable {
    private let cloudProvider: (any LLMProvider)?

    public init(cloudProvider: (any LLMProvider)? = nil) {
        self.cloudProvider = cloudProvider
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

        return uniqueSorted(localCandidates(for: raw, protectedRanges: protectedRanges))
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
                maxCandidates: 3
            )
            if let cloud = try? await cloudProvider.complete(request) {
                let cloudCandidates = cloud.candidates.map {
                    CorrectionCandidate(
                        text: $0.text,
                        source: cloudProvider.providerName,
                        confidence: $0.confidence ?? 0.62,
                        correctionLevel: .strongAlternative,
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
        let tokenCount = tokenize(context.rawInput).count
        return tokenCount >= 4 || context.locale == .mixed
    }

    private func localCandidates(for raw: String, protectedRanges: [ProtectedRange]) -> [CorrectionCandidate] {
        let tokens = tokenize(raw)
        guard !tokens.isEmpty else {
            return []
        }

        var candidates: [CorrectionCandidate] = []

        let normalizedTokens = tokens.map(normalizeToken)
        if let decoded = decodeMixedTokens(normalizedTokens), decoded != raw {
            candidates.append(
                CorrectionCandidate(
                    text: decoded,
                    source: "local-decoder",
                    confidence: 0.92,
                    correctionLevel: .contextual,
                    protectedRanges: TextProtection.detectProtectedRanges(in: decoded)
                )
            )

            if decoded.hasSuffix("方案") {
                candidates.append(
                    CorrectionCandidate(
                        text: String(decoded.dropLast(2)) + "方法",
                        source: "local-decoder",
                        confidence: 0.72,
                        correctionLevel: .contextual
                    )
                )
                candidates.append(
                    CorrectionCandidate(
                        text: String(decoded.dropLast(2)) + "方向",
                        source: "local-decoder",
                        confidence: 0.69,
                        correctionLevel: .contextual
                    )
                )
            }
        }

        let english = normalizedTokens.joined(separator: " ")
        if english != raw, isLikelyEnglish(raw), !looksLikePinyinInput(tokens) {
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
}

private let spellingCorrections: [String: String] = [
    "thikn": "think",
    "approch": "approach",
    "latnecy": "latency",
    "fagnan": "fangan",
    "faangan": "fangan",
    "fangam": "fangan",
    "fangn": "fangan"
]

private let phraseMap: [String: String] = [
    "wo": "我",
    "wo jue": "我觉得",
    "wo jue de": "我觉得",
    "wo xiang": "我想",
    "zhege": "这个",
    "zhe ge": "这个",
    "fangan": "方案",
    "fangfa": "方法",
    "fangxiang": "方向",
    "gongneng": "功能",
    "bushi": "不是",
    "hen": "很",
    "wending": "稳定",
    "jiekou": "接口",
    "yan chi": "延迟",
    "yanchi": "延迟",
    "youdian": "有点",
    "gao": "高",
    "ba": "把",
    "wenti": "问题",
    "xiugai": "修改",
    "yixia": "一下"
]

private func tokenize(_ raw: String) -> [String] {
    let separated = raw
        .split(whereSeparator: { $0.isWhitespace })
        .map(String.init)
    if separated.count > 1 {
        return separated
    }
    return separated.flatMap(segmentCompactPinyin)
}

private func segmentCompactPinyin(_ token: String) -> [String] {
    let lower = token.lowercased()
    let known = compactPinyinSegments
        .sorted { $0.count > $1.count }
    var output: [String] = []
    var cursor = lower.startIndex

    while cursor < lower.endIndex {
        let suffix = lower[cursor...]
        if let match = known.first(where: { suffix.hasPrefix($0) }) {
            output.append(match)
            cursor = lower.index(cursor, offsetBy: match.count)
        } else {
            return [token]
        }
    }
    return output.isEmpty ? [token] : output
}

private let compactPinyinSegments: [String] = {
    var segments = Set<String>()

    for key in phraseMap.keys {
        if !key.contains(" ") {
            segments.insert(key)
        }
        for part in key.split(separator: " ") {
            segments.insert(String(part))
        }
    }

    for (misspelled, corrected) in spellingCorrections {
        segments.insert(misspelled)
        segments.insert(corrected)
    }

    return Array(segments)
}()

private func normalizeToken(_ token: String) -> String {
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
    return spellingCorrections[lower] ?? lower
}

private func preservesCodeLikeToken(_ token: String) -> Bool {
    token.range(of: #"^[a-z]+_[A-Za-z0-9_]+$"#, options: .regularExpression) != nil
        || token.range(of: #"^[a-z]+[A-Z][A-Za-z0-9]*$"#, options: .regularExpression) != nil
}

private func looksLikePinyinInput(_ tokens: [String]) -> Bool {
    tokens.contains { token in
        phraseMap.keys.contains(token.lowercased()) || spellingCorrections[token.lowercased()] == "fangan"
    }
}

private func isLikelyEnglish(_ raw: String) -> Bool {
    raw.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
}

private func decodeMixedTokens(_ tokens: [String]) -> String? {
    var segments: [String] = []
    var index = 0

    while index < tokens.count {
        var matched = false
        for length in stride(from: min(3, tokens.count - index), through: 1, by: -1) {
            let key = tokens[index..<(index + length)].joined(separator: " ").lowercased()
            if let phrase = phraseMap[key] {
                segments.append(phrase)
                index += length
                matched = true
                break
            }
        }
        if matched {
            continue
        }

        let token = tokens[index]
        if TextProtection.canonicalTechnicalToken(token) != nil || token == "latency" {
            segments.append(token)
            index += 1
            continue
        }

        if isASCIIWord(token), !looksLikePinyinInput([token]) {
            segments.append(token)
            index += 1
            continue
        }

        return nil
    }

    return joinSegments(segments)
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
