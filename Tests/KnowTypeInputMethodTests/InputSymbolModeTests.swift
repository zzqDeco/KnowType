import XCTest
@testable import KnowTypeInputMethod

final class InputSymbolModeTests: XCTestCase {
    func testChineseModeMapsCommonAsciiPunctuation() {
        let transformer = InputSymbolTransformer()

        XCTAssertEqual(transformer.text(for: ",", mode: .chinese), "，")
        XCTAssertEqual(transformer.text(for: ".", mode: .chinese), "。")
        XCTAssertEqual(transformer.text(for: "?", mode: .chinese), "？")
        XCTAssertEqual(transformer.text(for: "/", mode: .chinese), "、")
        XCTAssertEqual(transformer.text(for: "<", mode: .chinese), "《")
        XCTAssertEqual(transformer.text(for: ">", mode: .chinese), "》")
        XCTAssertEqual(transformer.text(for: "@", mode: .chinese), "@")
    }

    func testEnglishModeKeepsAsciiPunctuation() {
        let transformer = InputSymbolTransformer()

        XCTAssertEqual(transformer.text(for: ",", mode: .english), ",")
        XCTAssertEqual(transformer.text(for: ".", mode: .english), ".")
        XCTAssertEqual(transformer.text(for: "/", mode: .english), "/")
    }

    func testSymbolDetectionRejectsLettersNumbersAndMultiCharacterText() {
        XCTAssertTrue(InputSymbolTransformer.isSymbolInput("!"))
        XCTAssertTrue(InputSymbolTransformer.isSymbolInput("@"))
        XCTAssertFalse(InputSymbolTransformer.isSymbolInput("a"))
        XCTAssertFalse(InputSymbolTransformer.isSymbolInput("1"))
        XCTAssertFalse(InputSymbolTransformer.isSymbolInput("..."))
    }

    func testSymbolModeTogglesBetweenChineseAndEnglish() {
        var mode = InputSymbolMode.chinese

        mode.toggle()
        XCTAssertEqual(mode, .english)

        mode.toggle()
        XCTAssertEqual(mode, .chinese)
    }

    func testSymbolCommitAppendsToCommittedCandidateOrRawFallback() {
        XCTAssertEqual(
            InputSymbolCommitPolicy.result(
                symbol: "。",
                rawInput: "ni",
                baseCommitResult: .commit("你")
            ),
            .commit("你。")
        )
        XCTAssertEqual(
            InputSymbolCommitPolicy.result(
                symbol: "。",
                rawInput: "raw",
                baseCommitResult: .noAction
            ),
            .commit("raw。")
        )
        XCTAssertEqual(
            InputSymbolCommitPolicy.result(
                symbol: "。",
                rawInput: "",
                baseCommitResult: .noAction
            ),
            .commit("。")
        )
    }
}
