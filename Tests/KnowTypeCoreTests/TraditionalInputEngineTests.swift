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

    func testPinyinInitialAbbreviationsDecodeHighFrequencyPrefixes() {
        let engine = TraditionalInputEngine()

        XCTAssertEqual(engine.candidates(for: "wsm").first?.text, "为什么")
        XCTAssertEqual(engine.candidates(for: "sm").first?.text, "什么")
        XCTAssertEqual(engine.candidates(for: "zmb").first?.text, "怎么办")
    }

    func testCompactPinyinPrefixCompletionDecodesUnfinishedSyllable() {
        let engine = TraditionalInputEngine()
        let xianzCandidates = engine.candidates(for: "xianz").map(\.text)
        let xianshCandidates = engine.candidates(for: "xiansh").map(\.text)

        XCTAssertEqual(xianzCandidates.first, "现在")
        XCTAssertTrue(xianzCandidates.contains("限制"))
        XCTAssertEqual(xianshCandidates.first, "显示")
    }

    func testExactPinyinStaysAheadOfLongerPrefixCompletions() {
        let engine = TraditionalInputEngine()
        let candidates = engine.candidates(for: "xian").map(\.text)

        XCTAssertEqual(candidates.first, "先")
        XCTAssertTrue(candidates.contains("现在"))
    }

    func testSyllableFallbacksComposeBasicWords() {
        let engine = TraditionalInputEngine()

        XCTAssertEqual(engine.candidates(for: "nishi").first?.text, "你是")
        XCTAssertEqual(engine.candidates(for: "ni shi").first?.text, "你是")
        XCTAssertEqual(engine.candidates(for: "nixiang").first?.text, "你想")
        XCTAssertEqual(engine.candidates(for: "nishishei").first?.text, "你是谁")
    }

    func testSingleSyllableShowsExpandedHomophoneCandidates() {
        let engine = TraditionalInputEngine()
        let candidates = engine.candidates(for: "ni").map(\.text)

        XCTAssertEqual(candidates.first, "你")
        XCTAssertTrue(candidates.contains("呢"))
        XCTAssertTrue(candidates.contains("尼"))
        XCTAssertTrue(candidates.contains("拟"))
        XCTAssertGreaterThanOrEqual(candidates.count, 14)
    }

    func testTrailingIncompleteSyllableCanStillCompose() {
        let engine = TraditionalInputEngine()
        let nihCandidates = engine.candidates(for: "nih").map(\.text)

        XCTAssertEqual(engine.candidates(for: "niw").first?.text, "你我")
        XCTAssertEqual(engine.candidates(for: "nish").first?.text, "你是")
        XCTAssertEqual(nihCandidates.first, "你好")
        XCTAssertTrue(nihCandidates.contains("你"))
        XCTAssertTrue(nihCandidates.contains("呢"))
        XCTAssertLessThan(nihCandidates.firstIndex(of: "你") ?? Int.max, 9)
        XCTAssertLessThan(nihCandidates.firstIndex(of: "呢") ?? Int.max, 9)
    }

    func testCommonCompactPinyinComposesBeyondSeedExamples() {
        let engine = TraditionalInputEngine()

        XCTAssertEqual(engine.candidates(for: "zhongguoren").first?.text, "中国人")
        XCTAssertEqual(engine.candidates(for: "zhongwen").first?.text, "中文")
        XCTAssertEqual(engine.candidates(for: "keyi").first?.text, "可以")
        XCTAssertEqual(engine.candidates(for: "meiyou").first?.text, "没有")
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
