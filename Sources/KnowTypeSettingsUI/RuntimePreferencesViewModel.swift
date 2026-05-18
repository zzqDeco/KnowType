import Combine
import Foundation
import KnowTypeCore

@MainActor
public final class RuntimePreferencesViewModel: ObservableObject {
    @Published public private(set) var preferences: InputMethodRuntimePreferences
    @Published public private(set) var lastErrorMessage: String?

    private let store: any InputMethodRuntimePreferenceStore

    public init(store: any InputMethodRuntimePreferenceStore = UserDefaultsInputMethodRuntimePreferenceStore.defaultStore()) {
        self.store = store
        self.preferences = store.loadPreferences()
        self.lastErrorMessage = nil
    }

    public func setInputScheme(_ scheme: TraditionalInputEngine.Scheme) {
        update { $0.inputScheme = scheme }
    }

    public func setCandidatePageSize(_ pageSize: Int) {
        update { $0.candidatePageSize = InputMethodRuntimePreferences.clampedCandidatePageSize(pageSize) }
    }

    public func setCandidateLayoutMode(_ mode: CandidatePanelLayoutMode) {
        update { $0.candidateLayoutMode = mode }
    }

    public func setCloudContinuationEnabled(_ isEnabled: Bool) {
        update { $0.cloudContinuationEnabled = isEnabled }
    }

    public func setLocalContinuationEnabledWhenNoProvider(_ isEnabled: Bool) {
        update { $0.localContinuationEnabledWhenNoProvider = isEnabled }
    }

    public func setContinuationLengthLevel(_ level: ContinuationLengthLevel) {
        update { $0.continuationLengthLevel = level }
    }

    public func setMaxContinuationCandidates(_ count: Int) {
        update { $0.maxContinuationCandidates = InputMethodRuntimePreferences.clampedContinuationCandidateCount(count) }
    }

    public func resetToDefaults() {
        preferences = .standard
        save()
    }

    private func update(_ mutate: (inout InputMethodRuntimePreferences) -> Void) {
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
