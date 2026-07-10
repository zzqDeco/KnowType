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
    case stale
    case pending(requestID: UUID)
    case ready(AIRecommendationCandidate)
    case ineligible(reason: String)
    case unavailable(reason: String)

    public var isPendingRecommendation: Bool {
        if case .pending = self {
            return true
        }
        return false
    }

    public var isSelectableRecommendation: Bool {
        if case .ready = self {
            return true
        }
        return false
    }

    public var displayText: String? {
        switch self {
        case .idle, .stale:
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
    public var lockedPrefix: String?
    public var candidateHints: [AICandidateHint]
    public var appBundleID: String?
    public var appName: String?
    public var locale: KnowTypeLocale
    public var compositionID: Int
    public var lexicalContext: LexicalContextSnapshot?
    public var feedbackContext: AIAcceptedFeedbackContextSnapshot?

    public init(
        rawInput: String,
        lockedPrefix: String? = nil,
        candidateHints: [AICandidateHint] = [],
        appBundleID: String? = nil,
        appName: String? = nil,
        locale: KnowTypeLocale = .mixed,
        compositionID: Int,
        requestID: UUID = UUID(),
        lexicalContext: LexicalContextSnapshot? = nil,
        feedbackContext: AIAcceptedFeedbackContextSnapshot? = nil
    ) {
        self.requestID = requestID
        self.rawInput = rawInput
        self.lockedPrefix = lockedPrefix?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
            ? nil
            : lockedPrefix
        self.candidateHints = candidateHints
        self.appBundleID = appBundleID
        self.appName = appName
        self.locale = locale
        self.compositionID = compositionID
        self.lexicalContext = lexicalContext
        self.feedbackContext = feedbackContext
    }

    public init(
        rawInput: String,
        traditionalCandidate: CorrectionCandidate,
        appBundleID: String? = nil,
        appName: String? = nil,
        locale: KnowTypeLocale = .mixed,
        compositionID: Int,
        requestID: UUID = UUID(),
        lexicalContext: LexicalContextSnapshot? = nil,
        feedbackContext: AIAcceptedFeedbackContextSnapshot? = nil
    ) {
        self.init(
            rawInput: rawInput,
            lockedPrefix: traditionalCandidate.text,
            candidateHints: [],
            appBundleID: appBundleID,
            appName: appName,
            locale: locale,
            compositionID: compositionID,
            requestID: requestID,
            lexicalContext: lexicalContext,
            feedbackContext: feedbackContext
        )
    }

    public var traditionalCandidate: CorrectionCandidate {
        CorrectionCandidate(
            text: lockedPrefix ?? "",
            source: lockedPrefix == nil ? "raw-input" : "locked-prefix",
            confidence: 1,
            correctionLevel: .contextual
        )
    }
}

public struct AICandidateHint: Codable, Sendable, Equatable, Hashable {
    public var text: String
    public var nativeIndex: Int?
    public var pageNumber: Int
    public var isHighlighted: Bool
    public var comment: String?

    public init(
        text: String,
        nativeIndex: Int? = nil,
        pageNumber: Int = 0,
        isHighlighted: Bool = false,
        comment: String? = nil
    ) {
        self.text = text
        self.nativeIndex = nativeIndex
        self.pageNumber = pageNumber
        self.isHighlighted = isHighlighted
        self.comment = comment
    }

    public var llmHint: LLMCandidateHint {
        LLMCandidateHint(
            text: text,
            nativeIndex: nativeIndex,
            pageNumber: pageNumber,
            isHighlighted: isHighlighted,
            comment: comment
        )
    }
}

public protocol AIRecommendationProviding: Sendable {
    func recommendation(for request: AIRecommendationRequest) async -> AIRecommendationState
}

public enum AIRecommendationProviderAvailability: Sendable, Equatable {
    case unknown
    case available
    case unavailable
}

public protocol AIRecommendationProviderAvailabilitySnapshotting: Sendable {
    var providerAvailability: AIRecommendationProviderAvailability { get }
}

public final class AIRecommendationProviderAvailabilityState:
    AIRecommendationProviderAvailabilitySnapshotting,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var state: AIRecommendationProviderAvailability

    public init(_ state: AIRecommendationProviderAvailability = .unknown) {
        self.state = state
    }

    public var providerAvailability: AIRecommendationProviderAvailability {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    public func update(_ state: AIRecommendationProviderAvailability) {
        lock.lock()
        self.state = state
        lock.unlock()
    }
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
