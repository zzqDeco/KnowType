import XCTest
@testable import KnowTypeCore

final class TraditionalInputEngineTests: XCTestCase {
    func testFullPinyinProducesMultiplePrefixCandidates() {
        let engine = TraditionalInputEngine()
        let candidates = engine.candidates(for: "wo jue de zhege fagnan")

        XCTAssertEqual(candidates.first?.text, "我觉得这个方案")
        XCTAssertTrue(candidates.map(\.text).contains("我觉得这个方法"))
        XCTAssertTrue(candidates.map(\.text).contains("我觉得这个方向"))
    }

    func testCompactPinyinSegmentationUsesParseableSyllables() {
        let engine = TraditionalInputEngine()
        let candidates = engine.candidates(for: "wojuedezhegefagnan")

        XCTAssertEqual(candidates.first?.text, "我觉得这个方案")
    }

    func testStandaloneSyllableReturnsManySingleCharacterCandidates() {
        let engine = TraditionalInputEngine()
        let candidateTexts = engine.candidates(for: "ni").map(\.text)

        XCTAssertEqual(candidateTexts.first, "你")
        XCTAssertTrue(candidateTexts.contains("尼"))
        XCTAssertTrue(candidateTexts.contains("呢"))
        XCTAssertGreaterThanOrEqual(candidateTexts.count, 10)
    }

    func testTrailingPartialSyllableKeepsPrefixAndOffersPhraseCandidates() {
        let engine = TraditionalInputEngine()
        let candidateTexts = engine.candidates(for: "nih").map(\.text)

        XCTAssertEqual(candidateTexts.first, "你好")
        XCTAssertTrue(candidateTexts.contains("你"))
        XCTAssertTrue(candidateTexts.contains("尼"))
    }

    func testCompactSentencePinyinDecodesCommonPhrase() {
        let engine = TraditionalInputEngine()

        XCTAssertEqual(engine.candidates(for: "nishi").first?.text, "你是")
        XCTAssertEqual(engine.candidates(for: "nishishei").first?.text, "你是谁")
    }

    func testPartialSecondSyllableUsesLegalPinyinPrefixes() {
        let engine = TraditionalInputEngine()

        XCTAssertEqual(engine.candidates(for: "xianz").first?.text, "现在")
        XCTAssertEqual(engine.candidates(for: "niw").first?.text, "你我")
    }

    func testCompleteSyllableIsNotSplitIntoInitialPartials() {
        let engine = TraditionalInputEngine()
        let candidateTexts = engine.candidates(for: "fang").map(\.text)

        XCTAssertEqual(candidateTexts.first, "方")
        XCTAssertFalse(candidateTexts.contains("方案个"))
        XCTAssertFalse(candidateTexts.contains("方案高"))
    }

    func testUnseededInitialAbbreviationDoesNotComposeArbitrarySingleCharacters() {
        let engine = TraditionalInputEngine()
        let candidateTexts = engine.candidates(for: "qqq").map(\.text)

        XCTAssertFalse(candidateTexts.contains("去去去"))
        XCTAssertFalse(candidateTexts.contains("区去去"))
    }

    func testSingleInitialCanPrecedePinyinAndTechnicalTail() {
        let engine = TraditionalInputEngine()

        XCTAssertEqual(engine.candidates(for: "w de").first?.text, "我的")
        XCTAssertEqual(engine.candidates(for: "w de fangan").first?.text, "我的方案")
        XCTAssertEqual(engine.candidates(for: "w API").first?.text, "我 API")
    }

    func testInitialAbbreviationDecodesCommonExpression() {
        let engine = TraditionalInputEngine()

        XCTAssertEqual(engine.candidates(for: "wsm").first?.text, "为什么")
        XCTAssertEqual(engine.candidates(for: "sm").first?.text, "什么")
        XCTAssertEqual(engine.candidates(for: "zmb").first?.text, "怎么办")
        XCTAssertEqual(engine.candidates(for: "wzmb").first?.text, "我怎么办")
        XCTAssertEqual(engine.candidates(for: "wzmy").first?.text, "我怎么样")
    }

