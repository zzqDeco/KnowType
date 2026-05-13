import Foundation
import KnowTypeCore

public struct InputCandidateListBuilder: Sendable {
    public init() {}

    public func candidates(rawInput: String, suggestion: SuggestionResponse?) -> [String] {
        guard let suggestion else {
            return rawInput.isEmpty ? [] : [rawInput]
        }
        var candidates: [String] = rawInput.isEmpty ? [] : [rawInput]
        for prefix in suggestion.prefixCandidates.map(\.text) where !candidates.contains(prefix) {
            candidates.append(prefix)
        }
        return candidates
    }
}
