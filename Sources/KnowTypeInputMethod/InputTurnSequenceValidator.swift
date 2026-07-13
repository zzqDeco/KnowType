import Foundation

enum InputTurnSequenceViolationCode: String, Sendable, Equatable {
    case prepareAfterRecord = "prepare_after_record"
    case insertBeforeRecord = "insert_before_record"
    case postInsertVerificationBeforeInsert = "post_insert_verification_before_insert"
    case lifecycleResetBeforeHide = "lifecycle_reset_before_hide"
    case lifecycleClearAfterReset = "lifecycle_clear_after_reset"
    case lifecycleInsertAfterReset = "lifecycle_insert_after_reset"
    case lifecyclePublishEndedBeforeFinishWriter = "lifecycle_publish_ended_before_finish_writer"
    case nativeSyncBeforeInsert = "native_sync_before_insert"
    case nativePublishBeforeSync = "native_publish_before_sync"
    case directPassthroughClearsMarkedText = "direct_passthrough_clears_marked_text"
    case directPassthroughInsertBeforeCancelFeedback = "direct_passthrough_insert_before_cancel_feedback"
    case directPassthroughInsertBeforeLifecycleFinish = "direct_passthrough_insert_before_lifecycle_finish"
}

struct InputTurnSequenceViolation: Sendable, Equatable, CustomStringConvertible {
    var code: InputTurnSequenceViolationCode
    var turnID: Int
    var turnKind: InputTurnKind
    var compositionID: Int
    var rawRevision: Int
    var effectIndex: Int?
    var effectName: String?

    var description: String {
        var fields = [
            "code=\(code.rawValue)",
            "turnID=\(turnID)",
            "kind=\(turnKind.rawValue)",
            "compositionID=\(compositionID)",
            "rawRevision=\(rawRevision)"
        ]
        if let effectIndex {
            fields.append("effectIndex=\(effectIndex)")
        }
        if let effectName {
            fields.append("effect=\(effectName)")
        }
        return fields.joined(separator: " ")
    }
}

struct InputTurnSequenceValidator: Sendable {
    func validate(_ sequence: InputTurnEffectSequence) -> [InputTurnSequenceViolation] {
        var violations: [InputTurnSequenceViolation] = []
        validateCommitLikeOrdering(sequence, violations: &violations)
        validateLifecycleOrdering(sequence, violations: &violations)
        validateNativeOrdering(sequence, violations: &violations)
        validateDirectPassthroughOrdering(sequence, violations: &violations)
        return violations
    }

    private func validateCommitLikeOrdering(
        _ sequence: InputTurnEffectSequence,
        violations: inout [InputTurnSequenceViolation]
    ) {
        guard let insertIndex = sequence.effects.firstIndex(where: { $0.isCommittedTextInsert }) else {
            return
        }
        if let recordIndex = sequence.effects.firstIndex(where: { $0.isCommitSideEffectRecord }) {
            if insertIndex < recordIndex {
                violations.append(violation(.insertBeforeRecord, sequence: sequence, index: insertIndex))
            }
            if let prepareIndex = sequence.effects.firstIndex(where: { $0.isAcceptedFeedbackPreparation }),
               prepareIndex > recordIndex {
                violations.append(violation(.prepareAfterRecord, sequence: sequence, index: prepareIndex))
            }
        }
        if let verificationIndex = sequence.effects.firstIndex(where: { $0.isPostInsertCaretVerification }),
           verificationIndex < insertIndex {
            violations.append(
                violation(.postInsertVerificationBeforeInsert, sequence: sequence, index: verificationIndex)
            )
        }
    }

    private func validateLifecycleOrdering(
        _ sequence: InputTurnEffectSequence,
        violations: inout [InputTurnSequenceViolation]
    ) {
        guard let resetIndex = sequence.effects.firstIndex(where: { $0.isConversionEngineReset }) else {
            return
        }
        if let hideIndex = sequence.effects.firstIndex(where: { $0.isCandidatePanelHide }),
           resetIndex < hideIndex {
            violations.append(violation(.lifecycleResetBeforeHide, sequence: sequence, index: resetIndex))
        }
        if let clearIndex = sequence.effects.firstIndex(where: { $0.isOwnedMarkedTextClear }),
           clearIndex > resetIndex {
            violations.append(violation(.lifecycleClearAfterReset, sequence: sequence, index: clearIndex))
        }
        if let lifecycleInsertIndex = sequence.effects.firstIndex(where: { $0.isCommittedTextInsert }),
           lifecycleInsertIndex > resetIndex {
            violations.append(violation(.lifecycleInsertAfterReset, sequence: sequence, index: lifecycleInsertIndex))
        }
        if let publishEndedIndex = sequence.effects.firstIndex(where: { $0.isCompositionEndedPublication }),
           let finishWriterIndex = sequence.effects.firstIndex(where: { $0.isWriterLifecycleFinish }),
           publishEndedIndex < finishWriterIndex {
            violations.append(
                violation(.lifecyclePublishEndedBeforeFinishWriter, sequence: sequence, index: publishEndedIndex)
            )
        }
    }

