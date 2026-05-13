import Foundation

public enum InputModifier: Sendable, Equatable, Hashable {
    case option
    case command
    case control
}

public struct InputKeyStroke: Sendable, Equatable {
    public var text: String
    public var keyCode: Int
    public var modifiers: Set<InputModifier>

    public init(text: String, keyCode: Int, modifiers: Set<InputModifier> = []) {
        self.text = text
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum InputKeyIntent: Sendable, Equatable {
    case append(String)
    case deleteBackward
    case action(InputAction)
    case ignored
}

public struct InputKeyCommandMapper: Sendable {
    public init() {}

    public func intent(for stroke: InputKeyStroke) -> InputKeyIntent {
        if stroke.modifiers.contains(.command) || stroke.modifiers.contains(.control) {
            return .ignored
        }

        if stroke.modifiers.contains(.option) {
            if let digit = optionDigit(for: stroke.keyCode) {
                return .action(.optionNumber(digit))
            }
            if stroke.keyCode == Self.rKeyCode {
                return .action(.optionR)
            }
            return .ignored
        }

        if stroke.keyCode == Self.deleteKeyCode {
            return .deleteBackward
        }
        if stroke.keyCode == Self.tabKeyCode || stroke.text == "\t" {
            return .action(.tab)
        }
        if stroke.keyCode == Self.spaceKeyCode || stroke.text == " " {
            return .action(.space)
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
    private static let deleteKeyCode = 51
    private static let rKeyCode = 15
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
}
