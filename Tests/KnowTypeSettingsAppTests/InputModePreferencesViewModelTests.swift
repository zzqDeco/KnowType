import XCTest
import KnowTypeCore
@testable import KnowTypeSettingsUI

final class InputModePreferencesViewModelTests: XCTestCase {
    @MainActor
    func testViewModelLoadsStoredPreferences() throws {
        let store = makeStore()
        var preferences = InputModePreferences.standard
        preferences.globalSymbolWidth = .fullWidth
        try store.savePreferences(preferences)

        let viewModel = InputModePreferencesViewModel(store: store)

        XCTAssertEqual(viewModel.preferences.globalSymbolWidth, .fullWidth)
    }

    @MainActor
    func testViewModelPersistsUpdates() {
        let store = makeStore()
        let viewModel = InputModePreferencesViewModel(store: store)

        viewModel.setGlobalSymbolWidth(.fullWidth)

        XCTAssertNil(viewModel.lastErrorMessage)
        XCTAssertEqual(store.loadPreferences().globalSymbolWidth, .fullWidth)
        XCTAssertEqual(viewModel.preferences.globalSymbolWidth, .fullWidth)
    }

    @MainActor
    func testViewModelResetsToDefaults() {
        let store = makeStore()
        let viewModel = InputModePreferencesViewModel(store: store)
        viewModel.setGlobalSymbolWidth(.fullWidth)

        viewModel.resetToDefaults()

        XCTAssertEqual(viewModel.preferences, .standard)
        XCTAssertEqual(viewModel.preferences.defaultState.punctuationMode, .chinese)
        XCTAssertEqual(viewModel.preferences.defaultState.symbolWidth, .halfWidth)
        XCTAssertEqual(viewModel.preferences.codeAppState.textMode, .ascii)
        XCTAssertEqual(viewModel.preferences.codeAppState.punctuationMode, .english)
        XCTAssertEqual(viewModel.preferences.codeAppState.symbolWidth, .halfWidth)
        XCTAssertEqual(store.loadPreferences(), .standard)
    }

    private func makeStore() -> UserDefaultsInputModePreferenceStore {
        let suiteName = "KnowTypeInputModePreferencesViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsInputModePreferenceStore(defaults: defaults)
    }
}
