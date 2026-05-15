import Foundation
import KnowTypeCore

@MainActor
public final class InputModePreferencesViewModel: ObservableObject {
    @Published public private(set) var preferences: InputModePreferences
    @Published public private(set) var lastErrorMessage: String?

    private let store: any InputModePreferenceStore

    public init(store: any InputModePreferenceStore = UserDefaultsInputModePreferenceStore.defaultStore()) {
        self.store = store
        self.preferences = store.loadPreferences()
        self.lastErrorMessage = nil
    }

    public func setDefaultPunctuationMode(_ mode: InputSymbolMode) {
        update { $0.defaultState.punctuationMode = mode }
    }

    public func setDefaultSymbolWidth(_ width: InputSymbolWidth) {
        update { $0.defaultState.symbolWidth = width }
    }

    public func setCodeAppPunctuationMode(_ mode: InputSymbolMode) {
        update { $0.codeAppState.punctuationMode = mode }
    }

    public func setCodeAppSymbolWidth(_ width: InputSymbolWidth) {
        update { $0.codeAppState.symbolWidth = width }
    }

    public func resetToDefaults() {
        preferences = .standard
        save()
    }

    private func update(_ mutate: (inout InputModePreferences) -> Void) {
        var updated = preferences
        mutate(&updated)
        preferences = updated
        save()
    }

    private func save() {
        do {
            try store.savePreferences(preferences)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
