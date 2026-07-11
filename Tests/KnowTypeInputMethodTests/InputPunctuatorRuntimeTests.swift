import XCTest
import KnowTypeCore
@testable import KnowTypeInputMethod

final class InputPunctuatorRuntimeTests: XCTestCase {
    func testChineseHalfWidthDirectPunctuation() {
        var runtime = InputPunctuatorRuntime()
        let state = InputModeState(
            textMode: .chinese,
            punctuationMode: .chinese,
            symbolWidth: .halfWidth
        )

        XCTAssertEqual(runtime.decision(for: ",", state: state), .commit("，"))
        XCTAssertEqual(runtime.decision(for: ".", state: state), .commit("。"))
        XCTAssertEqual(runtime.decision(for: "?", state: state), .commit("？"))
        XCTAssertEqual(runtime.decision(for: "!", state: state), .commit("！"))
        XCTAssertEqual(runtime.decision(for: ":", state: state), .commit("："))
        XCTAssertEqual(runtime.decision(for: ";", state: state), .commit("；"))
        XCTAssertEqual(runtime.decision(for: "(", state: state), .commit("（"))
        XCTAssertEqual(runtime.decision(for: ")", state: state), .commit("）"))
    }

    func testChineseHalfWidthPairsQuotesAndResetsPredictably() {
        var runtime = InputPunctuatorRuntime()
        let state = InputModeState(punctuationMode: .chinese, symbolWidth: .halfWidth)

        XCTAssertEqual(runtime.decision(for: "\"", state: state), .commit("“"))
        XCTAssertEqual(runtime.decision(for: "\"", state: state), .commit("”"))
        XCTAssertEqual(runtime.decision(for: "'", state: state), .commit("‘"))
        XCTAssertEqual(runtime.decision(for: "'", state: state), .commit("’"))

        runtime.resetPairingState()

        XCTAssertEqual(runtime.decision(for: "\"", state: state), .commit("“"))
        XCTAssertEqual(runtime.decision(for: "'", state: state), .commit("‘"))
    }

    func testQuoteContextOverridesAlternationAndUpdatesUnknownFallback() {
        var runtime = InputPunctuatorRuntime()
        let state = InputModeState(punctuationMode: .chinese, symbolWidth: .halfWidth)

        XCTAssertEqual(
            runtime.decision(
                for: "\"",
                context: InputPunctuatorContext(state: state, quoteContext: .closing)
            ),
            .commit("”")
        )
        XCTAssertEqual(runtime.decision(for: "\"", state: state), .commit("“"))
        XCTAssertEqual(
            runtime.decision(
                for: "'",
                context: InputPunctuatorContext(state: state, quoteContext: .opening)
            ),
            .commit("‘")
        )
        XCTAssertEqual(runtime.decision(for: "'", state: state), .commit("’"))
    }

    func testChineseHalfWidthEllipsisDashAndAsciiMinus() {
        var runtime = InputPunctuatorRuntime()
        let state = InputModeState(punctuationMode: .chinese, symbolWidth: .halfWidth)

        XCTAssertEqual(runtime.decision(for: "^", state: state), .commit("……"))
        XCTAssertEqual(runtime.decision(for: "_", state: state), .commit("——"))
        XCTAssertEqual(runtime.decision(for: "-", state: state), .commit("-"))
    }

    func testEnglishHalfWidthKeepsAsciiSymbols() {
        var runtime = InputPunctuatorRuntime()
        let state = InputModeState(punctuationMode: .english, symbolWidth: .halfWidth)

        for symbol in [",", ".", "/", "\\", "\"", "'", "^", "_", "-", "{", "}"] {
            XCTAssertEqual(runtime.decision(for: symbol, state: state), .commit(symbol))
        }
    }

    func testFullWidthStateUsesFullWidthTable() {
        var runtime = InputPunctuatorRuntime()
        let state = InputModeState(punctuationMode: .chinese, symbolWidth: .fullWidth)

        XCTAssertEqual(runtime.decision(for: "-", state: state), .commit("－"))
        XCTAssertEqual(runtime.decision(for: "@", state: state), .commit("＠"))
        XCTAssertEqual(runtime.decision(for: ".", state: state), .commit("．"))
    }

    func testChineseCandidateListSymbols() {
        var runtime = InputPunctuatorRuntime()
        let state = InputModeState(punctuationMode: .chinese, symbolWidth: .halfWidth)

        XCTAssertEqual(
            runtime.decision(for: "/", state: state),
            .showCandidates(
                InputSymbolCandidateSession(
                    trigger: "/",
                    candidates: [
                        InputSymbolCandidate(text: "、"),
                        InputSymbolCandidate(text: "/"),
                        InputSymbolCandidate(text: "／"),
                        InputSymbolCandidate(text: "÷")
                    ]
                )
            )
        )
    }

    func testDigitBeforePeriodUsesAsciiPeriodInChineseAndFullWidthModes() {
        var runtime = InputPunctuatorRuntime()
        let state = InputModeState(
            textMode: .chinese,
            punctuationMode: .chinese,
            symbolWidth: .fullWidth
        )

        XCTAssertEqual(
            runtime.decision(
                for: ".",
                context: InputPunctuatorContext(
                    state: state,
                    previousCharacterKind: .asciiDigit
                )
            ),
            .commit(".")
        )
    }

    func testDigitContextDoesNotChangeCommaOrActiveCompositionPeriod() {
        var runtime = InputPunctuatorRuntime()
        let state = InputModeState(punctuationMode: .chinese, symbolWidth: .halfWidth)

        XCTAssertEqual(
            runtime.decision(
                for: ",",
                context: InputPunctuatorContext(
                    state: state,
                    previousCharacterKind: .asciiDigit
                )
            ),
            .commit("，")
        )
        XCTAssertEqual(
            runtime.decision(
                for: ".",
                context: InputPunctuatorContext(
                    state: state,
                    previousCharacterKind: .asciiDigit,
                    hasActiveComposition: true
                )
            ),
            .commit("。")
        )
    }

    func testSecondPeriodAfterRecordedAsciiPeriodReturnsToChinesePunctuation() {
        var runtime = InputPunctuatorRuntime()
        let state = InputModeState(punctuationMode: .chinese, symbolWidth: .halfWidth)

        XCTAssertEqual(
            runtime.decision(
                for: ".",
                context: InputPunctuatorContext(
                    state: state,
                    previousCharacterKind: .asciiDigit
                )
            ),
            .commit(".")
        )
        XCTAssertEqual(
            runtime.decision(
                for: ".",
                context: InputPunctuatorContext(
                    state: state,
                    previousCharacterKind: .text
                )
            ),
            .commit("。")
        )
    }
}
