import Foundation
import KnowTypeCore

public enum InputAction: Sendable, Equatable {
    case space
    case tab
    case optionNumber(Int)
    case optionR
}

public enum InputCommitResult: Sendable, Equatable {
    case commit(String)
    case polishRequested(String)
    case noAction
}

public struct CandidatePanelViewModel: Sendable, Equatable {
    public var title: String
    public var rawInput: String
    public var prefixCandidates: [CorrectionCandidate]
    public var continuationCandidates: [ContinuationCandidate]

    public init(
        title: String = "KnowType",
        rawInput: String,
        prefixCandidates: [CorrectionCandidate],
        continuationCandidates: [ContinuationCandidate]
    ) {
        self.title = title
        self.rawInput = rawInput
        self.prefixCandidates = prefixCandidates
        self.continuationCandidates = continuationCandidates
    }

    public var lockedPreview: String? {
        guard let prefix = prefixCandidates.first?.text else {
            return nil
        }
        guard let continuation = continuationCandidates.first?.text else {
            return prefix
        }
        return "\(prefix) | \(continuation)"
    }
}

public struct InputCompositionController: Sendable {
    public init() {}

    public func handle(
        action: InputAction,
        prefixCandidates: [CorrectionCandidate],
        continuationCandidates: [ContinuationCandidate],
        originalText: String
    ) -> InputCommitResult {
        guard let prefix = prefixCandidates.first?.text else {
            return .noAction
        }

        switch action {
        case .space:
            return .commit(prefix)
        case .tab:
            guard let continuation = continuationCandidates.first?.text else {
                return .commit(prefix)
            }
            return .commit(join(prefix: prefix, continuation: continuation))
        case .optionNumber(let number):
            let index = number - 1
            guard continuationCandidates.indices.contains(index) else {
                return .noAction
            }
            return .commit(join(prefix: prefix, continuation: continuationCandidates[index].text))
        case .optionR:
            return .polishRequested(originalText)
        }
    }

    private func join(prefix: String, continuation: String) -> String {
        if prefix.range(of: #"\p{Han}$"#, options: .regularExpression) != nil,
           continuation.range(of: #"^[A-Za-z0-9]"#, options: .regularExpression) != nil {
            return "\(prefix) \(continuation)"
        }
        if prefix.range(of: #"[A-Za-z0-9]$"#, options: .regularExpression) != nil,
           continuation.range(of: #"^[A-Za-z0-9]"#, options: .regularExpression) != nil {
            return "\(prefix) \(continuation)"
        }
        return "\(prefix)\(continuation)"
    }
}
