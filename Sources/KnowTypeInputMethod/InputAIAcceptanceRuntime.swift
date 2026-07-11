import Foundation
import KnowTypeAI
import KnowTypeCore

struct InputAIAcceptanceCommitContext {
    var text: String
    var rawInput: String
    var schemaID: String
    var appBundleID: String?
    var acceptedAIRecommendation: AIRecommendationCandidate?
    var acceptID: UUID?
    var selectedNativeCandidateSource: String?
    var prefixCandidateSource: String?
    var deleteCountBeforeCommit: Int
    var client: InputControllerClient?
    var commitKindOverride: AITypingCommitKind? = nil
}

struct InputAIAcceptanceFeedbackContext {
    var text: String
    var schemaID: String
    var appBundleID: String?
    var acceptedAIRecommendation: AIRecommendationCandidate?
    var client: InputControllerClient?
}

struct InputAIAcceptanceCommitEffects: Equatable {
    var shouldRecordLexicalCommit: Bool
}

final class InputAIAcceptanceRuntime: @unchecked Sendable {
    private let contextEventRecorder: (any AIContextEventRecording)?
    private let acceptedLearningRecorder: (any AIAcceptedLearningRecording)?
    private let feedbackTracker: AIAcceptedFeedbackTracker
    private let diagnosticSink: any AIRecommendationDiagnosticSink
    private let canRequestAIRecommendations: Bool
    private var runtimePreferences: InputMethodRuntimePreferences

    init(
        contextEventRecorder: (any AIContextEventRecording)?,
        acceptedLearningRecorder: (any AIAcceptedLearningRecording)?,
        acceptedFeedbackRecorder: (any AIAcceptedFeedbackRecording)?,
        diagnosticSink: any AIRecommendationDiagnosticSink,
        canRequestAIRecommendations: Bool,
        runtimePreferences: InputMethodRuntimePreferences
    ) {
        self.contextEventRecorder = contextEventRecorder
        self.acceptedLearningRecorder = acceptedLearningRecorder
        self.feedbackTracker = AIAcceptedFeedbackTracker(
            recorder: acceptedFeedbackRecorder,
            diagnosticSink: diagnosticSink
        )
        self.diagnosticSink = diagnosticSink
        self.canRequestAIRecommendations = canRequestAIRecommendations
        self.runtimePreferences = runtimePreferences
    }

    func updateRuntimePreferences(_ preferences: InputMethodRuntimePreferences) {
        runtimePreferences = preferences
    }