    private func validateNativeOrdering(
        _ sequence: InputTurnEffectSequence,
        violations: inout [InputTurnSequenceViolation]
    ) {
        guard let syncIndex = sequence.effects.firstIndex(where: { $0.isNativeRawSync }) else {
            return
        }
        if let insertIndex = sequence.effects.firstIndex(where: { $0.isCommittedTextInsert }),
           syncIndex < insertIndex {
            violations.append(violation(.nativeSyncBeforeInsert, sequence: sequence, index: syncIndex))
        }
        if let publishIndex = sequence.effects.firstIndex(where: { $0.isLocalSuggestionPublication }),
           publishIndex < syncIndex {
            violations.append(violation(.nativePublishBeforeSync, sequence: sequence, index: publishIndex))
        }
    }

    private func validateDirectPassthroughOrdering(
        _ sequence: InputTurnEffectSequence,
        violations: inout [InputTurnSequenceViolation]
    ) {
        guard sequence.token.kind == .directPassthrough,
              let insertIndex = sequence.effects.firstIndex(where: { $0.isDirectPassthroughInsert }) else {
            return
        }
        if let clearIndex = sequence.effects.firstIndex(where: { $0.isOwnedMarkedTextClear }) {
            violations.append(violation(.directPassthroughClearsMarkedText, sequence: sequence, index: clearIndex))
        }
        if let cancelIndex = sequence.effects.firstIndex(where: { $0.isAIFeedbackCancellation }),
           insertIndex < cancelIndex {
            violations.append(
                violation(.directPassthroughInsertBeforeCancelFeedback, sequence: sequence, index: insertIndex)
            )
        }
        if let finishIndex = sequence.effects.firstIndex(where: { $0.isWriterLifecycleFinish }),
           insertIndex < finishIndex {
            violations.append(
                violation(.directPassthroughInsertBeforeLifecycleFinish, sequence: sequence, index: insertIndex)
            )
        }
    }

    private func violation(
        _ code: InputTurnSequenceViolationCode,
        sequence: InputTurnEffectSequence,
        index: Int
    ) -> InputTurnSequenceViolation {
        InputTurnSequenceViolation(
            code: code,
            turnID: sequence.token.turnID,
            turnKind: sequence.token.kind,
            compositionID: sequence.token.compositionID,
            rawRevision: sequence.token.rawRevision,
            effectIndex: index,
            effectName: sequence.effects[index].privacySafeName
        )
    }
}

extension InputTurnEffect {
    var privacySafeName: String {
        switch self {
        case .prepareAcceptedFeedback:
            return "prepareAcceptedFeedback"
        case .recordCommitSideEffects:
            return "recordCommitSideEffects"
        case .insertCommittedText:
            return "insertCommittedText"
        case .schedulePostInsertCaretVerification:
            return "schedulePostInsertCaretVerification"
        case .refreshComposition:
            return "refreshComposition"
        case .hideCandidatePanel:
            return "hideCandidatePanel"
        case .clearOwnedMarkedText:
            return "clearOwnedMarkedText"
        case .resetConversionEngine:
            return "resetConversionEngine"
        case .resetCompositionStateAfterLifecycleFinish:
            return "resetCompositionStateAfterLifecycleFinish"
        case .resetAnchorState:
            return "resetAnchorState"
        case .invalidateSuggestion:
            return "invalidateSuggestion"
        case .finishWriterLifecycle:
            return "finishWriterLifecycle"
        case .publishCompositionEnded:
            return "publishCompositionEnded"
        case .cancelAIFeedback:
            return "cancelAIFeedback"
        case .insertDirectPassthroughText:
            return "insertDirectPassthroughText"
        case .syncRawInputFromNativeSnapshot:
            return "syncRawInputFromNativeSnapshot"
        case .publishLocalSuggestion:
            return "publishLocalSuggestion"
        }
    }

    fileprivate var isAcceptedFeedbackPreparation: Bool {
        if case .prepareAcceptedFeedback = self { return true }
        return false
    }

    fileprivate var isCommitSideEffectRecord: Bool {
        if case .recordCommitSideEffects = self { return true }
        return false
    }

    fileprivate var isCommittedTextInsert: Bool {
        if case .insertCommittedText = self { return true }
        return false
    }

    fileprivate var isPostInsertCaretVerification: Bool {
        self == .schedulePostInsertCaretVerification
    }

    fileprivate var isCandidatePanelHide: Bool {
        if case .hideCandidatePanel = self { return true }
        return false
    }

    fileprivate var isOwnedMarkedTextClear: Bool {
        self == .clearOwnedMarkedText
    }

    fileprivate var isConversionEngineReset: Bool {
        self == .resetConversionEngine
    }

    fileprivate var isWriterLifecycleFinish: Bool {
        if case .finishWriterLifecycle = self { return true }
        return false
    }

    fileprivate var isCompositionEndedPublication: Bool {
        if case .publishCompositionEnded = self { return true }
        return false
    }

    fileprivate var isNativeRawSync: Bool {
        if case .syncRawInputFromNativeSnapshot = self { return true }
        return false
    }

    fileprivate var isLocalSuggestionPublication: Bool {
        self == .publishLocalSuggestion
    }

    fileprivate var isDirectPassthroughInsert: Bool {
        if case .insertDirectPassthroughText = self { return true }
        return false
    }

    fileprivate var isAIFeedbackCancellation: Bool {
        if case .cancelAIFeedback = self { return true }
        return false
    }
}
