import Foundation
import KnowTypeCore

public enum CustomCandidateSelectionDecision: Sendable, Equatable {
    case commitRawInput
    case commitPrefixCandidate(Int)
    case passThrough
}

public struct CustomCandidateSelectionPolicy: Sendable {
    public init() {}

    public func decision(
        for stroke: InputKeyStroke,
        rawInput: String,
        suggestion: SuggestionResponse?,
        suggestionRawInput: String?
    ) -> CustomCandidateSelectionDecision {
        guard stroke.modifiers.isEmpty,
              let number = Self.selectionNumberByKeyCode[stroke.keyCode],
              stroke.text == String(number),
              let suggestion,
              SuggestionPublicationGuard.hasCurrentSuggestion(
                suggestionRawInput: suggestionRawInput,
                currentRawInput: rawInput
              ) else {
            return .passThrough
        }

        if number == 0 {
            guard !suggestion.prefixCandidates.isEmpty else {
                return .passThrough
            }
            return rawInput.isEmpty ? .passThrough : .commitRawInput
        }

        let prefixIndex = number - 1
        guard suggestion.prefixCandidates.indices.contains(prefixIndex) else {
            return .passThrough
        }
        return .commitPrefixCandidate(prefixIndex)
    }

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
}
