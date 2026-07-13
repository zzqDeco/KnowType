import Foundation

public enum InputTextMode: String, Codable, Sendable, Equatable, CaseIterable {
    case chinese
    case ascii

    public mutating func toggle() {
        self = toggled
    }

    public var toggled: InputTextMode {
        switch self {
        case .chinese:
            return .ascii
        case .ascii:
            return .chinese
        }
    }
}

public enum InputSymbolMode: String, Codable, Sendable, Equatable, CaseIterable {
    case chinese
    case english

    public mutating func toggle() {
        self = toggled
    }

    public var toggled: InputSymbolMode {
        switch self {
        case .chinese:
            return .english
        case .english:
            return .chinese
        }
    }
}

public enum InputSymbolWidth: String, Codable, Sendable, Equatable, CaseIterable {
    case halfWidth
    case fullWidth

    public mutating func toggle() {
        self = toggled
    }

    public var toggled: InputSymbolWidth {
        switch self {
        case .halfWidth:
            return .fullWidth
        case .fullWidth:
            return .halfWidth
        }
    }
}

public struct InputModeState: Codable, Sendable, Equatable {
    public var textMode: InputTextMode
    public var punctuationMode: InputSymbolMode
    public var symbolWidth: InputSymbolWidth

    public init(
        textMode: InputTextMode = .chinese,
        punctuationMode: InputSymbolMode = .chinese,
        symbolWidth: InputSymbolWidth = .halfWidth
    ) {
        self.textMode = textMode
        self.punctuationMode = punctuationMode
        self.symbolWidth = symbolWidth
    }

    public mutating func togglePunctuationMode() {
        punctuationMode.toggle()
    }

    public mutating func toggleTextMode() {
        textMode.toggle()
    }

    public mutating func toggleSymbolWidth() {
        symbolWidth.toggle()
    }
}

public struct InputModePreferences: Codable, Sendable, Equatable {
    public var defaultState: InputModeState
    public var codeAppState: InputModeState

    public init(
        defaultState: InputModeState = InputModeState(),
        codeAppState: InputModeState = InputModeState(
            textMode: .ascii,
            punctuationMode: .english,
            symbolWidth: .halfWidth
        )
    ) {
        self.defaultState = defaultState
        self.codeAppState = codeAppState
    }

    public var globalSymbolWidth: InputSymbolWidth {
        get { defaultState.symbolWidth }
        set {
            defaultState.symbolWidth = newValue
            codeAppState.symbolWidth = newValue
        }
    }

    public static let standard = InputModePreferences()
}

public protocol InputModePreferenceStore: Sendable {
    func loadPreferences() -> InputModePreferences
    func savePreferences(_ preferences: InputModePreferences) throws
}

public struct UserDefaultsInputModePreferenceStore: InputModePreferenceStore, @unchecked Sendable {
    public static let defaultSuiteName = "com.knowtype.preferences"

    private enum Key {
        static let globalSymbolWidth = "input.global.symbolWidth"
        static let defaultTextMode = "input.default.textMode"
        static let defaultPunctuationMode = "input.default.punctuationMode"
        static let defaultSymbolWidth = "input.default.symbolWidth"
        static let codeAppTextMode = "input.codeApp.textMode"
        static let codeAppPunctuationMode = "input.codeApp.punctuationMode"
        static let codeAppSymbolWidth = "input.codeApp.symbolWidth"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public static func defaultStore() -> UserDefaultsInputModePreferenceStore {
        UserDefaultsInputModePreferenceStore(
            defaults: UserDefaults(suiteName: defaultSuiteName) ?? .standard
        )
    }

    public func loadPreferences() -> InputModePreferences {
        let standard = InputModePreferences.standard
        let globalSymbolWidth = symbolWidth(forKey: Key.globalSymbolWidth)
            ?? symbolWidth(forKey: Key.defaultSymbolWidth)
            ?? standard.globalSymbolWidth
        return InputModePreferences(
            defaultState: InputModeState(
                textMode: textMode(forKey: Key.defaultTextMode) ?? standard.defaultState.textMode,
                punctuationMode: symbolMode(forKey: Key.defaultPunctuationMode) ?? standard.defaultState.punctuationMode,
                symbolWidth: globalSymbolWidth
            ),
            codeAppState: InputModeState(
                textMode: textMode(forKey: Key.codeAppTextMode) ?? standard.codeAppState.textMode,
                punctuationMode: symbolMode(forKey: Key.codeAppPunctuationMode) ?? standard.codeAppState.punctuationMode,
                symbolWidth: symbolWidth(forKey: Key.codeAppSymbolWidth) ?? standard.codeAppState.symbolWidth
            )
        )
    }

    public func savePreferences(_ preferences: InputModePreferences) throws {
        defaults.set(preferences.globalSymbolWidth.rawValue, forKey: Key.globalSymbolWidth)
    }

    private func textMode(forKey key: String) -> InputTextMode? {
        defaults.string(forKey: key).flatMap(InputTextMode.init(rawValue:))
    }

    private func symbolMode(forKey key: String) -> InputSymbolMode? {
        defaults.string(forKey: key).flatMap(InputSymbolMode.init(rawValue:))
    }

    private func symbolWidth(forKey key: String) -> InputSymbolWidth? {
        defaults.string(forKey: key).flatMap(InputSymbolWidth.init(rawValue:))
    }
}
