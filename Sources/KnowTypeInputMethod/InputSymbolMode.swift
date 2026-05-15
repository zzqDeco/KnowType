import Foundation

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

public struct InputSymbolTransformer: Sendable {
    public init() {}

    public func text(for input: String, mode: InputSymbolMode) -> String? {
        guard Self.isSymbolInput(input) else {
            return nil
        }

        switch mode {
        case .chinese:
            return Self.chineseSymbolMap[input] ?? input
        case .english:
            return input
        }
    }

    public static func isSymbolInput(_ input: String) -> Bool {
        guard input.count == 1 else {
            return false
        }
        return asciiSymbolInputs.contains(input)
    }

    private static let asciiSymbolInputs: Set<String> = Set(chineseSymbolMap.keys)

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
