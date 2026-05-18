import Foundation

public enum CandidatePanelLayoutMode: String, Codable, Sendable, Equatable, CaseIterable {
    case adaptive
    case verticalPreferred
}

public struct InputMethodRuntimePreferences: Codable, Sendable, Equatable {
    public static let adaptiveCandidatePageSize = 6
    public static let maximumCandidatePageSize = 9

    public var inputScheme: TraditionalInputEngine.Scheme
    public var candidatePageSize: Int
    public var candidateLayoutMode: CandidatePanelLayoutMode
    public var cloudContinuationEnabled: Bool
    public var localContinuationEnabledWhenNoProvider: Bool
    public var continuationLengthLevel: ContinuationLengthLevel
    public var maxContinuationCandidates: Int

    public init(
        inputScheme: TraditionalInputEngine.Scheme = .fullPinyin,
        candidatePageSize: Int = InputMethodRuntimePreferences.adaptiveCandidatePageSize,
        candidateLayoutMode: CandidatePanelLayoutMode = .adaptive,
        cloudContinuationEnabled: Bool = true,
        localContinuationEnabledWhenNoProvider: Bool = true,
        continuationLengthLevel: ContinuationLengthLevel = .medium,
        maxContinuationCandidates: Int = 6
    ) {
        self.inputScheme = inputScheme
        self.candidatePageSize = Self.clampedCandidatePageSize(candidatePageSize)
        self.candidateLayoutMode = candidateLayoutMode
        self.cloudContinuationEnabled = cloudContinuationEnabled
        self.localContinuationEnabledWhenNoProvider = localContinuationEnabledWhenNoProvider
        self.continuationLengthLevel = continuationLengthLevel
        self.maxContinuationCandidates = Self.clampedContinuationCandidateCount(maxContinuationCandidates)
    }

    public static let standard = InputMethodRuntimePreferences()

    public var effectiveCandidatePageSize: Int {
        switch candidateLayoutMode {
        case .adaptive:
            return min(candidatePageSize, Self.adaptiveCandidatePageSize)
        case .verticalPreferred:
            return candidatePageSize
        }
    }

    public static func clampedCandidatePageSize(_ value: Int) -> Int {
        min(max(value, 1), maximumCandidatePageSize)
    }

    public static func clampedContinuationCandidateCount(_ value: Int) -> Int {
        min(max(value, 1), 6)
    }
}

public protocol InputMethodRuntimePreferenceStore: Sendable {
    func loadPreferences() -> InputMethodRuntimePreferences
    func savePreferences(_ preferences: InputMethodRuntimePreferences) throws
}

public struct UserDefaultsInputMethodRuntimePreferenceStore: InputMethodRuntimePreferenceStore, @unchecked Sendable {
    private enum Key {
        static let inputScheme = "runtime.input.scheme"
        static let candidatePageSize = "runtime.candidates.pageSize"
        static let candidateLayoutMode = "runtime.candidates.layoutMode"
        static let cloudContinuationEnabled = "runtime.ai.cloudContinuationEnabled"
        static let localContinuationEnabledWhenNoProvider = "runtime.ai.localContinuationEnabledWhenNoProvider"
        static let continuationLengthLevel = "runtime.ai.continuationLengthLevel"
        static let maxContinuationCandidates = "runtime.ai.maxContinuationCandidates"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public static func defaultStore() -> UserDefaultsInputMethodRuntimePreferenceStore {
        UserDefaultsInputMethodRuntimePreferenceStore(
            defaults: UserDefaults(suiteName: UserDefaultsInputModePreferenceStore.defaultSuiteName) ?? .standard
        )
    }

    public func loadPreferences() -> InputMethodRuntimePreferences {
        let standard = InputMethodRuntimePreferences.standard
        return InputMethodRuntimePreferences(
            inputScheme: stringValue(forKey: Key.inputScheme).flatMap(TraditionalInputEngine.Scheme.init(rawValue:)) ?? standard.inputScheme,
            candidatePageSize: intValue(forKey: Key.candidatePageSize) ?? standard.candidatePageSize,
            candidateLayoutMode: stringValue(forKey: Key.candidateLayoutMode).flatMap(CandidatePanelLayoutMode.init(rawValue:)) ?? standard.candidateLayoutMode,
            cloudContinuationEnabled: boolValue(forKey: Key.cloudContinuationEnabled) ?? standard.cloudContinuationEnabled,
            localContinuationEnabledWhenNoProvider: boolValue(forKey: Key.localContinuationEnabledWhenNoProvider) ?? standard.localContinuationEnabledWhenNoProvider,
            continuationLengthLevel: stringValue(forKey: Key.continuationLengthLevel).flatMap(ContinuationLengthLevel.init(rawValue:)) ?? standard.continuationLengthLevel,
            maxContinuationCandidates: intValue(forKey: Key.maxContinuationCandidates) ?? standard.maxContinuationCandidates
        )
    }

    public func savePreferences(_ preferences: InputMethodRuntimePreferences) throws {
        defaults.set(preferences.inputScheme.rawValue, forKey: Key.inputScheme)
        defaults.set(preferences.candidatePageSize, forKey: Key.candidatePageSize)
        defaults.set(preferences.candidateLayoutMode.rawValue, forKey: Key.candidateLayoutMode)
        defaults.set(preferences.cloudContinuationEnabled, forKey: Key.cloudContinuationEnabled)
        defaults.set(preferences.localContinuationEnabledWhenNoProvider, forKey: Key.localContinuationEnabledWhenNoProvider)
        defaults.set(preferences.continuationLengthLevel.rawValue, forKey: Key.continuationLengthLevel)
        defaults.set(preferences.maxContinuationCandidates, forKey: Key.maxContinuationCandidates)
    }

    private func stringValue(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    private func intValue(forKey key: String) -> Int? {
        guard defaults.object(forKey: key) != nil else {
            return nil
        }
        return defaults.integer(forKey: key)
    }

    private func boolValue(forKey key: String) -> Bool? {
        guard defaults.object(forKey: key) != nil else {
            return nil
        }
        return defaults.bool(forKey: key)
    }
}
