import Foundation

public enum LLMTask: String, Codable, Sendable, Equatable {
    case correction
    case continuation
    case polish
}

public enum KnowTypeLocale: String, Codable, Sendable, Equatable {
    case zhCN = "zh-CN"
    case enUS = "en-US"
    case mixed
}

public enum ContinuationLengthLevel: String, Codable, Sendable, Equatable {
    case short
    case medium
    case long
}

public enum CorrectionLevel: Int, Codable, Sendable, Equatable, Comparable {
    case none = 0
    case light = 1
    case contextual = 2
    case strongAlternative = 3

    public static func < (lhs: CorrectionLevel, rhs: CorrectionLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct ProtectedRange: Codable, Sendable, Equatable {
    public var start: Int
    public var length: Int
    public var reason: String

    public init(start: Int, length: Int, reason: String) {
        self.start = start
        self.length = length
        self.reason = reason
    }
}

public struct InputContext: Codable, Sendable, Equatable {
    public var rawInput: String
    public var appBundleID: String?
    public var locale: KnowTypeLocale
    public var userSelectionHistory: [String]

    public init(
        rawInput: String,
        appBundleID: String? = nil,
        locale: KnowTypeLocale = .mixed,
        userSelectionHistory: [String] = []
    ) {
        self.rawInput = rawInput
        self.appBundleID = appBundleID
        self.locale = locale
        self.userSelectionHistory = userSelectionHistory
    }
}

public struct CorrectionCandidate: Codable, Sendable, Equatable {
    public var text: String
    public var source: String
    public var confidence: Double
    public var correctionLevel: CorrectionLevel
    public var protectedRanges: [ProtectedRange]

    public init(
        text: String,
        source: String,
        confidence: Double,
        correctionLevel: CorrectionLevel,
        protectedRanges: [ProtectedRange] = []
    ) {
        self.text = text
        self.source = source
        self.confidence = confidence
        self.correctionLevel = correctionLevel
        self.protectedRanges = protectedRanges
    }
}

public struct LockedPrefix: Codable, Sendable, Equatable {
    public var text: String
    public var rawInput: String
    public var candidateID: String
    public var protectedRanges: [ProtectedRange]

    public init(
        text: String,
        rawInput: String,
        candidateID: String,
        protectedRanges: [ProtectedRange] = []
    ) {
        self.text = text
        self.rawInput = rawInput
        self.candidateID = candidateID
        self.protectedRanges = protectedRanges
    }
}

public struct ContinuationCandidate: Codable, Sendable, Equatable {
    public var text: String
    public var lengthLevel: ContinuationLengthLevel
    public var confidence: Double
    public var provider: String
    public var reason: String?

    public init(
        text: String,
        lengthLevel: ContinuationLengthLevel,
        confidence: Double,
        provider: String,
        reason: String? = nil
    ) {
        self.text = text
        self.lengthLevel = lengthLevel
        self.confidence = confidence
        self.provider = provider
        self.reason = reason
    }
}

public struct SuggestionResponse: Codable, Sendable, Equatable {
    public var prefixCandidates: [CorrectionCandidate]
    public var lockedPrefix: LockedPrefix?
    public var continuationCandidates: [ContinuationCandidate]
    public var latencyMs: Int

    public init(
        prefixCandidates: [CorrectionCandidate],
        lockedPrefix: LockedPrefix?,
        continuationCandidates: [ContinuationCandidate],
        latencyMs: Int
    ) {
        self.prefixCandidates = prefixCandidates
        self.lockedPrefix = lockedPrefix
        self.continuationCandidates = continuationCandidates
        self.latencyMs = latencyMs
    }
}

public struct LLMCandidate: Codable, Sendable, Equatable {
    public var text: String
    public var confidence: Double?
    public var reason: String?

    public init(text: String, confidence: Double? = nil, reason: String? = nil) {
        self.text = text
        self.confidence = confidence
        self.reason = reason
    }
}

public struct LLMRequest: Codable, Sendable, Equatable {
    public var task: LLMTask
    public var lockedPrefix: String?
    public var rawInput: String?
    public var locale: KnowTypeLocale
    public var appContext: String?
    public var maxCandidates: Int
    public var lengthLevel: ContinuationLengthLevel?
    public var outputSchema: String

    public init(
        task: LLMTask,
        lockedPrefix: String? = nil,
        rawInput: String? = nil,
        locale: KnowTypeLocale = .mixed,
        appContext: String? = nil,
        maxCandidates: Int = 3,
        lengthLevel: ContinuationLengthLevel? = nil,
        outputSchema: String = "json"
    ) {
        self.task = task
        self.lockedPrefix = lockedPrefix
        self.rawInput = rawInput
        self.locale = locale
        self.appContext = appContext
        self.maxCandidates = max(1, maxCandidates)
        self.lengthLevel = lengthLevel
        self.outputSchema = outputSchema
    }
}

public struct LLMResponse: Codable, Sendable, Equatable {
    public var candidates: [LLMCandidate]

    public init(candidates: [LLMCandidate]) {
        self.candidates = candidates
    }
}

public protocol LLMProvider: Sendable {
    var providerName: String { get }
    func complete(_ request: LLMRequest) async throws -> LLMResponse
}
