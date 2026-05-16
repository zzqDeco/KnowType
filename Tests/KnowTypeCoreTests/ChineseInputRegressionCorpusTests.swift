import XCTest
@testable import KnowTypeCore

final class ChineseInputRegressionCorpusTests: XCTestCase {
    func testTraditionalInputCorpus() {
        let engine = TraditionalInputEngine()

        for corpusCase in Self.traditionalInputCases {
            let candidates = engine.candidates(for: corpusCase.rawInput)
            let candidateTexts = candidates.map(\.text)

            for expectation in corpusCase.expectations {
                switch expectation {
                case let .exactTop(expected):
                    XCTAssertEqual(
                        candidateTexts.first,
                        expected,
                        "\(corpusCase.id) should rank \(expected) first for \(corpusCase.rawInput)"
                    )
                case let .contains(expected):
                    XCTAssertTrue(
                        candidateTexts.contains(expected),
                        "\(corpusCase.id) should include \(expected) for \(corpusCase.rawInput); got \(candidateTexts)"
                    )
                case let .minimumCount(expected):
                    XCTAssertGreaterThanOrEqual(
                        candidateTexts.count,
                        expected,
                        "\(corpusCase.id) should expose at least \(expected) candidates for \(corpusCase.rawInput)"
                    )
                }
            }
        }
    }

    func testFallbackClassificationCorpus() async {
        for corpusCase in Self.fallbackClassificationCases {
            let provider = CorpusRecordingProvider()
            let engine = CorrectionEngine(cloudProvider: provider)

            let candidates = await engine.correct(InputContext(rawInput: corpusCase.rawInput, locale: .zhCN))
            let requests = await provider.requests

            switch corpusCase.expectedClassification {
            case .localChineseCandidates:
                XCTAssertTrue(
                    requests.isEmpty,
                    "\(corpusCase.id) should stay local for \(corpusCase.rawInput)"
                )
                XCTAssertEqual(candidates.first?.source, "local-traditional-input")
            case .cloudPinyinFallback:
                XCTAssertEqual(
                    requests.first?.task,
                    .correction,
                    "\(corpusCase.id) should ask the provider for pinyin fallback"
                )
                XCTAssertEqual(requests.first?.rawInput, corpusCase.rawInput)
            case .notPinyinFallback:
                XCTAssertTrue(
                    requests.isEmpty,
                    "\(corpusCase.id) should not classify \(corpusCase.rawInput) as pinyin fallback"
                )
            }
        }
    }

    func testUserSelectionRankingCorpus() async {
        for corpusCase in Self.userSelectionRankingCases {
            let engine = CorrectionEngine()

            let defaultCandidates = await engine.correct(
                InputContext(rawInput: corpusCase.rawInput, locale: .zhCN)
            )
            let boostedCandidates = await engine.correct(
                InputContext(
                    rawInput: corpusCase.rawInput,
                    locale: .zhCN,
                    userSelectionHistory: corpusCase.selectionHistory
                )
            )
            let boostedTexts = boostedCandidates.map(\.text)

            XCTAssertEqual(
                defaultCandidates.first?.text,
                corpusCase.defaultTopCandidate,
                "\(corpusCase.id) should document the baseline top candidate"
            )
            XCTAssertEqual(
                boostedCandidates.first?.text,
                corpusCase.boostedTopCandidate,
                "\(corpusCase.id) should boost the selected candidate"
            )
            for expectedCandidate in corpusCase.expectedContains {
                XCTAssertTrue(
                    boostedTexts.contains(expectedCandidate),
                    "\(corpusCase.id) should keep \(expectedCandidate) available after ranking boost"
                )
            }
        }
    }

    func testLargeLexiconBoundaryCorpus() {
        for corpusCase in Self.largeLexiconBoundaryCases {
            let entries = (0..<corpusCase.entryCount).map { index in
                TraditionalInputLexiconEntry(
                    pinyin: [Self.syntheticLexiconToken(index)],
                    outputs: [
                        TraditionalInputLexiconOutput(
                            text: "\(corpusCase.outputPrefix)\(index)",
                            confidence: 0.7
                        )
                    ]
                )
            }
            let engine = TraditionalInputEngine(additionalLexiconEntries: entries)

            let exactCandidates = engine.candidates(for: Self.syntheticLexiconToken(corpusCase.exactIndex))
            XCTAssertEqual(
                exactCandidates.first?.text,
                "\(corpusCase.outputPrefix)\(corpusCase.exactIndex)",
                "\(corpusCase.id) should still resolve exact entries near the large lexicon boundary"
            )

            let partialMatches = engine
                .candidates(for: corpusCase.partialInput)
                .map(\.text)
                .filter { $0.hasPrefix(corpusCase.outputPrefix) }

            XCTAssertGreaterThanOrEqual(
                partialMatches.count,
                corpusCase.minimumPartialMatches,
                "\(corpusCase.id) should expose a useful partial-match candidate set"
            )
            XCTAssertLessThanOrEqual(
                partialMatches.count,
                corpusCase.maximumPartialMatches,
                "\(corpusCase.id) should keep partial lookup bounded"
            )
        }
    }

