import Foundation
import KnowTypeAI
import KnowTypeCore

public enum InputAction: Sendable, Equatable {
    case space
    case tab
    case optionNumber(Int)
    case optionR
    case toggleSymbolMode
    case toggleTextMode
    case toggleSymbolWidth
    case commitRaw
}

public enum InputCommitResult: Sendable, Equatable {
    case commit(String)
    case polishRequested(String)
    case noAction
}

public struct CandidatePanelViewModel: Sendable, Equatable {
    public var title: String
    public var rawInput: String
    public var preeditDisplayText: String?
    public var modeStatusText: String?
    public var prefixCandidates: [CorrectionCandidate]
    public var continuationCandidates: [ContinuationCandidate]
    public var aiRecommendation: AIRecommendationState
    public var aiPolish: InputAIPolishState
    public var symbolCandidates: [InputSymbolCandidate]

    public init(
        title: String = "KnowType",
        rawInput: String,
        preeditDisplayText: String? = nil,
        modeStatusText: String? = nil,
        prefixCandidates: [CorrectionCandidate],
        continuationCandidates: [ContinuationCandidate],
        aiRecommendation: AIRecommendationState = .idle,
        aiPolish: InputAIPolishState = .idle,
        symbolCandidates: [InputSymbolCandidate] = []
    ) {
        self.title = title
        self.rawInput = rawInput
        self.preeditDisplayText = preeditDisplayText
        self.modeStatusText = modeStatusText
        self.prefixCandidates = prefixCandidates
        self.continuationCandidates = continuationCandidates
        self.aiRecommendation = aiRecommendation
        self.aiPolish = aiPolish
        self.symbolCandidates = symbolCandidates
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
        if action == .commitRaw {
            return originalText.isEmpty ? .noAction : .commit(originalText)
        }
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
            guard number > 0 else {
                return .noAction
            }
            let index = number - 1
            guard continuationCandidates.indices.contains(index) else {
                return .noAction
            }
            return .commit(join(prefix: prefix, continuation: continuationCandidates[index].text))
        case .optionR:
            return .polishRequested(originalText)
        case .toggleSymbolMode:
            return .noAction
        case .toggleTextMode:
            return .noAction
        case .toggleSymbolWidth:
            return .noAction
        case .commitRaw:
            return .commit(originalText)
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
