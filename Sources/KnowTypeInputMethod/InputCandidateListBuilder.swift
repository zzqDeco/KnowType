import Foundation
import KnowTypeCore

public enum InputCandidateSelectionKind: Sendable, Equatable {
    case rawInput
    case prefixCandidate(index: Int)
}

public struct InputCandidateSelection: Sendable, Equatable {
    public var text: String
    public var kind: InputCandidateSelectionKind

    public init(text: String, kind: InputCandidateSelectionKind) {
        self.text = text
        self.kind = kind
    }
}

public struct InputCandidateListBuilder: Sendable {
    public init() {}

    public func candidates(rawInput: String, suggestion: SuggestionResponse?) -> [String] {
        candidateSelections(rawInput: rawInput, suggestion: suggestion).map(\.text)
    }

    public func candidateSelections(rawInput: String, suggestion: SuggestionResponse?) -> [InputCandidateSelection] {
        var candidates: [InputCandidateSelection] = rawInput.isEmpty
            ? []
            : [InputCandidateSelection(text: rawInput, kind: .rawInput)]

        guard let suggestion else {
            return candidates
        }

        for (index, prefix) in suggestion.prefixCandidates.enumerated()
            where !candidates.map(\.text).contains(prefix.text) {
            candidates.append(
                InputCandidateSelection(
                    text: prefix.text,
                    kind: .prefixCandidate(index: index)
                )
            )
        }
        return candidates
    }
}
