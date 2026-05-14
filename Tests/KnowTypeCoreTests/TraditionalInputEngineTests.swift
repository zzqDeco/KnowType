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

    func testInitialAbbreviationDecodesCommonExpression() {
        let engine = TraditionalInputEngine()

        XCTAssertEqual(engine.candidates(for: "wsm").first?.text, "为什么")
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

    func testCapitalizedPinyinCanDecodeWhenNamePreservationIsDisabled() {
        let engine = TraditionalInputEngine()
        let candidates = engine.candidates(
            for: "Wo jue de zhege fagnan",
            preserveCapitalizedPinyin: false
        )

        XCTAssertEqual(candidates.first?.text, "我觉得这个方案")
    }

    func testXiaoheHookCanMapKnownDoublePinyinSyllables() {
        let engine = TraditionalInputEngine(scheme: .xiaohe)
        let candidates = engine.candidates(for: "ni hc")

        XCTAssertEqual(candidates.first?.text, "你好")
    }
}
