import Foundation
import KnowTypeAI
import KnowTypeCore

public enum InputCandidateSelectionKind: Sendable, Equatable {
    case rawInput
    case prefixCandidate(index: Int)
    case fullCandidate(index: Int)
    case segmentCandidate(index: Int)
    case aiRecommendation
    case continuationCandidate(index: Int)
}

extension InputCandidateSelectionKind {
    var analyticsSource: String {
        switch self {
        case .rawInput:
            return "raw"
        case .prefixCandidate:
            return "traditional-prefix"
        case .fullCandidate:
            return "traditional-full"
        case .segmentCandidate:
            return "traditional-segment"
        case .aiRecommendation:
            return "ai"
        case .continuationCandidate:
            return "continuation"
        }
    }
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
        var seenTexts = Set(candidates.map(\.text))

        guard let suggestion else {
            return candidates
        }

        for (index, prefix) in suggestion.prefixCandidates.enumerated()
            where !seenTexts.contains(prefix.text) {
            candidates.append(
                InputCandidateSelection(
                    text: prefix.text,
                    kind: prefixSelectionKind(for: prefix, rawInput: rawInput, index: index)
                )
            )
            seenTexts.insert(prefix.text)
            if index == 0 {
                break
            }
        }

        // Native candidates only mirror traditional suggestions. The custom panel owns AI slot rendering.
        for (index, prefix) in suggestion.prefixCandidates.dropFirst().enumerated()
            where !seenTexts.contains(prefix.text) {
            candidates.append(
                InputCandidateSelection(
                    text: prefix.text,
                    kind: prefixSelectionKind(for: prefix, rawInput: rawInput, index: index + 1)
                )
            )
            seenTexts.insert(prefix.text)
        }

        for (index, continuation) in suggestion.continuationCandidates.enumerated() {
            let text = continuation.text
            guard !seenTexts.contains(text) else {
                continue
            }
            candidates.append(
                InputCandidateSelection(
                    text: text,
                    kind: .continuationCandidate(index: index)
                )
            )
            seenTexts.insert(text)
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
