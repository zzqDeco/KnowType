import XCTest
import KnowTypeCore
@testable import KnowTypeSettingsApp

final class InputModePreferencesViewModelTests: XCTestCase {
    @MainActor
    func testViewModelLoadsStoredPreferences() throws {
        let store = makeStore()
        let preferences = InputModePreferences(
            defaultState: InputModeState(punctuationMode: .english, symbolWidth: .fullWidth),
            codeAppState: InputModeState(punctuationMode: .chinese, symbolWidth: .fullWidth)
        )
        try store.savePreferences(preferences)

        let viewModel = InputModePreferencesViewModel(store: store)

        XCTAssertEqual(viewModel.preferences, preferences)
    }

    @MainActor
    func testViewModelPersistsUpdates() {
        let store = makeStore()
        let viewModel = InputModePreferencesViewModel(store: store)

        viewModel.setDefaultPunctuationMode(.english)
        viewModel.setDefaultSymbolWidth(.fullWidth)
        viewModel.setCodeAppPunctuationMode(.chinese)
        viewModel.setCodeAppSymbolWidth(.fullWidth)

        XCTAssertNil(viewModel.lastErrorMessage)
        XCTAssertEqual(store.loadPreferences(), viewModel.preferences)
        XCTAssertEqual(store.loadPreferences().defaultState.punctuationMode, .english)
        XCTAssertEqual(store.loadPreferences().defaultState.symbolWidth, .fullWidth)
        XCTAssertEqual(store.loadPreferences().codeAppState.punctuationMode, .chinese)
        XCTAssertEqual(store.loadPreferences().codeAppState.symbolWidth, .fullWidth)
    }

    @MainActor
    func testViewModelResetsToDefaults() {
        let store = makeStore()
        let viewModel = InputModePreferencesViewModel(store: store)
        viewModel.setDefaultPunctuationMode(.english)
        viewModel.setDefaultSymbolWidth(.fullWidth)

        viewModel.resetToDefaults()

        XCTAssertEqual(viewModel.preferences, .standard)
        XCTAssertEqual(store.loadPreferences(), .standard)
    }

    private func makeStore() -> UserDefaultsInputModePreferenceStore {
        let suiteName = "KnowTypeInputModePreferencesViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsInputModePreferenceStore(defaults: defaults)
    }
}
