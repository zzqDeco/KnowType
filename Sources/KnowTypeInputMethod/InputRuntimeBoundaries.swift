import Foundation
import KnowTypeAI
import KnowTypeCore

enum CandidatePanelVisibilityReason: String, Sendable, Equatable {
    case compositionActive = "composition_active"
    case compositionEnded = "composition_ended"
    case rawEmpty = "raw_empty"
    case deactivate
    case close
    case escape
    case reset
    case nativeEnded = "native_ended"
    case layoutImpossible = "layout_impossible"
    case staleUpdate = "stale_update"
}

struct CandidatePanelFrame: Sendable, Equatable {
    var presentationGeneration: Int
    var compositionID: Int
    var rawRevision: Int
    var rawLength: Int
    var panelModel: CandidatePanelState
    var anchorSource: CandidateAnchorSource
    var visibilityReason: CandidatePanelVisibilityReason

    var isVisible: Bool {
        panelModel.windowState.isVisible
    }
}

final class CandidatePanelPresenter: @unchecked Sendable {
    private weak var host: InputControllerHost?

    init(host: InputControllerHost) {
        self.host = host
    }

    func apply(_ frame: CandidatePanelFrame, locale: KnowTypeLocale) {
        trace(frame)
        host?.applyCandidatePanelFrame(frame, locale: locale)
    }

    func hide(
        reason: CandidatePanelVisibilityReason,
        presentationGeneration: Int,
        compositionID: Int,
        rawRevision: Int,
        rawLength: Int,
        locale: KnowTypeLocale
    ) {
        let frame = CandidatePanelFrame(
            presentationGeneration: presentationGeneration,
            compositionID: compositionID,
            rawRevision: rawRevision,
            rawLength: rawLength,
            panelModel: CandidatePanelState(),
            anchorSource: .none,
            visibilityReason: reason
        )
        apply(frame, locale: locale)
    }

    private func trace(_ frame: CandidatePanelFrame) {
        InputDebugDiagnostics.emit(
            category: .panel,
            fields: [
                .init(.stage, "frame_apply"),
                .init(.panelGeneration, frame.presentationGeneration),
                .init(.reason, frame.visibilityReason.rawValue),
                .init(.compositionID, frame.compositionID),
                .init(.rawRevision, frame.rawRevision),
                .init(.rawLength, frame.rawLength),
                .init(.anchorSource, frame.anchorSource.rawValue),
                .init(.handled, frame.isVisible)
            ]
        )
    }
}

struct AIRecommendationPatch: Sendable, Equatable {
    var requestID: UUID
    var generation: Int
    var compositionID: Int
    var rawRevision: Int
    var rawInput: String
    var state: AIRecommendationState

    func matches(
        requestID activeRequestID: UUID?,
        generation currentGeneration: Int,
        compositionID currentCompositionID: Int,
        rawRevision currentRawRevision: Int,
        rawInput currentRawInput: String
    ) -> Bool {
        activeRequestID == requestID
            && currentGeneration == generation
            && currentCompositionID == compositionID
            && currentRawRevision == rawRevision
            && currentRawInput == rawInput
    }
}

enum InputRuntimeEvent: Sendable, Equatable {
    case compositionStarted(compositionID: Int, rawRevision: Int)
    case compositionCommitted(text: String, schemaID: String, compositionID: Int)
    case candidateSelected(text: String, schemaID: String, compositionID: Int)
    case compositionEnded(reason: CandidatePanelVisibilityReason, compositionID: Int)
    case appContextChanged(bundleID: String?)
}

actor InputEventBus {
    private let maxRecordedEvents: Int
    private var recordedEvents: [InputRuntimeEvent] = []

    init(maxRecordedEvents: Int = 256) {
        self.maxRecordedEvents = max(0, maxRecordedEvents)
    }

    func publish(_ event: InputRuntimeEvent) {
        guard maxRecordedEvents > 0 else {
            return
        }
        recordedEvents.append(event)
        let overflowCount = recordedEvents.count - maxRecordedEvents
        if overflowCount > 0 {
            recordedEvents.removeFirst(overflowCount)
        }
    }

    func events() -> [InputRuntimeEvent] {
        recordedEvents
    }

    func removeAll() {
        recordedEvents.removeAll()
    }
}

struct InputHotPathContext: Sendable, Equatable {
    var compositionID: Int
    var rawRevision: Int
    var rawInput: String
}

struct InputFrame: Sendable, Equatable {
    var markedText: String?
    var committedText: String?
    var candidateFrame: CandidatePanelFrame?
    var events: [InputRuntimeEvent]
}

protocol InputHotPathRuntime {
    func handle(_ stroke: InputKeyStroke, context: InputHotPathContext) -> InputFrame
}
