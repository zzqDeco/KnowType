import XCTest
import KnowTypeCore
@testable import KnowTypeInputMethod

final class InputSymbolModeTests: XCTestCase {
    func testChineseModeMapsSentenceBracketsBookTitleAndDunhaoPunctuation() {
        let transformer = InputSymbolTransformer()

        XCTAssertEqual(transformer.text(for: ",", mode: .chinese), "，")
        XCTAssertEqual(transformer.text(for: ".", mode: .chinese), "。")
        XCTAssertEqual(transformer.text(for: "?", mode: .chinese), "？")
        XCTAssertEqual(transformer.text(for: "!", mode: .chinese), "！")
        XCTAssertEqual(transformer.text(for: ":", mode: .chinese), "：")
        XCTAssertEqual(transformer.text(for: ";", mode: .chinese), "；")
        XCTAssertEqual(transformer.text(for: "(", mode: .chinese), "（")
        XCTAssertEqual(transformer.text(for: ")", mode: .chinese), "）")
        XCTAssertEqual(transformer.text(for: "[", mode: .chinese), "【")
        XCTAssertEqual(transformer.text(for: "]", mode: .chinese), "】")
        XCTAssertEqual(transformer.text(for: "/", mode: .chinese), "、")
        XCTAssertEqual(transformer.text(for: "<", mode: .chinese), "《")
        XCTAssertEqual(transformer.text(for: ">", mode: .chinese), "》")
    }

    func testChineseHalfWidthModeKeepsCodePathAndOperatorSymbolsAscii() {
        let transformer = InputSymbolTransformer()
        let state = InputModeState(
            textMode: .chinese,
            punctuationMode: .chinese,
            symbolWidth: .halfWidth
        )

        for symbol in ["-", "_", "+", "=", "\\", "@", "#", "$", "%", "^", "&", "*", "|", "~", "`", "{", "}"] {
            XCTAssertEqual(transformer.text(for: symbol, state: state), symbol)
        }
    }

    func testEnglishModeKeepsAsciiPunctuation() {
        let transformer = InputSymbolTransformer()

        XCTAssertEqual(transformer.text(for: ",", mode: .english), ",")
        XCTAssertEqual(transformer.text(for: ".", mode: .english), ".")
        XCTAssertEqual(transformer.text(for: "/", mode: .english), "/")
    }

    func testInputModeStateCarriesIndependentTextPunctuationAndWidthModes() {
        var state = InputModeState(
            textMode: .chinese,
            punctuationMode: .chinese,
            symbolWidth: .halfWidth
        )

        state.togglePunctuationMode()
        XCTAssertEqual(state.textMode, .chinese)
        XCTAssertEqual(state.punctuationMode, .english)
        XCTAssertEqual(state.symbolWidth, .halfWidth)

        state.toggleSymbolWidth()
        XCTAssertEqual(state.textMode, .chinese)
        XCTAssertEqual(state.punctuationMode, .english)
        XCTAssertEqual(state.symbolWidth, .fullWidth)
    }

    func testFullWidthStateMapsAsciiSymbolsWithoutChangingChinesePunctuationMode() {
        let transformer = InputSymbolTransformer()
        let state = InputModeState(
            textMode: .chinese,
            punctuationMode: .chinese,
            symbolWidth: .fullWidth
        )

        XCTAssertEqual(transformer.text(for: ",", state: state), "，")
        XCTAssertEqual(transformer.text(for: "-", state: state), "－")
        XCTAssertEqual(transformer.text(for: "@", state: state), "＠")
        XCTAssertEqual(transformer.text(for: "+", state: state), "＋")
    }

    func testEnglishPunctuationModeCanStillUseFullWidthSymbols() {
        let transformer = InputSymbolTransformer()
        let state = InputModeState(
            textMode: .chinese,
            punctuationMode: .english,
            symbolWidth: .fullWidth
        )

        XCTAssertEqual(transformer.text(for: ".", state: state), "．")
        XCTAssertEqual(transformer.text(for: "@", state: state), "＠")
    }

    func testLegacyAppPreferencesDoNotDefineTheRuntimeInitialState() {
        let preferences = InputModePreferences(
            defaultState: InputModeState(
                textMode: .chinese,
                punctuationMode: .english,
                symbolWidth: .fullWidth
            ),
            codeAppState: InputModeState(
                textMode: .ascii,
                punctuationMode: .chinese,
                symbolWidth: .halfWidth
            )
        )
        let machine = InputModeStateMachine(symbolWidth: preferences.globalSymbolWidth)

        XCTAssertEqual(
            machine.snapshot.state,
            InputModeState(
                textMode: .chinese,
                punctuationMode: .chinese,
                symbolWidth: .fullWidth
            )
        )
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
