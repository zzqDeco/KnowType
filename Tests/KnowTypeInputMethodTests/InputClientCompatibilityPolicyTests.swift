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

    func testAsciiModeUsesPassthroughForAnyInlineHostWhenIdle() {
        let policy = InputClientCompatibilityPolicy(userDefaults: nil)

        XCTAssertEqual(
            policy.writeMode(
                bundleIdentifier: "com.example.GenericInlineHost",
                inputModeState: InputModeState(textMode: .ascii),
                hasActiveComposition: false,
                hasClient: true
            ),
            .asciiPassthrough
        )
    }

    func testTerminalCompatibilityClientUsesAsciiPassthroughWhenGlobalModeIsAscii() {
        let policy = InputClientCompatibilityPolicy(userDefaults: nil)
        let state = InputModeState(textMode: .ascii, punctuationMode: .english)

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

    func testTerminalPlaceholderProfileUsesIdlePassthroughFromGlobalInputMode() {
        let policy = InputClientCompatibilityPolicy(userDefaults: nil)
        let state = InputModeState(textMode: .ascii, punctuationMode: .english)

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

    func testEditorCompatibilityClientUsesInlineInGlobalChineseMode() {
        let policy = InputClientCompatibilityPolicy(userDefaults: nil)
        let state = InputModeState(textMode: .chinese, punctuationMode: .chinese)

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

    func testInlineHostUsesInlineForChineseOrActiveCompositionByDefault() {
        let policy = InputClientCompatibilityPolicy(userDefaults: nil)

        XCTAssertEqual(
            policy.writeMode(
                bundleIdentifier: "com.example.GenericInlineHost",
                inputModeState: InputModeState(textMode: .chinese),
                hasActiveComposition: false,
                hasClient: true
            ),
            .inlineComposition
        )
        XCTAssertEqual(
            policy.writeMode(
                bundleIdentifier: "com.example.GenericInlineHost",
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
            forKey: "input.client.com.example.OverrideHost.writeMode"
        )
        let policy = InputClientCompatibilityPolicy(userDefaults: defaults)

        XCTAssertEqual(
            policy.writeMode(
                bundleIdentifier: "com.example.OverrideHost",
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