    func testSpacedInitialAbbreviationsUseIndexedPartialMatching() {
        let engine = TraditionalInputEngine()

        XCTAssertEqual(engine.candidates(for: "w s m").first?.text, "为什么")
        XCTAssertEqual(engine.candidates(for: "s m").first?.text, "什么")
        XCTAssertEqual(engine.candidates(for: "z m b").first?.text, "怎么办")
    }

    func testPinyinInputAnalysisSeparatesLocalAndFallbackCases() {
        let engine = TraditionalInputEngine()
        let knownPartial = engine.analyzePinyinInput("xian z")
        let unknownInitials = engine.analyzePinyinInput("wzm")
        let technicalToken = engine.analyzePinyinInput("css")
        let englishWord = engine.analyzePinyinInput("change")

        XCTAssertTrue(knownPartial.isLikelyPinyinComposition)
        XCTAssertTrue(knownPartial.hasPartialToken)
        XCTAssertTrue(knownPartial.hasLocalCandidates)
        XCTAssertTrue(unknownInitials.isLikelyPinyinComposition)
        XCTAssertTrue(unknownInitials.hasInitialAbbreviation)
        XCTAssertFalse(unknownInitials.hasLocalCandidates)
        XCTAssertFalse(technicalToken.isLikelyPinyinComposition)
        XCTAssertFalse(englishWord.isLikelyPinyinComposition)
    }

    func testCompactPinyinDecodesCommonQuestionAndActionPhrases() {
        let engine = TraditionalInputEngine()

        XCTAssertEqual(engine.candidates(for: "xiansh").first?.text, "显示")
        XCTAssertTrue(engine.candidates(for: "xiansh").map(\.text).contains("现实"))
        XCTAssertEqual(engine.candidates(for: "zhongguoren").first?.text, "中国人")
        XCTAssertEqual(engine.candidates(for: "woxiangqukan").first?.text, "我想去看")
    }

    func testMVPExamplesDecodeThroughSeedLexicon() {
        let engine = TraditionalInputEngine()
        let examples = [
            ("zhege gongneng bushi hen wending", "这个功能不是很稳定"),
            ("jiekou yan chi youdian gao", "接口延迟有点高"),
            ("wo xiang ba zhege wenti xiugai yixia", "我想把这个问题修改一下")
        ]

        for (raw, expected) in examples {
            XCTAssertEqual(engine.candidates(for: raw).first?.text, expected)
        }
    }

    func testGongnengKeepsSeededPrefixAlternatives() {
        let engine = TraditionalInputEngine()
        let candidateTexts = engine.candidates(for: "zhege gongneng").map(\.text)

        XCTAssertEqual(candidateTexts.first, "这个功能")
        XCTAssertTrue(candidateTexts.contains("这个工具"))
        XCTAssertTrue(candidateTexts.contains("这个模块"))
    }

    func testMixedInputPreservesTechnicalTokens() {
        let engine = TraditionalInputEngine()
        let candidates = engine.candidates(for: "zhege API latency youdian gao")

        XCTAssertEqual(candidates.first?.text, "这个 API latency 有点高")
    }

    func testPassthroughPreservesASCIICasing() {
        let engine = TraditionalInputEngine()
        let candidates = engine.candidates(for: "I xiang zhege")

        XCTAssertEqual(candidates.first?.text, "I 想这个")
    }

    func testCapitalizedEnglishNameIsNotTranslatedAsStandalonePinyin() {
        let engine = TraditionalInputEngine()
        let candidateTexts = engine.candidates(for: "I thikn Xiang").map(\.text)

        XCTAssertFalse(candidateTexts.contains("I thikn 想"))
    }

    func testCapitalizedStandaloneCompactPinyinIsNotTranslatedWhenPreserved() {
        let engine = TraditionalInputEngine()
        let candidateTexts = engine.candidates(for: "Xiang").map(\.text)

        XCTAssertFalse(candidateTexts.contains("想"))
    }

    func testCapitalizedPinyinCanDecodeWhenNamePreservationIsDisabled() {
        let engine = TraditionalInputEngine()
        let candidates = engine.candidates(
            for: "Wo jue de zhege fagnan",
            preserveCapitalizedPinyin: false
        )

        XCTAssertEqual(candidates.first?.text, "我觉得这个方案")
    }

