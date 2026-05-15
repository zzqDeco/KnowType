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

    func testUserDefaultsStorePersistsPunctuationAndWidthPreferences() throws {
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
        defaults.set("invalid", forKey: "input.default.punctuationMode")
        defaults.set("invalid", forKey: "input.codeApp.symbolWidth")
        let store = UserDefaultsInputModePreferenceStore(defaults: defaults)

        XCTAssertEqual(store.loadPreferences(), .standard)
    }
}
