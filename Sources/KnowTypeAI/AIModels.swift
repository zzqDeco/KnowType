import Foundation
import KnowTypeCore

public struct AIRecommendationCandidate: Codable, Sendable, Equatable {
    public var prefixText: String
    public var continuationText: String?
    public var displayText: String
    public var confidence: Double
    public var provider: String
    public var contextVersion: String

    public init(
        prefixText: String,
        continuationText: String? = nil,
        displayText: String,
        confidence: Double,
        provider: String,
        contextVersion: String
    ) {
        self.prefixText = prefixText
        self.continuationText = continuationText
        self.displayText = displayText
        self.confidence = confidence
        self.provider = provider
        self.contextVersion = contextVersion
    }
}

public enum AIRecommendationState: Sendable, Equatable {
    case idle
    case pending(requestID: UUID)
    case ready(AIRecommendationCandidate)
    case ineligible(reason: String)
    case unavailable(reason: String)

    public var isSelectableRecommendation: Bool {
        if case .ready = self {
            return true
        }
        return false
    }

    public var displayText: String? {
        switch self {
        case .idle:
            return nil
        case .pending:
            return "AI 推荐中..."
        case .ready(let candidate):
            return candidate.displayText
        case .ineligible(let reason):
            return reason
        case .unavailable(let reason):
            return reason
        }
    }
}

public struct AIRecommendationRequest: Sendable, Equatable {
    public var requestID: UUID
    public var rawInput: String
    public var traditionalCandidate: CorrectionCandidate
    public var appBundleID: String?
    public var appName: String?
    public var locale: KnowTypeLocale
    public var compositionID: Int
    public var lexicalContext: LexicalContextSnapshot?

    public init(
        rawInput: String,
        traditionalCandidate: CorrectionCandidate,
        appBundleID: String? = nil,
        appName: String? = nil,
        locale: KnowTypeLocale = .mixed,
        compositionID: Int,
        requestID: UUID = UUID(),
        lexicalContext: LexicalContextSnapshot? = nil
    ) {
        self.requestID = requestID
        self.rawInput = rawInput
        self.traditionalCandidate = traditionalCandidate
        self.appBundleID = appBundleID
        self.appName = appName
        self.locale = locale
        self.compositionID = compositionID
        self.lexicalContext = lexicalContext
    }
}

public protocol AIRecommendationProviding: Sendable {
    func recommendation(for request: AIRecommendationRequest) async -> AIRecommendationState
}

public enum AITypingCommitKind: String, Codable, Sendable, Equatable {
    case traditional
    case ai
    case raw
    case polish
    case symbol
    case externalDelete
}

public struct AITypingEvent: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var appBundleID: String?
    public var appName: String?
    public var rawInput: String?
    public var committedText: String?
    public var commitKind: AITypingCommitKind
    public var candidateSource: String
    public var deleteCountBeforeCommit: Int

    public init(
        timestamp: Date = Date(),
        appBundleID: String? = nil,
        appName: String? = nil,
        rawInput: String? = nil,
        committedText: String? = nil,
        commitKind: AITypingCommitKind,
        candidateSource: String,
        deleteCountBeforeCommit: Int = 0
    ) {
        self.timestamp = timestamp
        self.appBundleID = appBundleID
        self.appName = appName
        self.rawInput = rawInput
        self.committedText = committedText
        self.commitKind = commitKind
        self.candidateSource = candidateSource
        self.deleteCountBeforeCommit = deleteCountBeforeCommit
    }
}

public protocol AIContextEventRecording: Sendable {
    func record(_ event: AITypingEvent) async
}
