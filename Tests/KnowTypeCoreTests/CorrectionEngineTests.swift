import XCTest
@testable import KnowTypeCore

final class CorrectionEngineTests: XCTestCase {
    func testPinyinCorrectionProducesAccuratePrefixCandidates() async {
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "wo jue de zhege fagnan", locale: .zhCN)
        )

        XCTAssertEqual(candidates.first?.text, "我觉得这个方案")
        XCTAssertTrue(candidates.map(\.text).contains("我觉得这个方法"))
        XCTAssertTrue(candidates.map(\.text).contains("我觉得这个方向"))
    }

    func testEnglishCorrectionPreservesSentenceShape() async {
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "I thikn this approch", locale: .enUS)
        )

        XCTAssertEqual(candidates.first?.text, "I think this approach")
    }

    func testMixedInputProtectsTechnicalTokens() async {
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "zhege api latnecy youdian gao", locale: .mixed)
        )

        XCTAssertEqual(candidates.first?.text, "这个 API latency 有点高")
    }

    func testLevelZeroInputsAreNotCorrected() async {
        let engine = CorrectionEngine()
        let path = "/Users/zq/project/KnowType"
        let candidates = await engine.correct(InputContext(rawInput: path, locale: .mixed))

        XCTAssertEqual(candidates.first?.text, path)
        XCTAssertEqual(candidates.first?.source, "local-protection")
        XCTAssertEqual(candidates.first?.correctionLevel, CorrectionLevel.none)
    }
}
