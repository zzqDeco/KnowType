import Foundation
import KnowTypeCore

public struct InputCandidateListBuilder: Sendable {
    public init() {}

    public func candidates(rawInput: String, suggestion: SuggestionResponse?) -> [String] {
        guard let suggestion else {
            return rawInput.isEmpty ? [] : [rawInput]
        }
        return suggestion.prefixCandidates.map(\.text)
    }
}