    private static let traditionalInputCases: [TraditionalInputCorpusCase] = [
        TraditionalInputCorpusCase(
            id: "compact-question",
            rawInput: "nishishei",
            expectations: [
                .exactTop("你是谁")
            ]
        ),
        TraditionalInputCorpusCase(
            id: "compact-action-phrase",
            rawInput: "woxiangqukan",
            expectations: [
                .exactTop("我想去看")
            ]
        ),
        TraditionalInputCorpusCase(
            id: "initial-abbreviation",
            rawInput: "wsm",
            expectations: [
                .exactTop("为什么"),
                .contains("为啥么")
            ]
        ),
        TraditionalInputCorpusCase(
            id: "partial-third-syllable",
            rawInput: "xianz",
            expectations: [
                .exactTop("现在"),
                .contains("现")
            ]
        ),
        TraditionalInputCorpusCase(
            id: "partial-second-syllable",
            rawInput: "niw",
            expectations: [
                .exactTop("你我"),
                .contains("你")
            ]
        ),
        TraditionalInputCorpusCase(
            id: "partial-hao",
            rawInput: "nih",
            expectations: [
                .exactTop("你好"),
                .contains("你"),
                .contains("尼")
            ]
        ),
        TraditionalInputCorpusCase(
            id: "single-syllable-ni",
            rawInput: "ni",
            expectations: [
                .exactTop("你"),
                .contains("尼"),
                .contains("呢"),
                .minimumCount(10)
            ]
        ),
        TraditionalInputCorpusCase(
            id: "single-syllable-shi",
            rawInput: "shi",
            expectations: [
                .exactTop("是"),
                .contains("时"),
                .contains("事"),
                .minimumCount(10)
            ]
        ),
        TraditionalInputCorpusCase(
            id: "single-syllable-de",
            rawInput: "de",
            expectations: [
                .exactTop("的"),
                .contains("得"),
                .contains("地"),
                .minimumCount(3)
            ]
        ),
        TraditionalInputCorpusCase(
            id: "single-syllable-le",
            rawInput: "le",
            expectations: [
                .exactTop("了"),
                .contains("乐"),
                .minimumCount(2)
            ]
        )
    ]

    private static let fallbackClassificationCases: [FallbackClassificationCorpusCase] = [
        FallbackClassificationCorpusCase(
            id: "seeded-initial-abbreviation-stays-local",
            rawInput: "wsm",
            expectedClassification: .localChineseCandidates
        ),
        FallbackClassificationCorpusCase(
            id: "unknown-initial-abbreviation-uses-cloud-fallback",
            rawInput: "wzm",
            expectedClassification: .cloudPinyinFallback
        ),
        FallbackClassificationCorpusCase(
            id: "technical-token-does-not-use-pinyin-fallback",
            rawInput: "css",
            expectedClassification: .notPinyinFallback
        ),
        FallbackClassificationCorpusCase(
            id: "english-word-does-not-use-pinyin-fallback",
            rawInput: "change",
            expectedClassification: .notPinyinFallback
        )
    ]

    private static let userSelectionRankingCases: [UserSelectionRankingCorpusCase] = [
        UserSelectionRankingCorpusCase(
            id: "selected-fangan-alternative-ranks-first",
            rawInput: "fangan",
            selectionHistory: ["方法"],
            defaultTopCandidate: "方案",
            boostedTopCandidate: "方法",
            expectedContains: ["方案", "方向"]
        )
    ]

    private static let largeLexiconBoundaryCases: [LargeLexiconBoundaryCorpusCase] = [
        LargeLexiconBoundaryCorpusCase(
            id: "partial-lookup-is-useful-and-bounded",
            entryCount: 120,
            exactIndex: 119,
            partialInput: "z",
            outputPrefix: "扩展边界",
            minimumPartialMatches: 32,
            maximumPartialMatches: 64
        )
    ]

    private static func syntheticLexiconToken(_ index: Int) -> String {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        let first = letters[(index / 26) % 26]
        let second = letters[index % 26]
        return "zreg\(first)\(second)"
    }
}

private struct TraditionalInputCorpusCase {
    var id: String
    var rawInput: String
    var expectations: [CandidateExpectation]
}

private enum CandidateExpectation {
    case exactTop(String)
    case contains(String)
    case minimumCount(Int)
}

private struct FallbackClassificationCorpusCase {
    var id: String
    var rawInput: String
    var expectedClassification: FallbackClassification
}

private enum FallbackClassification {
    case localChineseCandidates
    case cloudPinyinFallback
    case notPinyinFallback
}

private struct UserSelectionRankingCorpusCase {
    var id: String
    var rawInput: String
    var selectionHistory: [String]
    var defaultTopCandidate: String
    var boostedTopCandidate: String
    var expectedContains: [String]
}

private struct LargeLexiconBoundaryCorpusCase {
    var id: String
    var entryCount: Int
    var exactIndex: Int
    var partialInput: String
    var outputPrefix: String
    var minimumPartialMatches: Int
    var maximumPartialMatches: Int
}

private actor CorpusRecordingProvider: LLMProvider {
    nonisolated let providerName = "corpus-recording"
    private var recordedRequests: [LLMRequest] = []

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        recordedRequests.append(request)
        return LLMResponse(candidates: [
            LLMCandidate(text: "云候选", confidence: 0.7)
        ])
    }

    var requests: [LLMRequest] {
        recordedRequests
    }
}
