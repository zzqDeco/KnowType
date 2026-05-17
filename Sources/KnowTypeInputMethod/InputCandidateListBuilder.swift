import Foundation
import KnowTypeCore

public enum InputCandidateSelectionKind: Sendable, Equatable {
    case rawInput
    case prefixCandidate(index: Int)
    case fullCandidate(index: Int)
    case segmentCandidate(index: Int)
    case continuationCandidate(index: Int)
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
        let hasSuggestedCandidates = suggestion?.prefixCandidates.isEmpty == false
            || suggestion?.continuationCandidates.isEmpty == false
        var candidates: [InputCandidateSelection] = rawInput.isEmpty || hasSuggestedCandidates
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
                    kind: prefixSelectionKind(for: prefix, rawInput: rawInput, index: index)
                )
            )
        }

        for (index, continuation) in suggestion.continuationCandidates.enumerated() {
            let text = continuation.text
            guard !candidates.map(\.text).contains(text) else {
                continue
            }
            candidates.append(
                InputCandidateSelection(
                    text: text,
                    kind: .continuationCandidate(index: index)
                )
            )
        }
        return candidates
    }

    private func prefixSelectionKind(
        for candidate: CorrectionCandidate,
        rawInput: String,
        index: Int
    ) -> InputCandidateSelectionKind {
        guard let range = candidate.rawRange else {
            return .prefixCandidate(index: index)
        }
        let fullRange = KnowTypeCore.TextRange(start: 0, length: rawInput.count)
        if range == fullRange {
            return .fullCandidate(index: index)
        }
        return .segmentCandidate(index: index)
    }
}
