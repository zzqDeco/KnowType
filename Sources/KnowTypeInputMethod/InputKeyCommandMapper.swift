import Foundation

public enum InputModifier: Sendable, Equatable, Hashable {
    case option
    case command
    case control
}

public enum InputKeyEventKind: Sendable, Equatable {
    case keyDown
    case keyUp
    case flagsChanged
}

public struct InputKeyStroke: Sendable, Equatable {
    public var text: String
    public var keyCode: Int
    public var modifiers: Set<InputModifier>
    public var eventKind: InputKeyEventKind

    public init(
        text: String,
        keyCode: Int,
        modifiers: Set<InputModifier> = [],
        eventKind: InputKeyEventKind = .keyDown
    ) {
        self.text = text
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.eventKind = eventKind
    }
}

public enum InputCandidateNavigation: Sendable, Equatable {
    case up
    case down
    case left
    case right
    case pageUp
    case pageDown
}

public enum InputKeyIntent: Sendable, Equatable {
    case append(String)
    case symbol(String)
    case deleteBackward
    case action(InputAction)
    case cancelComposition
    case selectCandidate(Int)
    case moveCandidateSelection(InputCandidateNavigation)
    case modifierFlagsChanged(Set<InputModifier>)
    case ignored
}

public struct InputKeyCommandMapper: Sendable {
    public init() {}

    public func intent(for stroke: InputKeyStroke) -> InputKeyIntent {
        switch stroke.eventKind {
        case .keyUp:
            return .ignored
        case .flagsChanged:
            return .modifierFlagsChanged(stroke.modifiers)
        case .keyDown:
            break
        }

        if stroke.modifiers.contains(.command) || stroke.modifiers.contains(.control) {
            return .ignored
        }

        if stroke.modifiers.contains(.option) {
            if stroke.keyCode == Self.periodKeyCode {
                return .action(.toggleSymbolMode)
            }
            if let digit = optionDigit(for: stroke.keyCode) {
                return .action(.optionNumber(digit))
            }
            if stroke.keyCode == Self.rKeyCode {
                return .action(.optionR)
            }
            return .ignored
        }

        if stroke.keyCode == Self.escapeKeyCode || stroke.text == Self.escapeText {
            return .cancelComposition
        }
        if stroke.keyCode == Self.deleteKeyCode || stroke.text == Self.deleteText {
            return .deleteBackward
        }
        if stroke.keyCode == Self.tabKeyCode || stroke.text == "\t" {
            return .action(.tab)
        }
        if stroke.keyCode == Self.returnKeyCode || stroke.keyCode == Self.keypadEnterKeyCode
            || stroke.text == "\r" || stroke.text == "\n" {
            return .action(.commitRaw)
        }
        if stroke.keyCode == Self.spaceKeyCode || stroke.text == " " {
            return .action(.space)
        }
        if let navigation = Self.navigationByKeyCode[stroke.keyCode] {
            return .moveCandidateSelection(navigation)
        }
        if let number = Self.selectionNumberByKeyCode[stroke.keyCode],
           stroke.text == String(number) {
            return .selectCandidate(number)
        }
        if InputSymbolTransformer.isSymbolInput(stroke.text) {
            return .symbol(stroke.text)
        }
        guard Self.isAppendableText(stroke.text) else {
            return .ignored
        }
        return .append(stroke.text)
    }

    private func optionDigit(for keyCode: Int) -> Int? {
        Self.digitKeyCodes[keyCode]
    }

    public static func isAppendableText(_ text: String) -> Bool {
        guard !text.isEmpty else {
            return false
        }
        return text.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                && !CharacterSet.newlines.contains(scalar)
                && !appKitFunctionKeyScalarRange.contains(scalar.value)
        }
    }

    private static let tabKeyCode = 48
    private static let spaceKeyCode = 49
    private static let returnKeyCode = 36
    private static let keypadEnterKeyCode = 76
    private static let deleteKeyCode = 51
    private static let deleteText = "\u{7F}"
    private static let escapeKeyCode = 53
    private static let escapeText = "\u{1B}"
    private static let rKeyCode = 15
    private static let periodKeyCode = 47
    private static let appKitFunctionKeyScalarRange: ClosedRange<UInt32> = 0xF700...0xF8FF

    private static let digitKeyCodes: [Int: Int] = [
        18: 1,
        19: 2,
        20: 3,
        21: 4,
        23: 5,
        22: 6,
        26: 7,
        28: 8,
        25: 9
    ]

    private static let selectionNumberByKeyCode: [Int: Int] = [
        29: 0,
        18: 1,
        19: 2,
        20: 3,
        21: 4,
        23: 5,
        22: 6,
        26: 7,
        28: 8,
        25: 9
    ]

    private static let navigationByKeyCode: [Int: InputCandidateNavigation] = [
        123: .left,
        124: .right,
        125: .down,
        126: .up,
        116: .pageUp,
        121: .pageDown
    ]
}
