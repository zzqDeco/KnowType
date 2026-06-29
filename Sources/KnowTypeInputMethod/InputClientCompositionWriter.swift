import Foundation
import KnowTypeCore

struct InputClientCompositionWriteState: Sendable, Equatable {
    var compositionID: Int
    var rawLength: Int
    var inputModeState: InputModeState
    var hasActiveComposition: Bool
}

final class InputClientCompositionWriter: @unchecked Sendable {
    private static let commitOnlyCompositionPlaceholder = "\u{3000}"

    private let compatibilityPolicy: InputClientCompatibilityPolicy
    private let writeCoordinator: InputClientWriteCoordinator
    private var ownedMarkedTextClientID: ObjectIdentifier?

    init(
        compatibilityPolicy: InputClientCompatibilityPolicy = InputClientCompatibilityPolicy(),
        writeCoordinator: InputClientWriteCoordinator = InputClientWriteCoordinator()
    ) {
        self.compatibilityPolicy = compatibilityPolicy
        self.writeCoordinator = writeCoordinator
    }

    func writeMode(
        client: InputControllerClient?,
        state: InputClientCompositionWriteState
    ) -> InputClientWriteMode {
        compatibilityPolicy.writeMode(
            bundleIdentifier: client?.bundleIdentifier,
            inputModeState: state.inputModeState,
            hasActiveComposition: state.hasActiveComposition,
            hasClient: client != nil
        )
    }

    func shouldPassThroughIdleText(
        _ text: String,
        client: InputControllerClient?,
        state: InputClientCompositionWriteState,
        reason: String
    ) -> Bool {
        guard !state.hasActiveComposition,
              InputKeyCommandMapper.isAppendableText(text) else {
            return false
        }
        let mode = writeMode(client: client, state: state)
        guard mode == .asciiPassthrough || mode == .disabled else {
            return false
        }
        writeCoordinator.traceDecision(
            kind: "passThrough",
            client: client,
            context: writeContext(client: client, state: state, reason: reason),
            handled: false
        )
        return true
    }

    func insertText(
        _ text: String,
        client: InputControllerClient?,
        state: InputClientCompositionWriteState,
        reason: String,
        clearsOwnedMarkedText: Bool = true
    ) {
        if clearsOwnedMarkedText {
            clearOwnedMarkedTextIfNeeded(client: client, state: state)
        }
        writeCoordinator.insertText(
            text,
            client: client,
            context: writeContext(client: client, state: state, reason: reason)
        )
    }

    @discardableResult
    func refreshComposition(
        client: InputControllerClient?,
        state: InputClientCompositionWriteState,
        markedDisplayText: String?
    ) -> Bool {
        let mode = writeMode(client: client, state: state)
        guard let client else {
            writeCoordinator.traceDecision(
                kind: "skipMarkedText",
                client: client,
                context: writeContext(client: client, state: state, reason: "composition_update"),
                handled: false
            )
            return false
        }
        guard state.hasActiveComposition else {
            clearOwnedMarkedTextIfNeeded(client: client, state: state)
            return false
        }

        guard mode == .inlineComposition || mode == .commitOnlyComposition else {
            clearOwnedMarkedTextIfNeeded(client: client, state: state)
            writeCoordinator.traceDecision(
                kind: "skipMarkedText",
                client: client,
                context: writeContext(client: client, state: state, reason: "composition_update"),
                handled: false
            )
            return false
        }

        let markedTextString = mode == .commitOnlyComposition
            ? Self.commitOnlyCompositionPlaceholder
            : markedDisplayText ?? ""
        guard !markedTextString.isEmpty else {
            clearOwnedMarkedTextIfNeeded(client: client, state: state)
            return false
        }
        let markedText = mode == .commitOnlyComposition
            ? InputClientMarkedText.placeholder(markedTextString)
            : InputClientMarkedText.composition(markedTextString)
        setOwnedMarkedText(
            markedText,
            selectionRange: mode == .commitOnlyComposition
                ? NSRange(location: 0, length: 0)
                : NSRange(location: (markedTextString as NSString).length, length: 0),
            client: client,
            state: state,
            reason: "composition_update",
            kind: mode == .commitOnlyComposition ? "setMarkedTextPlaceholder" : "setMarkedText"
        )
        return true
    }

    func candidatePanelPreeditDisplayText(
        client: InputControllerClient?,
        state: InputClientCompositionWriteState,
        markedDisplayText: String?
    ) -> String? {
        guard state.hasActiveComposition,
              writeMode(client: client, state: state) == .commitOnlyComposition,
              let markedDisplayText,
              !markedDisplayText.isEmpty else {
            return nil
        }
        return markedDisplayText
    }

    @discardableResult
    func clearOwnedMarkedTextIfNeeded(
        client: InputControllerClient?,
        state: InputClientCompositionWriteState
    ) -> Bool {
        guard let client,
              ownedMarkedTextClientID == client.feedbackTrackingID else {
            return false
        }
        clearMarkedText(client, state: state)
        return true
    }

    func finishLifecycle(shouldClearOwnedMarkedTextWhenEndingWithoutCommit: Bool) {
        if !shouldClearOwnedMarkedTextWhenEndingWithoutCommit || ownedMarkedTextClientID == nil {
            ownedMarkedTextClientID = nil
        }
    }

    private func clearMarkedText(
        _ client: InputControllerClient,
        state: InputClientCompositionWriteState
    ) {
        writeCoordinator.setMarkedText(
            .emptyAttributed(),
            selectionRange: NSRange(location: 0, length: 0),
            client: client,
            context: writeContext(client: client, state: state, reason: "clear_marked_text")
        )
        if ownedMarkedTextClientID == client.feedbackTrackingID {
            ownedMarkedTextClientID = nil
        }
    }

    private func setOwnedMarkedText(
        _ text: InputClientMarkedText,
        selectionRange: NSRange,
        client: InputControllerClient,
        state: InputClientCompositionWriteState,
        reason: String,
        kind: String
    ) {
        writeCoordinator.setMarkedText(
            text,
            selectionRange: selectionRange,
            client: client,
            context: writeContext(client: client, state: state, reason: reason),
            kind: kind
        )
        ownedMarkedTextClientID = client.feedbackTrackingID
    }

    private func writeContext(
        client: InputControllerClient?,
        state: InputClientCompositionWriteState,
        reason: String
    ) -> InputClientWriteContext {
        InputClientWriteContext(
            compositionID: state.compositionID,
            rawLength: state.rawLength,
            writeMode: writeMode(client: client, state: state),
            reason: reason
        )
    }
}
