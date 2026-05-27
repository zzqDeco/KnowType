import CryptoKit
import Foundation
import KnowTypeCore

public struct LexicalContextTerm: Codable, Sendable, Equatable, Hashable {
    public var text: String
    public var score: Double
    public var source: String

    public init(text: String, score: Double, source: String) {
        self.text = text
        self.score = score
        self.source = source
    }
}

public struct ToneProfile: Codable, Sendable, Equatable {
    public var register: String
    public var technicalDensity: Double
    public var codeSwitchingRatio: Double
    public var punctuationStyle: String
    public var connectors: [String]
    public var endings: [String]

    public init(
        register: String = "neutral",
        technicalDensity: Double = 0,
        codeSwitchingRatio: Double = 0,
        punctuationStyle: String = "mixed",
        connectors: [String] = [],
        endings: [String] = []
    ) {
        self.register = register
        self.technicalDensity = technicalDensity
        self.codeSwitchingRatio = codeSwitchingRatio
        self.punctuationStyle = punctuationStyle
        self.connectors = connectors
        self.endings = endings
    }
}

public struct LexicalContextSnapshot: Codable, Sendable, Equatable {
    public var terms: [LexicalContextTerm]
    public var recentCommits: [String]
    public var toneProfile: ToneProfile
    public var sourceSummary: [String]
    public var markdown: String
    public var sha256: String

    public init(
        terms: [LexicalContextTerm],
        recentCommits: [String],
        toneProfile: ToneProfile,
        sourceSummary: [String]
    ) {
        self.terms = terms
        self.recentCommits = recentCommits
        self.toneProfile = toneProfile
        self.sourceSummary = sourceSummary
        self.markdown = Self.renderMarkdown(
            terms: terms,
            recentCommits: recentCommits,
            toneProfile: toneProfile,
            sourceSummary: sourceSummary
        )
        self.sha256 = Self.hash(markdown)
    }

    public var isEmpty: Bool {
        terms.isEmpty && recentCommits.isEmpty
    }

