import XCTest
@testable import KnowTypeCore

final class InputModePreferencesTests: XCTestCase {
    func testStandardPreferencesKeepLegacyShapesAndExposeGlobalWidth() {
        XCTAssertEqual(InputModePreferences.standard.defaultState.punctuationMode, .chinese)
        XCTAssertEqual(InputModePreferences.standard.defaultState.symbolWidth, .halfWidth)
        XCTAssertEqual(InputModePreferences.standard.codeAppState.textMode, .ascii)
        XCTAssertEqual(InputModePreferences.standard.codeAppState.punctuationMode, .english)
        XCTAssertEqual(InputModePreferences.standard.codeAppState.symbolWidth, .halfWidth)
        XCTAssertEqual(InputModePreferences.standard.globalSymbolWidth, .halfWidth)
    }

    func testUserDefaultsStoreReturnsStandardPreferencesWhenUnset() {
        let suiteName = "KnowTypeInputModePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = UserDefaultsInputModePreferenceStore(defaults: defaults)

        XCTAssertEqual(store.loadPreferences(), .standard)
    }

    func testUserDefaultsStorePersistsOnlyGlobalSymbolWidth() throws {
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

        XCTAssertEqual(defaults.string(forKey: "input.global.symbolWidth"), "fullWidth")
        XCTAssertEqual(store.loadPreferences().globalSymbolWidth, .fullWidth)
        XCTAssertNil(defaults.string(forKey: "input.default.punctuationMode"))
        XCTAssertNil(defaults.string(forKey: "input.codeApp.punctuationMode"))
    }

    func testUserDefaultsStoreMigratesLegacyDefaultWidth() {
        let suiteName = "KnowTypeInputModePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("fullWidth", forKey: "input.default.symbolWidth")
        defaults.set("halfWidth", forKey: "input.codeApp.symbolWidth")
        let store = UserDefaultsInputModePreferenceStore(defaults: defaults)

        XCTAssertEqual(store.loadPreferences().globalSymbolWidth, .fullWidth)
    }

    func testGlobalWidthTakesPrecedenceAndLegacyKeysRemainReadOnly() throws {
        let suiteName = "KnowTypeInputModePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("fullWidth", forKey: "input.global.symbolWidth")
        defaults.set("halfWidth", forKey: "input.default.symbolWidth")
        defaults.set("english", forKey: "input.default.punctuationMode")
        defaults.set("chinese", forKey: "input.codeApp.textMode")
        let store = UserDefaultsInputModePreferenceStore(defaults: defaults)

        var preferences = store.loadPreferences()
        XCTAssertEqual(preferences.globalSymbolWidth, .fullWidth)
        XCTAssertEqual(preferences.defaultState.punctuationMode, .english)
        XCTAssertEqual(preferences.codeAppState.textMode, .chinese)

        preferences.globalSymbolWidth = .halfWidth
        try store.savePreferences(preferences)

        XCTAssertEqual(defaults.string(forKey: "input.global.symbolWidth"), "halfWidth")
        XCTAssertEqual(defaults.string(forKey: "input.default.symbolWidth"), "halfWidth")
        XCTAssertEqual(defaults.string(forKey: "input.default.punctuationMode"), "english")
        XCTAssertEqual(defaults.string(forKey: "input.codeApp.textMode"), "chinese")
    }

    func testGlobalWidthMutatorKeepsLegacyShapesAlignedForCallers() {
        var preferences = InputModePreferences(
            defaultState: InputModeState(symbolWidth: .halfWidth),
            codeAppState: InputModeState(symbolWidth: .halfWidth)
        )

        preferences.globalSymbolWidth = .fullWidth

        XCTAssertEqual(preferences.defaultState.symbolWidth, .fullWidth)
        XCTAssertEqual(preferences.codeAppState.symbolWidth, .fullWidth)
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
}
