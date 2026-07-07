import Foundation
import KnowTypeCore

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

    private static let asciiSymbolInputs: Set<String> = Set(fullWidthSymbolMap.keys)

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
        "<": "《",
        ">": "》",
        "/": "、"
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
