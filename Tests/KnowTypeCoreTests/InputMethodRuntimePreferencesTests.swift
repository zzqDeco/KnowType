import XCTest
@testable import KnowTypeCore

final class InputMethodRuntimePreferencesTests: XCTestCase {
    func testDefaultPreferencesUseAdaptiveSixCandidatePage() {
        let preferences = InputMethodRuntimePreferences.standard

        XCTAssertEqual(preferences.candidateLayoutMode, .adaptive)
        XCTAssertEqual(preferences.candidatePageSize, 6)
        XCTAssertEqual(preferences.effectiveCandidatePageSize, 6)
    }

    func testAdaptiveEffectivePageSizeCapsSavedNineAtSix() {
        let preferences = InputMethodRuntimePreferences(
            candidatePageSize: 9,
            candidateLayoutMode: .adaptive
        )

        XCTAssertEqual(preferences.candidatePageSize, 9)
        XCTAssertEqual(preferences.effectiveCandidatePageSize, 6)
    }

    func testVerticalEffectivePageSizeUsesSavedPageSize() {
        let preferences = InputMethodRuntimePreferences(
            candidatePageSize: 9,
            candidateLayoutMode: .verticalPreferred
        )

        XCTAssertEqual(preferences.effectiveCandidatePageSize, 9)
    }

    func testUserDefaultsStorePersistsRuntimePreferences() throws {
        let store = makeStore()
        let preferences = InputMethodRuntimePreferences(
            inputScheme: .xiaohe,
            candidatePageSize: 6,
            candidateLayoutMode: .verticalPreferred,
            cloudContinuationEnabled: false,
            localContinuationEnabledWhenNoProvider: false,
            continuationLengthLevel: .long,
            maxContinuationCandidates: 3
        )

        try store.savePreferences(preferences)

        XCTAssertEqual(store.loadPreferences(), preferences)
    }

    func testPreferencesClampOutOfRangeValues() {
        let preferences = InputMethodRuntimePreferences(
            candidatePageSize: 99,
            maxContinuationCandidates: 99
        )

        XCTAssertEqual(preferences.candidatePageSize, 9)
        XCTAssertEqual(preferences.maxContinuationCandidates, 6)
    }

    func testStoreFallsBackForInvalidRawValues() {
        let suiteName = "KnowTypeInputMethodRuntimePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("unknown", forKey: "runtime.input.scheme")
        defaults.set("unknown", forKey: "runtime.candidates.layoutMode")
        defaults.set("unknown", forKey: "runtime.ai.continuationLengthLevel")
        let store = UserDefaultsInputMethodRuntimePreferenceStore(defaults: defaults)

        XCTAssertEqual(store.loadPreferences(), .standard)
    }

    private func makeStore() -> UserDefaultsInputMethodRuntimePreferenceStore {
        let suiteName = "KnowTypeInputMethodRuntimePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsInputMethodRuntimePreferenceStore(defaults: defaults)
    }
}
