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

public enum InputPreviousCharacterKind: String, Sendable, Equatable {
    case asciiDigit
    case whitespace
    case openingPunctuation
    case closingPunctuation
    case quotePunctuation
    case text
    case unknown
}

public enum InputQuoteContext: String, Sendable, Equatable {
    case opening
    case closing
    case unknown
}

public struct InputPunctuatorContext: Sendable, Equatable {
    public var state: InputModeState
    public var previousCharacterKind: InputPreviousCharacterKind
    public var quoteContext: InputQuoteContext
    public var hasActiveComposition: Bool

    public init(
        state: InputModeState,
        previousCharacterKind: InputPreviousCharacterKind = .unknown,
        quoteContext: InputQuoteContext = .unknown,
        hasActiveComposition: Bool = false
    ) {
        self.state = state
        self.previousCharacterKind = previousCharacterKind
        self.quoteContext = quoteContext
        self.hasActiveComposition = hasActiveComposition
    }
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
        decision(
            for: input,
            context: InputPunctuatorContext(state: state),
            prefersCandidateList: prefersCandidateList
        )
    }

    public mutating func decision(
        for input: String,
        context: InputPunctuatorContext,
        prefersCandidateList: Bool = true
    ) -> InputPunctuatorDecision? {
        guard InputSymbolTransformer.isSymbolInput(input) else {
            return nil
        }
        if input == ".",
           !context.hasActiveComposition,
           context.previousCharacterKind == .asciiDigit {
            return .commit(".")
        }
        let state = context.state
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
            let isOpening = resolvedQuoteIsOpening(
                context.quoteContext,
                fallback: nextDoubleQuoteIsOpening
            )
            let text = isOpening ? "“" : "”"
            nextDoubleQuoteIsOpening = !isOpening
            return .commit(text)
        }
        if input == "'" {
            let isOpening = resolvedQuoteIsOpening(
                context.quoteContext,
                fallback: nextSingleQuoteIsOpening
            )
            let text = isOpening ? "‘" : "’"
            nextSingleQuoteIsOpening = !isOpening
            return .commit(text)
        }
        if prefersCandidateList,
           let candidates = Self.symbolCandidates[input] {
            return .showCandidates(InputSymbolCandidateSession(trigger: input, candidates: candidates))
        }
        return .commit(input)
    }

    private func resolvedQuoteIsOpening(_ context: InputQuoteContext, fallback: Bool) -> Bool {
        switch context {
        case .opening:
            return true
        case .closing:
            return false
        case .unknown:
            return fallback
        }
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
        guard input.unicodeScalars.count == 1,
              let scalar = input.unicodeScalars.first,
              scalar.value >= 0x21,
              scalar.value <= 0x7E else {
            return false
        }
        return !(0x30...0x39).contains(scalar.value)
            && !(0x41...0x5A).contains(scalar.value)
            && !(0x61...0x7A).contains(scalar.value)
    }

    public static func symbolWithWidth(for input: String, width: InputSymbolWidth) -> String {
        switch width {
        case .halfWidth:
            return input
        case .fullWidth:
            return Self.textWithWidth(for: input, width: width)
        }
    }

    public static func fullWidthSymbol(for input: String) -> String? {
        guard isSymbolInput(input) else {
            return nil
        }
        return textWithWidth(for: input, width: .fullWidth)
    }

    public static func textWithWidth(for input: String, width: InputSymbolWidth) -> String {
        guard width == .fullWidth else {
            return input
        }
        var transformed = String.UnicodeScalarView()
        transformed.reserveCapacity(input.unicodeScalars.count)
        for scalar in input.unicodeScalars {
            let value: UInt32
            switch scalar.value {
            case 0x20:
                value = 0x3000
            case 0x21...0x7E:
                value = scalar.value + 0xFEE0
            default:
                value = scalar.value
            }
            transformed.append(UnicodeScalar(value)!)
        }
        return String(transformed)
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
        case .noAction:
            return rawInput.isEmpty ? .commit(symbol) : .commit(rawInput + symbol)
        }
    }
}
