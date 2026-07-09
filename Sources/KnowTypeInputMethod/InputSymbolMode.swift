import Foundation
import KnowTypeCore

public struct InputSymbolCandidate: Sendable, Equatable {
    public var text: String
    public var label: String

    public init(text: String, label: String? = nil) {
        self.text = text
        self.label = label ?? text
    }
}

public struct InputSymbolCandidateSession: Sendable, Equatable {
    public var trigger: String
    public var candidates: [InputSymbolCandidate]

    public init(trigger: String, candidates: [InputSymbolCandidate]) {
        self.trigger = trigger
        self.candidates = candidates
    }
}

public enum InputPunctuatorDecision: Sendable, Equatable {
    case commit(String)
    case showCandidates(InputSymbolCandidateSession)
    case passThrough(String)
}

public struct InputPunctuatorRuntime: Sendable {
    private var nextDoubleQuoteIsOpening = true
    private var nextSingleQuoteIsOpening = true

    public init() {}

    public mutating func resetPairingState() {
        nextDoubleQuoteIsOpening = true
        nextSingleQuoteIsOpening = true
    }

    public mutating func decision(
        for input: String,
        state: InputModeState,
        prefersCandidateList: Bool = true
    ) -> InputPunctuatorDecision? {
        guard InputSymbolTransformer.isSymbolInput(input) else {
            return nil
        }
        guard state.punctuationMode == .chinese else {
            return .commit(InputSymbolTransformer.symbolWithWidth(for: input, width: state.symbolWidth))
        }
        if state.symbolWidth == .fullWidth,
           let mapped = InputSymbolTransformer.fullWidthSymbol(for: input) {
            return .commit(mapped)
        }
        if let direct = directChinesePunctuation(for: input) {
            return .commit(direct)
        }
        if input == "\"" {
            let text = nextDoubleQuoteIsOpening ? "“" : "”"
            nextDoubleQuoteIsOpening.toggle()
            return .commit(text)
        }
        if input == "'" {
            let text = nextSingleQuoteIsOpening ? "‘" : "’"
            nextSingleQuoteIsOpening.toggle()
            return .commit(text)
        }
        if prefersCandidateList,
           let candidates = Self.symbolCandidates[input] {
            return .showCandidates(InputSymbolCandidateSession(trigger: input, candidates: candidates))
        }
        return .commit(input)
    }

    private func directChinesePunctuation(for input: String) -> String? {
        switch input {
        case ",":
            return "，"
        case ".":
            return "。"
        case "?":
            return "？"
        case "!":
            return "！"
        case ":":
            return "："
        case ";":
            return "；"
        case "(":
            return "（"
        case ")":
            return "）"
        case "^":
            return "……"
        case "_":
            return "——"
        default:
            return nil
        }
    }

    private static let symbolCandidates: [String: [InputSymbolCandidate]] = [
        "/": [
            InputSymbolCandidate(text: "、"),
            InputSymbolCandidate(text: "/"),
            InputSymbolCandidate(text: "／"),
            InputSymbolCandidate(text: "÷")
        ],
        "\\": [
            InputSymbolCandidate(text: "、"),
            InputSymbolCandidate(text: "\\"),
            InputSymbolCandidate(text: "＼")
        ],
        "<": [
            InputSymbolCandidate(text: "《"),
            InputSymbolCandidate(text: "〈"),
            InputSymbolCandidate(text: "«"),
            InputSymbolCandidate(text: "‹")
        ],
        ">": [
            InputSymbolCandidate(text: "》"),
            InputSymbolCandidate(text: "〉"),
            InputSymbolCandidate(text: "»"),
            InputSymbolCandidate(text: "›")
        ],
        "[": [
            InputSymbolCandidate(text: "【"),
            InputSymbolCandidate(text: "「"),
            InputSymbolCandidate(text: "〖"),
            InputSymbolCandidate(text: "〔"),
            InputSymbolCandidate(text: "［")
        ],
        "]": [
            InputSymbolCandidate(text: "】"),
            InputSymbolCandidate(text: "」"),
            InputSymbolCandidate(text: "〗"),
            InputSymbolCandidate(text: "〕"),
            InputSymbolCandidate(text: "］")
        ],
        "{": [
            InputSymbolCandidate(text: "「"),
            InputSymbolCandidate(text: "『"),
            InputSymbolCandidate(text: "〖"),
            InputSymbolCandidate(text: "｛")
        ],
        "}": [
            InputSymbolCandidate(text: "」"),
            InputSymbolCandidate(text: "』"),
            InputSymbolCandidate(text: "〗"),
            InputSymbolCandidate(text: "｝")
        ],
        "$": [
            InputSymbolCandidate(text: "￥"),
            InputSymbolCandidate(text: "$"),
            InputSymbolCandidate(text: "€"),
            InputSymbolCandidate(text: "£"),
            InputSymbolCandidate(text: "¥")
        ],
        "%": [
            InputSymbolCandidate(text: "%"),
            InputSymbolCandidate(text: "％"),
            InputSymbolCandidate(text: "°"),
            InputSymbolCandidate(text: "℃")
        ],
        "*": [
            InputSymbolCandidate(text: "*"),
            InputSymbolCandidate(text: "＊"),
            InputSymbolCandidate(text: "·"),
            InputSymbolCandidate(text: "×"),
            InputSymbolCandidate(text: "※")
        ],
        "|": [
            InputSymbolCandidate(text: "·"),
            InputSymbolCandidate(text: "|"),
            InputSymbolCandidate(text: "｜"),
            InputSymbolCandidate(text: "§"),
            InputSymbolCandidate(text: "¦")
        ],
        "~": [
            InputSymbolCandidate(text: "~"),
            InputSymbolCandidate(text: "〜"),
            InputSymbolCandidate(text: "～"),
            InputSymbolCandidate(text: "〰")
        ]
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
            return Self.symbolWithWidth(for: input, width: state.symbolWidth)
        case .english:
            return Self.symbolWithWidth(for: input, width: state.symbolWidth)
        }
    }

    public static func isSymbolInput(_ input: String) -> Bool {
        guard input.count == 1 else {
            return false
        }
        return asciiSymbolInputs.contains(input)
    }

    private static let asciiSymbolInputs: Set<String> = Set(fullWidthSymbolMap.keys)

    public static func symbolWithWidth(for input: String, width: InputSymbolWidth) -> String {
        switch width {
        case .halfWidth:
            return input
        case .fullWidth:
            return Self.fullWidthSymbolMap[input] ?? input
        }
    }

    public static func fullWidthSymbol(for input: String) -> String? {
        fullWidthSymbolMap[input]
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
