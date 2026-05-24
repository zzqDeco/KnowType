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
        guard frame.isVisible else {
            host?.updateCandidatePanel(state: frame.panelModel, locale: locale)
            host?.hideCandidatePanel()
            return
        }
        host?.updateCandidatePanel(state: frame.panelModel, locale: locale)
    }

    func hide(
        reason: CandidatePanelVisibilityReason,
        compositionID: Int,
        rawRevision: Int,
        rawLength: Int
    ) {
        let frame = CandidatePanelFrame(
            compositionID: compositionID,
            rawRevision: rawRevision,
            rawLength: rawLength,
            panelModel: CandidatePanelState(),
            anchorSource: .none,
            visibilityReason: reason
        )
        trace(frame)
        host?.hideCandidatePanel()
    }

    private func trace(_ frame: CandidatePanelFrame) {
        guard ProcessInfo.processInfo.environment["KNOWTYPE_PANEL_DEBUG"] == "1" else {
            return
        }
        let windowState = frame.panelModel.windowState
        fputs(
            "KnowType panel frame: reason=\(frame.visibilityReason.rawValue) compositionID=\(frame.compositionID) rawRevision=\(frame.rawRevision) rawLength=\(frame.rawLength) anchorSource=\(frame.anchorSource.rawValue) visible=\(windowState.isVisible) layoutMode=\(windowState.layoutMode.rawValue)\n",
            stderr
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
