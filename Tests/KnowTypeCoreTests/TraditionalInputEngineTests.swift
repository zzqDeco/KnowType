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

    func testMixedInputPreservesTechnicalTokens() {
        let engine = TraditionalInputEngine()
        let candidates = engine.candidates(for: "zhege API latency youdian gao")

        XCTAssertEqual(candidates.first?.text, "这个 API latency 有点高")
    }

    func testXiaoheHookCanMapKnownDoublePinyinSyllables() {
        let engine = TraditionalInputEngine(scheme: .xiaohe)
        let candidates = engine.candidates(for: "ni hc")

        XCTAssertEqual(candidates.first?.text, "你好")
    }
}
