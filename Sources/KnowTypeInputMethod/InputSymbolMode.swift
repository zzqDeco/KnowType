import Foundation

public enum InputTextMode: String, Sendable, Equatable {
    case chinese
    case ascii
}

public enum InputSymbolMode: String, Sendable, Equatable {
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

public enum InputSymbolWidth: String, Sendable, Equatable {
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

public struct InputModeState: Sendable, Equatable {
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

    public mutating func toggleSymbolWidth() {
        symbolWidth.toggle()
    }
}

public enum InputModeAppPolicy {
    public static func defaultState(appBundleID: String?) -> InputModeState {
        guard let appBundleID else {
            return InputModeState()
        }
        if englishPunctuationBundleIDs.contains(appBundleID)
            || englishPunctuationBundleIDPrefixes.contains(where: { appBundleID.hasPrefix($0) }) {
            return InputModeState(
                textMode: .chinese,
                punctuationMode: .english,
                symbolWidth: .halfWidth
            )
        }
        return InputModeState()
    }

    private static let englishPunctuationBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.apple.dt.Xcode",
        "com.microsoft.VSCode",
        "com.openai.codex"
    ]

    private static let englishPunctuationBundleIDPrefixes = [
        "com.googlecode.iterm2"
    ]
}

public struct InputSymbolTransformer: Sendable {
    public init() {}

    public func text(for input: String, mode: InputSymbolMode) -> String? {
        text(
            for: input,
            state: InputModeState(punctuationMode: mode)
        )
    }

    public func text(for input: String, state: InputModeState) -> String? {
        guard Self.isSymbolInput(input) else {
            return nil
        }

        switch state.punctuationMode {
        case .chinese:
            if let symbol = Self.chineseSymbolMap[input], symbol != input {
                return symbol
            }
            return symbolWithWidth(for: input, width: state.symbolWidth)
        case .english:
            return symbolWithWidth(for: input, width: state.symbolWidth)
        }
    }

    public static func isSymbolInput(_ input: String) -> Bool {
        guard input.count == 1 else {
            return false
        }
        return asciiSymbolInputs.contains(input)
    }

    private static let asciiSymbolInputs: Set<String> = Set(chineseSymbolMap.keys)

    private func symbolWithWidth(for input: String, width: InputSymbolWidth) -> String {
        switch width {
        case .halfWidth:
            return input
        case .fullWidth:
            return Self.fullWidthSymbolMap[input] ?? input
        }
    }

    private static let chineseSymbolMap: [String: String] = [
        ",": "，",
        ".": "。",
        "?": "？",
        "!": "！",
        ":": "：",
        ";": "；",
        "(": "（",
        ")": "）",
        "[": "【",
        "]": "】",
        "{": "「",
        "}": "」",
        "<": "《",
        ">": "》",
        "\"": "”",
        "'": "’",
        "/": "、",
        "\\": "、",
        "-": "－",
        "_": "——",
        "~": "～",
        "`": "·",
        "@": "@",
        "#": "#",
        "$": "$",
        "%": "%",
        "^": "^",
        "&": "&",
        "*": "*",
        "+": "+",
        "=": "=",
        "|": "|"
    ]

    private static let fullWidthSymbolMap: [String: String] = [
        ",": "，",
        ".": "．",
        "?": "？",
        "!": "！",
        ":": "：",
        ";": "；",
        "(": "（",
        ")": "）",
        "[": "［",
        "]": "］",
        "{": "｛",
        "}": "｝",
        "<": "＜",
        ">": "＞",
        "\"": "＂",
        "'": "＇",
        "/": "／",
        "\\": "＼",
        "-": "－",
        "_": "＿",
        "~": "～",
        "`": "｀",
        "@": "＠",
        "#": "＃",
        "$": "＄",
        "%": "％",
        "^": "＾",
        "&": "＆",
        "*": "＊",
        "+": "＋",
        "=": "＝",
        "|": "｜"
    ]
}

public enum InputSymbolCommitPolicy {
    public static func result(
        symbol: String,
        rawInput: String,
        baseCommitResult: InputCommitResult
    ) -> InputCommitResult {
        switch baseCommitResult {
        case .commit(let text):
            return .commit(text + symbol)
        case .polishRequested:
            return rawInput.isEmpty ? .commit(symbol) : .commit(rawInput + symbol)
        case .noAction:
            return rawInput.isEmpty ? .commit(symbol) : .commit(rawInput + symbol)
        }
    }
}
