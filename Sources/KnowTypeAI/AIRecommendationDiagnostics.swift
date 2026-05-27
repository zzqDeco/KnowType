import Foundation
import OSLog

public enum AIRecommendationDiagnosticStage: String, Sendable, Equatable {
    case skippedNoProvider = "skipped_no_provider"
    case skippedDisabled = "skipped_disabled"
    case skippedIneligible = "skipped_ineligible"
    case skippedProtectedText = "skipped_protected_text"
    case debounceStart = "debounce_start"
    case debounceEnd = "debounce_end"
    case cacheHit = "cache_hit"
    case cacheMiss = "cache_miss"
    case contextLoaded = "context_loaded"
    case providerRequestStart = "provider_request_start"
    case providerResponse = "provider_response"
    case structuredSchemaRequest = "structured_schema_request"
    case structuredSchemaUnsupported = "structured_schema_unsupported"
    case structuredDecodeError = "structured_decode_error"
    case sanitizeEmpty = "sanitize_empty"
    case sanitizeReject = "sanitize_reject"
    case sanitizeRepair = "sanitize_repair"
    case ready
    case timeout
    case providerError = "provider_error"
    case cooldownActive = "cooldown_active"
    case cancelled
    case skippedPrefixTooShort = "skipped_prefix_too_short"
    case scheduled
    case cancelPrevious = "cancel_previous"
    case staleResultDropped = "stale_result_dropped"
    case stateApplied = "state_applied"
    case lexicalProfileLoad = "lexical_profile_load"
    case rimeUserDBSnapshotLoadStart = "rime_userdb_snapshot_load_start"
    case rimeUserDBSnapshotLoadEnd = "rime_userdb_snapshot_load_end"
    case rimeUserDBSyncStart = "rime_userdb_sync_start"
    case rimeUserDBSyncEnd = "rime_userdb_sync_end"
    case rimeUserDBParse = "rime_userdb_parse"
    case lexicalProfileUpdated = "lexical_profile_updated"
    case lexicalProfileFallback = "lexical_profile_fallback"
    case acceptedLearningRecorded = "accepted_learning_recorded"
    case acceptedLearningSkippedSecret = "accepted_learning_skipped_secret"
    case acceptedLearningTermsExtracted = "accepted_learning_terms_extracted"
    case acceptedLearningProfileMerged = "accepted_learning_profile_merged"
}

public struct AIRecommendationDiagnosticEvent: Sendable, Equatable {
    public var stage: AIRecommendationDiagnosticStage
    public var requestID: UUID?
    public var compositionID: Int?
    public var rawLength: Int?
    public var prefixLength: Int?
    public var appBundleID: String?
    public var providerName: String?
    public var elapsedMilliseconds: Int?
    public var candidateCount: Int?
    public var acceptedCount: Int?
    public var reason: String?

    public init(
        stage: AIRecommendationDiagnosticStage,
        requestID: UUID? = nil,
        compositionID: Int? = nil,
        rawLength: Int? = nil,
        prefixLength: Int? = nil,
        appBundleID: String? = nil,
        providerName: String? = nil,
        elapsedMilliseconds: Int? = nil,
        candidateCount: Int? = nil,
        acceptedCount: Int? = nil,
        reason: String? = nil
    ) {
        self.stage = stage
        self.requestID = requestID
        self.compositionID = compositionID
        self.rawLength = rawLength
        self.prefixLength = prefixLength
        self.appBundleID = appBundleID
        self.providerName = providerName
        self.elapsedMilliseconds = elapsedMilliseconds
        self.candidateCount = candidateCount
        self.acceptedCount = acceptedCount
        self.reason = reason
    }
}

public protocol AIRecommendationDiagnosticSink: Sendable {
    func record(_ event: AIRecommendationDiagnosticEvent)
}

public struct NoopAIRecommendationDiagnosticSink: AIRecommendationDiagnosticSink {
    public init() {}

    public func record(_: AIRecommendationDiagnosticEvent) {}
}

public struct OSLogAIRecommendationDiagnosticSink: AIRecommendationDiagnosticSink {
    private let logger = Logger(
        subsystem: "com.knowtype.inputmethod.KnowType",
        category: "ai"
    )

    public init() {}

    public func record(_ event: AIRecommendationDiagnosticEvent) {
        logger.notice(
            """
            AI stage=\(event.stage.rawValue, privacy: .public) \
            requestID=\(event.requestID?.uuidString ?? "-", privacy: .public) \
            compositionID=\(event.compositionID ?? -1, privacy: .public) \
            rawLength=\(event.rawLength ?? -1, privacy: .public) \
            prefixLength=\(event.prefixLength ?? -1, privacy: .public) \
            appBundleID=\(event.appBundleID ?? "-", privacy: .public) \
            provider=\(event.providerName ?? "-", privacy: .public) \
            elapsedMs=\(event.elapsedMilliseconds ?? -1, privacy: .public) \
            candidateCount=\(event.candidateCount ?? -1, privacy: .public) \
            acceptedCount=\(event.acceptedCount ?? -1, privacy: .public) \
            reason=\(event.reason ?? "-", privacy: .public)
            """
        )
    }
}
