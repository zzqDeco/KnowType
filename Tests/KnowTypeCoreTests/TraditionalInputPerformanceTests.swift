import XCTest
@testable import KnowTypeCore

final class TraditionalInputPerformanceTests: XCTestCase {
    func testInteractiveQueryBudgetKeepsMixedInputResponsiveWithLargeLexicon() {
        let engine = TraditionalInputEngine(additionalLexiconEntries: Self.largeSyntheticLexicon())
        let context = InputContext(rawInput: "zhegeapi", locale: .mixed)

        let start = ContinuousClock.now
        let candidates = CorrectionEngine(traditionalInputEngine: engine)
            .localCorrect(context, queryOptions: .interactive)
        let elapsed = start.duration(to: .now)

        XCTAssertFalse(candidates.isEmpty)
        XCTAssertLessThan(Self.milliseconds(elapsed), 350)
    }

    func testDirectEnglishSpellingCorrectionSkipsPinyinSearch() {
        let engine = TraditionalInputEngine(additionalLexiconEntries: Self.largeSyntheticLexicon())
        let context = InputContext(rawInput: "latnecy", locale: .mixed)

        let start = ContinuousClock.now
        let candidates = CorrectionEngine(traditionalInputEngine: engine)
            .localCorrect(context, queryOptions: .interactive)
        let elapsed = start.duration(to: .now)

        XCTAssertEqual(candidates.first?.text, "latency")
        XCTAssertLessThan(Self.milliseconds(elapsed), 50)
    }

    private static func largeSyntheticLexicon() -> [TraditionalInputLexiconEntry] {
        let firstTokens = [
            "a", "ai", "an", "ang", "ba", "bai", "ban", "bao", "bei", "ben",
            "bi", "bian", "biao", "bie", "bin", "bing", "bo", "bu", "ca", "cai",
            "can", "cao", "ce", "cen", "cha", "chai", "chan", "chang", "che", "chen"
        ]
        let secondTokens = [
            "de", "ge", "hao", "he", "ji", "jian", "jie", "jin", "kan", "li",
            "ma", "me", "ming", "na", "ni", "qian", "shi", "wen", "xiang", "zai"
        ]
        var entries: [TraditionalInputLexiconEntry] = []
        for first in firstTokens {
            for second in secondTokens {
                for third in ["a", "pi", "qi", "xi", "zi"] {
                    entries.append(
                        TraditionalInputLexiconEntry(
                            pinyin: [first, second, third],
                            outputs: [
                                TraditionalInputLexiconOutput(
                                    text: "\(first)-\(second)-\(third)",
                                    confidence: 0.55
                                )
                            ]
                        )
                    )
                }
            }
        }
        entries.append(
            TraditionalInputLexiconEntry(
                pinyin: ["zhe", "ge", "a", "pi"],
                outputs: [TraditionalInputLexiconOutput(text: "这个啊皮", confidence: 0.96)]
            )
        )
        return entries
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(
            Double(duration.components.seconds) * 1000
                + Double(duration.components.attoseconds) / 1_000_000_000_000_000
        )
    }
}
