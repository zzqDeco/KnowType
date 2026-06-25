import XCTest
@testable import KnowTypeCore

final class InputModePreferencesTests: XCTestCase {
    func testUserDefaultsStoreReturnsStandardPreferencesWhenUnset() {
        let suiteName = "KnowTypeInputModePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = UserDefaultsInputModePreferenceStore(defaults: defaults)

        XCTAssertEqual(store.loadPreferences(), .standard)
    }

    func testUserDefaultsStorePersistsTextPunctuationAndWidthPreferences() throws {
        let suiteName = "KnowTypeInputModePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = UserDefaultsInputModePreferenceStore(defaults: defaults)
        let preferences = InputModePreferences(
            defaultState: InputModeState(
                textMode: .chinese,
                punctuationMode: .english,
                symbolWidth: .fullWidth
            ),
            codeAppState: InputModeState(
                textMode: .chinese,
                punctuationMode: .chinese,
                symbolWidth: .fullWidth
            )
        )

        try store.savePreferences(preferences)

        XCTAssertEqual(store.loadPreferences(), preferences)
    }

    func testUserDefaultsStoreIgnoresInvalidRawValues() {
        let suiteName = "KnowTypeInputModePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("invalid", forKey: "input.default.textMode")
        defaults.set("invalid", forKey: "input.default.punctuationMode")
        defaults.set("invalid", forKey: "input.codeApp.textMode")
        defaults.set("invalid", forKey: "input.codeApp.symbolWidth")
        let store = UserDefaultsInputModePreferenceStore(defaults: defaults)

        XCTAssertEqual(store.loadPreferences(), .standard)
    }

    func testPreferenceRuntimeReloadsWhenPreferencesChange() {
        var runtime = InputModePreferenceRuntime(
            preferences: .standard,
            appBundleID: "com.apple.TextEdit"
        )
        let updatedPreferences = InputModePreferences(
            defaultState: InputModeState(
                textMode: .chinese,
                punctuationMode: .english,
                symbolWidth: .fullWidth
            )
        )

        XCTAssertTrue(
            runtime.reloadIfChanged(
                preferences: updatedPreferences,
                appBundleID: "com.apple.TextEdit"
            )
        )
        XCTAssertEqual(runtime.preferences, updatedPreferences)
        XCTAssertEqual(runtime.state, updatedPreferences.defaultState)
    }

    func testPreferenceRuntimeDoesNotClobberManualToggleWhenPreferencesAreUnchanged() {
        var runtime = InputModePreferenceRuntime(
            preferences: .standard,
            appBundleID: "com.apple.TextEdit"
        )
        runtime.togglePunctuationMode()

        XCTAssertFalse(
            runtime.reloadIfChanged(
                preferences: .standard,
                appBundleID: "com.apple.TextEdit"
            )
        )
        XCTAssertEqual(runtime.state.punctuationMode, .english)
    }

    func testPreferenceRuntimeReloadsWhenAppContextChanges() {
        var runtime = InputModePreferenceRuntime(
            preferences: .standard,
            appBundleID: "com.apple.TextEdit"
        )

        XCTAssertTrue(
            runtime.reloadIfChanged(
                preferences: .standard,
                appBundleID: "com.openai.codex"
            )
        )
        XCTAssertEqual(runtime.state, InputModePreferences.standard.codeAppState)
    }
}
