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

    func testCommonCompatibilityClientsUseCodeAppDefaultAsciiPassthrough() {
        let policy = InputClientCompatibilityPolicy(userDefaults: nil)
        let state = InputModeAppPolicy.defaultState(appBundleID: "com.jetbrains.intellij")

        XCTAssertEqual(state.textMode, .ascii)
        XCTAssertEqual(
            policy.writeMode(
                bundleIdentifier: "com.jetbrains.intellij",
                inputModeState: state,
                hasActiveComposition: false,
                hasClient: true
            ),
            .asciiPassthrough
        )
    }

    func testCodeClientUsesCommitOnlyForChineseOrActiveComposition() {
        let policy = InputClientCompatibilityPolicy(userDefaults: nil)

        XCTAssertEqual(
            policy.writeMode(
                bundleIdentifier: "com.openai.codex",
                inputModeState: InputModeState(textMode: .chinese),
                hasActiveComposition: false,
                hasClient: true
            ),
            .commitOnlyComposition
        )
        XCTAssertEqual(
            policy.writeMode(
                bundleIdentifier: "com.openai.codex",
                inputModeState: InputModeState(textMode: .ascii),
                hasActiveComposition: true,
                hasClient: true
            ),
            .commitOnlyComposition
        )
    }

    func testOverrideWriteModeWinsForSpecificBundle() throws {
        let suiteName = "KnowTypeInputClientCompatibilityPolicyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(
            InputClientWriteMode.inlineComposition.rawValue,
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
            .inlineComposition
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
