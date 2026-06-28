import XCTest
import KnowTypeCore
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

    func testAppPolicyDefaultsTerminalsToAsciiAndEditorsToChineseText() {
        XCTAssertEqual(
            InputModeAppPolicy.defaultState(appBundleID: "com.apple.Terminal"),
            InputModeState(
                textMode: .ascii,
                punctuationMode: .chinese,
                symbolWidth: .halfWidth
            )
        )
        XCTAssertEqual(
            InputModeAppPolicy.defaultState(appBundleID: "com.googlecode.iterm2"),
            InputModeState(
                textMode: .ascii,
                punctuationMode: .chinese,
                symbolWidth: .halfWidth
            )
        )
        XCTAssertEqual(
            InputModeAppPolicy.defaultState(appBundleID: "org.vim.MacVim"),
            InputModeState(
                textMode: .ascii,
                punctuationMode: .chinese,
                symbolWidth: .halfWidth
            )
        )
        XCTAssertEqual(
            InputModeAppPolicy.defaultState(appBundleID: "com.apple.dt.Xcode"),
            InputModeState(
                textMode: .chinese,
                punctuationMode: .chinese,
                symbolWidth: .halfWidth
            )
        )
        XCTAssertEqual(
            InputModeAppPolicy.defaultState(appBundleID: "com.openai.codex"),
            InputModeState(
                textMode: .chinese,
                punctuationMode: .chinese,
                symbolWidth: .halfWidth
            )
        )
        XCTAssertEqual(
            InputModeAppPolicy.defaultState(appBundleID: "com.jetbrains.intellij"),
            InputModeState(
                textMode: .chinese,
                punctuationMode: .chinese,
                symbolWidth: .halfWidth
            )
        )
        XCTAssertEqual(
            InputModeAppPolicy.defaultState(appBundleID: "com.todesktop.app.example"),
            InputModeState(
                textMode: .chinese,
                punctuationMode: .chinese,
                symbolWidth: .halfWidth
            )
        )
        XCTAssertEqual(
            InputModeAppPolicy.defaultState(appBundleID: "com.apple.TextEdit"),
            InputModeState()
        )
    }

    func testAppPolicyUsesStoredPreferencesForDefaultAndCodeContexts() {
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

        XCTAssertEqual(
            InputModeAppPolicy.defaultState(appBundleID: "com.apple.TextEdit", preferences: preferences),
            preferences.defaultState
        )
        XCTAssertEqual(
            InputModeAppPolicy.defaultState(appBundleID: "com.apple.Terminal", preferences: preferences),
            preferences.codeAppState
        )
        XCTAssertEqual(
            InputModeAppPolicy.defaultState(appBundleID: "com.openai.codex", preferences: preferences),
            InputModeState(
                textMode: .chinese,
                punctuationMode: .chinese,
                symbolWidth: .halfWidth
            )
        )
        XCTAssertEqual(
            InputModeAppPolicy.defaultState(appBundleID: "com.jetbrains.intellij", preferences: preferences),
            InputModeState(
                textMode: .chinese,
                punctuationMode: .chinese,
                symbolWidth: .halfWidth
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
