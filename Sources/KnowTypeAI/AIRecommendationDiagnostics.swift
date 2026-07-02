import Foundation
import KnowTypeCore
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
    case dispatchDeferred = "dispatch_deferred"
    case dispatchCancelledByNewInput = "dispatch_cancelled_by_new_input"
    case transportStarted = "transport_started"
    case transportLeftStale = "transport_left_stale"
    case cancelPrevious = "cancel_previous"
    case pendingPlaceholder = "pending_placeholder"
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
    case acceptedFeedbackRecorded = "accepted_feedback_recorded"
    case acceptedFeedbackSkippedSecret = "accepted_feedback_skipped_secret"
    case acceptedFeedbackTrackingCancelled = "accepted_feedback_tracking_cancelled"
}

public struct AIRecommendationDiagnosticEvent: Sendable, Equatable {
    public var stage: AIRecommendationDiagnosticStage
    public var requestID: UUID?
    public var compositionID: Int?
    public var rawLength: Int?
    public var rawRevision: Int?
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
        rawRevision: Int? = nil,
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
        self.rawRevision = rawRevision
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
        InputDebugDiagnostics.emit(
            category: .ai,
            fields: Self.fields(for: event),
            logger: logger
        )
    }

    static func fields(for event: AIRecommendationDiagnosticEvent) -> [InputDebugDiagnostics.Field] {
        var fields: [InputDebugDiagnostics.Field] = [
            .init(.stage, event.stage.rawValue)
        ]
        if let requestID = event.requestID {
            fields.append(.init(.requestID, requestID.uuidString))
        }
        if let compositionID = event.compositionID {
            fields.append(.init(.compositionID, compositionID))
        }
        if let rawLength = event.rawLength {
            fields.append(.init(.rawLength, rawLength))
        }
        if let rawRevision = event.rawRevision {
            fields.append(.init(.rawRevision, rawRevision))
        }
        if let prefixLength = event.prefixLength {
            fields.append(.init(.prefixLength, prefixLength))
        }
        if let providerName = event.providerName {
            fields.append(.init(.provider, providerName))
        }
        if let elapsedMilliseconds = event.elapsedMilliseconds {
            fields.append(.init(.elapsedMs, elapsedMilliseconds))
        }
        if let appBundleID = event.appBundleID {
            fields.append(.init(.bundleID, appBundleID))
        }
        if let reason = event.reason {
            fields.append(.init(.reason, reason))
        }
        return fields
    }
}
