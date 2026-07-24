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

        XCTAssertEqual(runtime.rule(for: ",", state: state), .direct("，"))
        XCTAssertEqual(runtime.rule(for: ".", state: state), .direct("。"))
        XCTAssertEqual(runtime.rule(for: "?", state: state), .direct("？"))
        XCTAssertEqual(runtime.rule(for: "!", state: state), .direct("！"))
        XCTAssertEqual(runtime.rule(for: ":", state: state), .direct("："))
        XCTAssertEqual(runtime.rule(for: ";", state: state), .direct("；"))
        XCTAssertEqual(runtime.rule(for: "(", state: state), .direct("（"))
        XCTAssertEqual(runtime.rule(for: ")", state: state), .direct("）"))
    }

    func testChineseHalfWidthPairsQuotesAndResetsPredictably() {
        var runtime = InputPunctuatorRuntime()
        let state = InputModeState(punctuationMode: .chinese, symbolWidth: .halfWidth)

        XCTAssertEqual(runtime.rule(for: "\"", state: state), .direct("“"))
        XCTAssertEqual(runtime.rule(for: "\"", state: state), .direct("”"))
        XCTAssertEqual(runtime.rule(for: "'", state: state), .direct("‘"))
        XCTAssertEqual(runtime.rule(for: "'", state: state), .direct("’"))

        runtime.resetPairingState()

        XCTAssertEqual(runtime.rule(for: "\"", state: state), .direct("“"))
        XCTAssertEqual(runtime.rule(for: "'", state: state), .direct("‘"))
    }

    func testQuoteContextOverridesAlternationAndUpdatesUnknownFallback() {
        var runtime = InputPunctuatorRuntime()
        let state = InputModeState(punctuationMode: .chinese, symbolWidth: .halfWidth)

        XCTAssertEqual(
            runtime.rule(
                for: "\"",
                context: InputPunctuatorContext(state: state, quoteContext: .closing)
            ),
            .direct("”")
        )
        XCTAssertEqual(runtime.rule(for: "\"", state: state), .direct("“"))
        XCTAssertEqual(
            runtime.rule(
                for: "'",
                context: InputPunctuatorContext(state: state, quoteContext: .opening)
            ),
            .direct("‘")
        )
        XCTAssertEqual(runtime.rule(for: "'", state: state), .direct("’"))
    }

    func testChineseHalfWidthEllipsisDashAndAsciiMinus() {
        var runtime = InputPunctuatorRuntime()
        let state = InputModeState(punctuationMode: .chinese, symbolWidth: .halfWidth)

        XCTAssertEqual(runtime.rule(for: "^", state: state), .direct("……"))
        XCTAssertEqual(runtime.rule(for: "_", state: state), .direct("——"))
        XCTAssertEqual(runtime.rule(for: "-", state: state), .direct("-"))
    }

    func testEnglishHalfWidthKeepsAsciiSymbols() {
        var runtime = InputPunctuatorRuntime()
        let state = InputModeState(punctuationMode: .english, symbolWidth: .halfWidth)

        for symbol in [",", ".", "/", "\\", "\"", "'", "^", "_", "-", "{", "}"] {
            XCTAssertEqual(runtime.rule(for: symbol, state: state), .direct(symbol))
        }
    }

    func testFullWidthStateUsesFullWidthTable() {
        var runtime = InputPunctuatorRuntime()
        let state = InputModeState(punctuationMode: .chinese, symbolWidth: .fullWidth)

        XCTAssertEqual(runtime.rule(for: "-", state: state), .direct("－"))
        XCTAssertEqual(runtime.rule(for: "@", state: state), .direct("＠"))
        XCTAssertEqual(runtime.rule(for: ".", state: state), .direct("．"))
    }

    func testChineseCandidateListSymbols() {
        var runtime = InputPunctuatorRuntime()
        let state = InputModeState(punctuationMode: .chinese, symbolWidth: .halfWidth)

        XCTAssertEqual(
            runtime.rule(for: "/", state: state),
            .candidates(
                trigger: "/",
                outputs: [
                    InputSymbolCandidate(text: "、"),
                    InputSymbolCandidate(text: "/"),
                    InputSymbolCandidate(text: "／"),
                    InputSymbolCandidate(text: "÷")
                ]
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
            runtime.rule(
                for: ".",
                context: InputPunctuatorContext(
                    state: state,
                    previousCharacterKind: .asciiDigit
                )
            ),
            .direct(".")
        )
    }

    func testDigitContextDoesNotChangeCommaOrActiveCompositionPeriod() {
        var runtime = InputPunctuatorRuntime()
        let state = InputModeState(punctuationMode: .chinese, symbolWidth: .halfWidth)

        XCTAssertEqual(
            runtime.rule(
                for: ",",
                context: InputPunctuatorContext(
                    state: state,
                    previousCharacterKind: .asciiDigit
                )
            ),
            .direct("，")
        )
        XCTAssertEqual(
            runtime.rule(
                for: ".",
                context: InputPunctuatorContext(
                    state: state,
                    previousCharacterKind: .asciiDigit,
                    hasActiveComposition: true
                )
            ),
            .direct("。")
        )
    }

    func testSecondPeriodAfterRecordedAsciiPeriodReturnsToChinesePunctuation() {
        var runtime = InputPunctuatorRuntime()
        let state = InputModeState(punctuationMode: .chinese, symbolWidth: .halfWidth)

        XCTAssertEqual(
            runtime.rule(
                for: ".",
                context: InputPunctuatorContext(
                    state: state,
                    previousCharacterKind: .asciiDigit
                )
            ),
            .direct(".")
        )
        XCTAssertEqual(
            runtime.rule(
                for: ".",
                context: InputPunctuatorContext(
                    state: state,
                    previousCharacterKind: .text
                )
            ),
            .direct("。")
        )
    }
}