    func prepareAcceptedFeedbackTracking(context: InputAIAcceptanceFeedbackContext) -> UUID? {
        guard let candidate = context.acceptedAIRecommendation,
              candidate.displayText == context.text else {
            return nil
        }
        guard !TextProtection.requiresNoCorrection("knowtype", appBundleID: context.appBundleID) else {
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .acceptedFeedbackTrackingCancelled,
                    reason: "protected_app_context"
                )
            )
            return nil
        }
        let acceptID = UUID()
        let trackingTarget = Self.acceptedFeedbackTrackingTarget(
            text: context.text,
            acceptedAIRecommendation: candidate
        )
        _ = feedbackTracker.armAcceptedSpan(
            acceptID: acceptID,
            acceptedText: context.text,
            trackingText: trackingTarget.text,
            trackingOffsetUTF16: trackingTarget.offsetUTF16,
            schemaID: context.schemaID,
            appBundleID: context.appBundleID,
            provider: candidate.provider,
            contextVersion: candidate.contextVersion,
            client: context.client
        )
        return acceptID
    }

    func recordCommit(context: InputAIAcceptanceCommitContext) -> InputAIAcceptanceCommitEffects {
        let commitKind = commitKind(for: context)
        let candidateSource = candidateSource(for: context)
        if commitKind == .ai {
            if TextProtection.requiresNoCorrection("knowtype", appBundleID: context.appBundleID) {
                diagnosticSink.record(
                    AIRecommendationDiagnosticEvent(
                        stage: .acceptedLearningSkippedSecret,
                        reason: "protected_app_context"
                    )
                )
            } else {
                recordAcceptedAICommit(
                    context: context,
                    candidateSource: candidateSource
                )
            }
        } else if commitKind != .polish {
            feedbackTracker.observeVerifiedReplacementCommit(context.text, client: context.client)
        }
        guard !TextProtection.requiresNoCorrection(context.text, appBundleID: context.appBundleID),
              !TextProtection.requiresNoCorrection(context.rawInput, appBundleID: context.appBundleID),
              !TextProtection.containsSecretLikeContent(context.text),
              !TextProtection.containsSecretLikeContent(context.rawInput) else {
            return InputAIAcceptanceCommitEffects(shouldRecordLexicalCommit: false)
        }
        recordTypingEventIfNeeded(
            context: context,
            commitKind: commitKind,
            candidateSource: candidateSource
        )
        return InputAIAcceptanceCommitEffects(shouldRecordLexicalCommit: commitKind != .polish)
    }

    func recordExternalDelete(appBundleID: String?) {
        guard let contextEventRecorder,
              canRequestAIRecommendations,
              runtimePreferences.cloudContinuationEnabled else {
            return
        }
        let event = AITypingEvent(
            appBundleID: appBundleID,
            appName: appBundleID,
            rawInput: nil,
            committedText: nil,
            commitKind: .externalDelete,
            candidateSource: "external-delete",
            deleteCountBeforeCommit: 1
        )
        Task.detached(priority: .utility) { [contextEventRecorder] in
            await contextEventRecorder.record(event)
        }
    }

    func observeDeleteBackward(client: InputControllerClient?) -> Bool {
        feedbackTracker.observeDeleteBackward(client: client)
    }

    func cancelFeedback(reason: String) {
        feedbackTracker.cancel(reason: reason)
    }

    func verifyPostInsertCaret(client: InputControllerClient?) {
        feedbackTracker.verifyPostInsertCaret(client: client)
    }

    func preserveFeedbackForReplacementComposition(client: InputControllerClient?) -> Bool {
        feedbackTracker.preserveForReplacementComposition(client: client)
    }

    private func recordAcceptedAICommit(
        context: InputAIAcceptanceCommitContext,
        candidateSource: String
    ) {
        guard let acceptedLearningRecorder,
              let candidate = context.acceptedAIRecommendation,
              candidate.displayText == context.text else {
            return
        }
        let lockedPrefix = candidate.prefixText.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = AIAcceptedLearningRecord(
            acceptID: context.acceptID,
            schemaID: context.schemaID,
            appBundleID: context.appBundleID,
            rawInput: context.rawInput.isEmpty ? nil : context.rawInput,
            lockedPrefix: lockedPrefix.isEmpty ? nil : lockedPrefix,
            acceptedText: context.text,
            provider: candidate.provider,
            contextVersion: candidate.contextVersion,
            candidateSource: candidateSource
        )
        Task.detached(priority: .utility) { [acceptedLearningRecorder] in
            await acceptedLearningRecorder.recordAcceptedAI(record)
        }
    }

    private func recordTypingEventIfNeeded(
        context: InputAIAcceptanceCommitContext,
        commitKind: AITypingCommitKind,
        candidateSource: String
    ) {
        guard let contextEventRecorder,
              canRequestAIRecommendations,
              runtimePreferences.cloudContinuationEnabled,
              commitKind != .polish,
              !context.text.isEmpty else {
            return
        }
        let event = AITypingEvent(
            appBundleID: context.appBundleID,
            appName: context.appBundleID,
            rawInput: context.rawInput.isEmpty ? nil : context.rawInput,
            committedText: context.text,
            commitKind: commitKind,
            candidateSource: candidateSource,
            deleteCountBeforeCommit: context.deleteCountBeforeCommit
        )
        Task.detached(priority: .utility) { [contextEventRecorder] in
            await contextEventRecorder.record(event)
        }
    }

    private func commitKind(for context: InputAIAcceptanceCommitContext) -> AITypingCommitKind {
        if let commitKindOverride = context.commitKindOverride {
            return commitKindOverride
        }
        if context.acceptedAIRecommendation != nil {
            return .ai
        }
        if context.text == context.rawInput {
            return .raw
        }
        if context.rawInput.isEmpty {
            return .symbol
        }
        return .traditional
    }

    private func candidateSource(for context: InputAIAcceptanceCommitContext) -> String {
        if context.commitKindOverride == .polish {
            return "ai-polish"
        }
        if let candidate = context.acceptedAIRecommendation {
            return "ai:\(candidate.provider)"
        }
        if context.text == context.rawInput {
            return "raw"
        }
        if let selectedNativeCandidateSource = context.selectedNativeCandidateSource {
            return selectedNativeCandidateSource
        }
        if let prefixCandidateSource = context.prefixCandidateSource {
            return prefixCandidateSource
        }
        return context.rawInput.isEmpty ? "symbol" : "traditional"
    }

    private static func acceptedFeedbackTrackingTarget(
        text: String,
        acceptedAIRecommendation candidate: AIRecommendationCandidate
    ) -> (text: String, offsetUTF16: Int) {
        let prefix = candidate.prefixText
        guard candidate.continuationText != nil,
              !prefix.isEmpty,
              text.hasPrefix(prefix) else {
            return (text, 0)
        }
        let prefixLength = (prefix as NSString).length
        guard prefixLength < (text as NSString).length else {
            return (text, 0)
        }
        let generatedText = (text as NSString).substring(from: prefixLength)
        guard !generatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (text, 0)
        }
        return (generatedText, prefixLength)
    }
}