    func testSpacedTrailingPartialSyllableMatchesCompactBehavior() {
        let engine = TraditionalInputEngine()

        XCTAssertEqual(engine.candidates(for: "ni h").first?.text, "你好")
        XCTAssertEqual(engine.candidates(for: "xian z").first?.text, "现在")
    }

    func testDuplicateCandidatesKeepHighestConfidenceAcrossTokenizations() {
        let engine = TraditionalInputEngine()
        let compactCandidate = engine.candidates(for: "nihao").first
        let spacedCandidate = engine.candidates(for: "ni hao").first

        XCTAssertEqual(compactCandidate?.text, "你好")
        XCTAssertEqual(spacedCandidate?.text, "你好")
        XCTAssertEqual(compactCandidate?.confidence ?? 0, spacedCandidate?.confidence ?? 0, accuracy: 0.0001)
        XCTAssertGreaterThan(compactCandidate?.confidence ?? 0, 0.96)
    }

    func testXiaoheHookCanMapKnownDoublePinyinSyllables() {
        let engine = TraditionalInputEngine(scheme: .xiaohe)
        let candidates = engine.candidates(for: "ni hc")

        XCTAssertEqual(candidates.first?.text, "你好")
    }

    func testAdditionalLexiconEntriesAreIndexedForSpacedAndCompactInput() {
        let engine = TraditionalInputEngine(additionalLexiconEntries: [
            TraditionalInputLexiconEntry(
                pinyin: ["ce", "shi", "ci"],
                outputs: [TraditionalInputLexiconOutput(text: "测试词", confidence: 0.995)]
            )
        ])

        XCTAssertEqual(engine.candidates(for: "ce shi ci").first?.text, "测试词")
        XCTAssertEqual(engine.candidates(for: "ceshici").first?.text, "测试词")
    }

    func testAdditionalLexiconEntriesPreserveAmbiguousCompactSplits() {
        let engine = TraditionalInputEngine(additionalLexiconEntries: [
            TraditionalInputLexiconEntry(
                pinyin: ["xi", "an"],
                outputs: [TraditionalInputLexiconOutput(text: "西安", confidence: 0.995)]
            )
        ])
        let candidateTexts = engine.candidates(for: "xian").map(\.text)

        XCTAssertEqual(candidateTexts.first, "西安")
        XCTAssertTrue(candidateTexts.contains("现"))
    }

    func testAdditionalLexiconEntriesAreNormalizedAndMergedByHighestConfidence() {
        let engine = TraditionalInputEngine(additionalLexiconEntries: [
            TraditionalInputLexiconEntry(
                pinyin: [" FANG ", " AN "],
                outputs: [TraditionalInputLexiconOutput(text: "方案", confidence: 0.995)]
            )
        ])

        let candidate = engine.candidates(for: "fang an").first

        XCTAssertEqual(candidate?.text, "方案")
        XCTAssertEqual(candidate?.confidence ?? 0, 0.995, accuracy: 0.0001)
    }

    func testSyntheticLargeLexiconUsesIndexedPartialLookupCap() {
        let entries = (0..<120).map { index in
            TraditionalInputLexiconEntry(
                pinyin: ["zsynthetic\(index)"],
                outputs: [TraditionalInputLexiconOutput(text: "扩展\(index)", confidence: 0.6)]
            )
        }
        let engine = TraditionalInputEngine(additionalLexiconEntries: entries)
        let syntheticCandidates = engine
            .candidates(for: "z")
            .filter { $0.text.hasPrefix("扩展") }

        XCTAssertLessThanOrEqual(syntheticCandidates.count, 64)
    }

    func testEmptyAdditionalLexiconEntriesAreIgnored() {
        let engine = TraditionalInputEngine(additionalLexiconEntries: [
            TraditionalInputLexiconEntry(
                pinyin: ["  "],
                outputs: [TraditionalInputLexiconOutput(text: "空", confidence: 1.0)]
            ),
            TraditionalInputLexiconEntry(
                pinyin: ["ce"],
                outputs: []
            )
        ])

        XCTAssertFalse(engine.candidates(for: "ce").map(\.text).contains("空"))
    }
}
