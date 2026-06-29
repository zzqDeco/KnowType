import XCTest
import KnowTypeCore
@testable import KnowTypeInputMethod

final class InputClientCompatibilityPolicyTests: XCTestCase {
    func testUnknownClientUsesInlineCompositionByDefault() {
        let policy = InputClientCompatibilityPolicy(userDefaults: nil)

        XCTAssertEqual(
            policy.writeMode(
                bundleIdentifier: "com.apple.TextEdit",
                inputModeState: .init(),
                hasActiveComposition: false,
                hasClient: true
            ),
            .inlineComposition
        )
    }

    func testBrowserClientUsesInlineCompositionByDefault() {
        let policy = InputClientCompatibilityPolicy(userDefaults: nil)

        XCTAssertEqual(
            policy.writeMode(
                bundleIdentifier: "com.google.Chrome",
                inputModeState: .init(),
                hasActiveComposition: false,
                hasClient: true
            ),
            .inlineComposition
        )
    }

    func testCodeClientUsesAsciiPassthroughWhenIdleInAsciiMode() {
        let policy = InputClientCompatibilityPolicy(userDefaults: nil)

        XCTAssertEqual(
            policy.writeMode(
                bundleIdentifier: "com.openai.codex",
                inputModeState: InputModeState(textMode: .ascii),
                hasActiveComposition: false,
                hasClient: true
            ),
            .asciiPassthrough
        )
    }

    func testTerminalCompatibilityClientsUseAsciiPassthroughByDefault() {
        let policy = InputClientCompatibilityPolicy(userDefaults: nil)
        let state = InputModeAppPolicy.defaultState(appBundleID: "com.apple.Terminal")

        XCTAssertEqual(state.textMode, .ascii)
        XCTAssertEqual(
            policy.writeMode(
                bundleIdentifier: "com.apple.Terminal",
                inputModeState: state,
                hasActiveComposition: false,
                hasClient: true
            ),
            .asciiPassthrough
        )
    }

    func testTerminalPlaceholderProfileUsesIdlePassthroughFromInputModeByDefault() {
        let policy = InputClientCompatibilityPolicy(userDefaults: nil)
        let state = InputModeAppPolicy.defaultState(appBundleID: "org.vim.MacVim")

        XCTAssertEqual(state.textMode, .ascii)
        XCTAssertEqual(
            HostCompatibilityProfile.profile(bundleIdentifier: "org.vim.MacVim"),
            .terminalPlaceholder
        )
        XCTAssertEqual(
            policy.writeMode(
                bundleIdentifier: "org.vim.MacVim",
                inputModeState: state,
                hasActiveComposition: false,
                hasClient: true
            ),
            .asciiPassthrough
        )
        XCTAssertEqual(
            policy.writeMode(
                bundleIdentifier: "org.vim.MacVim",
                inputModeState: state,
                hasActiveComposition: true,
                hasClient: true
            ),
            .commitOnlyComposition
        )
        XCTAssertEqual(
            policy.writeMode(
                bundleIdentifier: "org.vim.MacVim",
                inputModeState: InputModeState(textMode: .chinese),
                hasActiveComposition: false,
                hasClient: true
            ),
            .commitOnlyComposition
        )
    }

    func testEditorCompatibilityClientsUseInlineByDefault() {
        let policy = InputClientCompatibilityPolicy(userDefaults: nil)
        let state = InputModeAppPolicy.defaultState(appBundleID: "com.jetbrains.intellij")

        XCTAssertEqual(state.textMode, .chinese)
        XCTAssertEqual(
            policy.writeMode(
                bundleIdentifier: "com.jetbrains.intellij",
                inputModeState: state,
                hasActiveComposition: false,
                hasClient: true
            ),
            .inlineComposition
        )
    }

    func testCodeClientUsesInlineForChineseOrActiveCompositionByDefault() {
        let policy = InputClientCompatibilityPolicy(userDefaults: nil)

        XCTAssertEqual(
            policy.writeMode(
                bundleIdentifier: "com.openai.codex",
                inputModeState: InputModeState(textMode: .chinese),
                hasActiveComposition: false,
                hasClient: true
            ),
            .inlineComposition
        )
        XCTAssertEqual(
            policy.writeMode(
                bundleIdentifier: "com.openai.codex",
                inputModeState: InputModeState(textMode: .ascii),
                hasActiveComposition: true,
                hasClient: true
            ),
            .inlineComposition
        )
    }

    func testOverrideWriteModeWinsForSpecificBundle() throws {
        let suiteName = "KnowTypeInputClientCompatibilityPolicyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(
            InputClientWriteMode.commitOnlyComposition.rawValue,
            forKey: "input.client.com.openai.codex.writeMode"
        )
        let policy = InputClientCompatibilityPolicy(userDefaults: defaults)

        XCTAssertEqual(
            policy.writeMode(
                bundleIdentifier: "com.openai.codex",
                inputModeState: InputModeState(textMode: .ascii),
                hasActiveComposition: false,
                hasClient: true
            ),
            .commitOnlyComposition
        )
    }

    func testMissingClientDisablesInputMethodWrites() {
        let policy = InputClientCompatibilityPolicy(userDefaults: nil)

        XCTAssertEqual(
            policy.writeMode(
                bundleIdentifier: nil,
                inputModeState: .init(),
                hasActiveComposition: false,
                hasClient: false
            ),
            .disabled
        )
    }
}