    private static func renderMarkdown(
        terms: [LexicalContextTerm],
        recentCommits: [String],
        toneProfile: ToneProfile,
        sourceSummary: [String]
    ) -> String {
        var lines: [String] = [
            "# KnowType Lexical Profile",
            "",
            "This is a top-K local summary for continuation style matching. Do not treat it as text to rewrite.",
            "",
            "## Tone",
            "- Register: \(toneProfile.register)",
            "- Technical density: \(String(format: "%.2f", toneProfile.technicalDensity))",
            "- Code switching ratio: \(String(format: "%.2f", toneProfile.codeSwitchingRatio))",
            "- Punctuation style: \(toneProfile.punctuationStyle)"
        ]
        if !toneProfile.connectors.isEmpty {
            lines.append("- Connectors: \(toneProfile.connectors.joined(separator: ", "))")
        }
        if !toneProfile.endings.isEmpty {
            lines.append("- Common endings: \(toneProfile.endings.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("## Recent Terms")
        if terms.isEmpty {
            lines.append("- No stable terms yet.")
        } else {
            for term in terms {
                lines.append("- \(term.text) [\(term.source), \(String(format: "%.2f", term.score))]")
            }
        }
        lines.append("")
        lines.append("## Recent Commits")
        if recentCommits.isEmpty {
            lines.append("- No recent committed text yet.")
        } else {
            for commit in recentCommits {
                lines.append("- \(commit)")
            }
        }
        lines.append("")
        lines.append("## Sources")
        if sourceSummary.isEmpty {
            lines.append("- none")
        } else {
            sourceSummary.forEach { lines.append("- \($0)") }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func hash(_ content: String) -> String {
        SHA256.hash(data: Data(content.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public protocol LexicalContextProviding: Sendable {
    func snapshot() -> LexicalContextSnapshot?
}

public struct LexicalContextBuilder: Sendable {
    public var maxTerms: Int
    public var maxRecentCommits: Int

    public init(maxTerms: Int = 24, maxRecentCommits: Int = 8) {
        self.maxTerms = max(1, maxTerms)
        self.maxRecentCommits = max(1, maxRecentCommits)
    }

    public func snapshot(
        rimeCandidates: [String] = [],
        recentCommits: [String] = [],
        selectionHistory: [String] = [],
        acceptedAITerms: [LexicalContextTerm] = [],
        acceptedAIRecentCommits: [String] = [],
        acceptedAISourceSummary: [String] = [],
        persistentTerms: [LexicalContextTerm] = [],
        persistentRecentCommits: [String] = [],
        persistentSourceSummary: [String] = []
    ) -> LexicalContextSnapshot? {
        var scores: [String: (score: Double, source: String)] = [:]
        addTerms(selectionHistory.reversed(), source: "selection-history", baseScore: 0.86, to: &scores)
        addAcceptedTerms(acceptedAITerms, to: &scores)
        addTerms(recentCommits.reversed(), source: "recent-commits", baseScore: 0.72, to: &scores)
        addTerms(persistentTerms, to: &scores)

        let terms = scores
            .map { text, value in
                LexicalContextTerm(text: text, score: min(1, value.score), source: value.source)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.text < rhs.text
                }
                return lhs.score > rhs.score
            }
            .prefix(maxTerms)

        let commits = (
            persistentRecentCommits.compactMap(Self.sanitizedProfileText)
                + acceptedAIRecentCommits.compactMap(Self.sanitizedAcceptedProfileText)
                + recentCommits.compactMap(Self.sanitizedProfileText)
        )
            .suffix(maxRecentCommits)

        let snapshot = LexicalContextSnapshot(
            terms: Array(terms),
            recentCommits: Array(commits),
            toneProfile: toneProfile(from: Array(commits)),
            sourceSummary: sourceSummary(
                recentCommits: recentCommits,
                selectionHistory: selectionHistory,
                acceptedAITerms: acceptedAITerms,
                acceptedAIRecentCommits: acceptedAIRecentCommits,
                acceptedAISourceSummary: acceptedAISourceSummary,
                persistentTerms: persistentTerms,
                persistentSourceSummary: persistentSourceSummary
            )
        )
        return snapshot.isEmpty ? nil : snapshot
    }

    private func addTerms(
        _ texts: [String],
        source: String,
        baseScore: Double,
        to scores: inout [String: (score: Double, source: String)]
    ) {
        for (offset, text) in texts.enumerated() {
            guard let clean = Self.sanitizedProfileText(text) else {
                continue
            }
            let recencyBonus = max(0, 0.12 - Double(offset) * 0.01)
            let nextScore = baseScore + recencyBonus
            if let existing = scores[clean] {
                scores[clean] = (score: existing.score + nextScore * 0.25, source: existing.source)
            } else {
                scores[clean] = (score: nextScore, source: source)
            }
        }
    }

    private func addTerms(
        _ terms: [LexicalContextTerm],
        to scores: inout [String: (score: Double, source: String)]
    ) {
        for term in terms {
            guard let clean = Self.sanitizedProfileText(term.text) else {
                continue
            }
            let nextScore = max(0, min(1, term.score)) * 0.58
            if let existing = scores[clean] {
                scores[clean] = (score: existing.score + nextScore * 0.25, source: existing.source)
            } else {
                scores[clean] = (score: nextScore, source: term.source)
            }
        }
    }

    private func addAcceptedTerms(
        _ terms: [LexicalContextTerm],
        to scores: inout [String: (score: Double, source: String)]
    ) {
        for term in terms {
            guard let clean = Self.sanitizedAcceptedProfileText(term.text) else {
                continue
            }
            let nextScore = max(0, min(1, term.score)) * 0.82
            if let existing = scores[clean] {
                scores[clean] = (score: existing.score + nextScore * 0.25, source: existing.source)
            } else {
                scores[clean] = (score: nextScore, source: "accepted-ai")
            }
        }
    }

    private func toneProfile(from recentCommits: [String]) -> ToneProfile {
        acceptedStyleProfile(from: recentCommits)
    }

    public func acceptedStyleProfile(from recentCommits: [String]) -> ToneProfile {
        guard !recentCommits.isEmpty else {
            return ToneProfile()
        }
        let joined = recentCommits.joined(separator: "\n")
        let casualSignals = ["吧", "呀", "呢", "啦", "哈哈", "感觉"]
        let formalSignals = ["请", "您", "感谢", "确认", "同步", "推进"]
        let casualCount = countSignals(casualSignals, in: joined)
        let formalCount = countSignals(formalSignals, in: joined)
        let register: String
        if casualCount > formalCount {
            register = "casual"
        } else if formalCount > casualCount {
            register = "formal"
        } else {
            register = "neutral"
        }

        let technicalTokenCount = joined.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                token.count >= 2 && token.range(of: #"[A-Za-z_]"#, options: .regularExpression) != nil
            }
            .count
        let totalUnits = max(1, recentCommits.reduce(0) { $0 + max(1, $1.count) })
        let mixedCount = recentCommits.filter { text in
            text.range(of: #"\p{Han}"#, options: .regularExpression) != nil
                && text.range(of: #"[A-Za-z0-9_]"#, options: .regularExpression) != nil
        }.count
        let punctuationStyle = joined.contains("，") || joined.contains("。") || joined.contains("、")
            ? "zh"
            : joined.contains(",") || joined.contains(".")
                ? "ascii"
                : "mixed"

        return ToneProfile(
            register: register,
            technicalDensity: min(1, Double(technicalTokenCount) / Double(totalUnits)),
            codeSwitchingRatio: Double(mixedCount) / Double(max(1, recentCommits.count)),
            punctuationStyle: punctuationStyle,
            connectors: frequentSignals(["然后", "所以", "但是", "另外", "不过", "以及", "因为", "如果"], in: joined),
            endings: frequentEndings(recentCommits)
        )
    }

    private func sourceSummary(
        recentCommits: [String],
        selectionHistory: [String],
        acceptedAITerms: [LexicalContextTerm],
        acceptedAIRecentCommits: [String],
        acceptedAISourceSummary: [String],
        persistentTerms: [LexicalContextTerm],
        persistentSourceSummary: [String]
    ) -> [String] {
        var summary = [
            "recent-commits: \(recentCommits.count)",
            "selection-history: \(selectionHistory.count)",
            "accepted-ai: terms=\(acceptedAITerms.count) commits=\(acceptedAIRecentCommits.count)",
            "rime-userdb: \(persistentTerms.count)"
        ]
        summary.append(contentsOf: acceptedAISourceSummary)
        summary.append(contentsOf: persistentSourceSummary)
        return summary
    }

    private func countSignals(_ signals: [String], in text: String) -> Int {
        signals.reduce(0) { count, signal in
            count + text.components(separatedBy: signal).count - 1
        }
    }

    private func frequentSignals(_ signals: [String], in text: String) -> [String] {
        signals
            .map { signal in (signal, countSignals([signal], in: text)) }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0 < rhs.0
                }
                return lhs.1 > rhs.1
            }
            .prefix(5)
            .map(\.0)
    }

    private func frequentEndings(_ texts: [String]) -> [String] {
        var counts: [String: Int] = [:]
        for text in texts {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard clean.count >= 2 else {
                continue
            }
            let ending = String(clean.suffix(min(4, clean.count)))
            counts[ending, default: 0] += 1
        }
        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(5)
            .map(\.key)
    }

    public static func sanitizedProfileText(_ text: String) -> String? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 48 else {
            return nil
        }
        if TextProtection.requiresNoCorrection(clean) {
            return nil
        }
        if clean.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return nil
        }
        if clean.range(of: #"^(https?://|[A-Za-z]:/|/|~\/)"#, options: .regularExpression) != nil {
            return nil
        }
        let hasHan = clean.range(of: #"\p{Han}"#, options: .regularExpression) != nil
        let isTechnicalToken = clean.range(of: #"^[A-Za-z0-9_./:-]{2,}$"#, options: .regularExpression) != nil
        guard hasHan || !isTechnicalToken else {
            return nil
        }
        return clean
    }

    public static func sanitizedAcceptedProfileText(_ text: String) -> String? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 80 else {
            return nil
        }
        if TextProtection.containsSecretLikeContent(clean) {
            return nil
        }
        if clean.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return nil
        }
        if clean.range(of: #"(?i)^(https?://|www\.|[A-Za-z]:[\\/]|/|~/|\./|\.\./)"#, options: .regularExpression) != nil {
            return nil
        }
        if clean.range(of: #"(?i)^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#, options: .regularExpression) != nil {
            return nil
        }
        if clean.range(of: #"(?i)^[A-Z0-9.-]+\.[A-Z]{2,}([/?#].*)?$"#, options: .regularExpression) != nil {
            return nil
        }
        let hasHan = clean.range(of: #"\p{Han}"#, options: .regularExpression) != nil
        let hasWord = clean.range(of: #"[A-Za-z_]"#, options: .regularExpression) != nil
        guard hasHan || hasWord else {
            return nil
        }
        return clean
    }
}
