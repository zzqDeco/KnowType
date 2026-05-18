import XCTest
import KnowTypeCore
@testable import KnowTypeSettingsUI

final class RuntimePreferencesViewModelTests: XCTestCase {
    @MainActor
    func testViewModelLoadsStoredPreferences() throws {
        let store = makeStore()
        let preferences = InputMethodRuntimePreferences(
            inputScheme: .xiaohe,
            candidatePageSize: 6,
            candidateLayoutMode: .verticalPreferred,
            cloudContinuationEnabled: false,
            localContinuationEnabledWhenNoProvider: false,
            continuationLengthLevel: .short,
            maxContinuationCandidates: 2
        )
        try store.savePreferences(preferences)

        let viewModel = RuntimePreferencesViewModel(store: store)

        XCTAssertEqual(viewModel.preferences, preferences)
    }

    @MainActor
    func testViewModelPersistsUpdates() {
        let store = makeStore()
        let viewModel = RuntimePreferencesViewModel(store: store)

        viewModel.setInputScheme(.xiaohe)
        viewModel.setCandidatePageSize(6)
        viewModel.setCandidateLayoutMode(.verticalPreferred)
        viewModel.setCloudContinuationEnabled(false)
        viewModel.setLocalContinuationEnabledWhenNoProvider(false)
        viewModel.setContinuationLengthLevel(.long)
        viewModel.setMaxContinuationCandidates(3)

        XCTAssertNil(viewModel.lastErrorMessage)
        XCTAssertEqual(store.loadPreferences(), viewModel.preferences)
        XCTAssertEqual(store.loadPreferences().inputScheme, .xiaohe)
        XCTAssertEqual(store.loadPreferences().candidatePageSize, 6)
        XCTAssertEqual(store.loadPreferences().candidateLayoutMode, .verticalPreferred)
        XCTAssertFalse(store.loadPreferences().cloudContinuationEnabled)
        XCTAssertFalse(store.loadPreferences().localContinuationEnabledWhenNoProvider)
        XCTAssertEqual(store.loadPreferences().continuationLengthLevel, .long)
        XCTAssertEqual(store.loadPreferences().maxContinuationCandidates, 3)
    }

    @MainActor
    func testViewModelResetsToDefaults() {
        let store = makeStore()
        let viewModel = RuntimePreferencesViewModel(store: store)
        viewModel.setInputScheme(.xiaohe)
        viewModel.setCloudContinuationEnabled(false)

        viewModel.resetToDefaults()

        XCTAssertEqual(viewModel.preferences, .standard)
        XCTAssertEqual(store.loadPreferences(), .standard)
    }

    private func makeStore() -> UserDefaultsInputMethodRuntimePreferenceStore {
        let suiteName = "KnowTypeRuntimePreferencesViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsInputMethodRuntimePreferenceStore(defaults: defaults)
    }
}
