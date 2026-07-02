import Foundation
import KnowTypeCore

struct InputClientWriteContext: Sendable, Equatable {
    var compositionID: Int
    var rawLength: Int
    var writeMode: InputClientWriteMode
    var reason: String
}

struct InputClientWriteCoordinator: Sendable {
    static let noOwnedReplacementRange = NSRange(location: NSNotFound, length: NSNotFound)

    func insertText(
        _ text: String,
        client: InputControllerClient?,
        context: InputClientWriteContext
    ) {
        let replacementRange = Self.noOwnedReplacementRange
        trace(
            kind: "insertText",
            client: client,
            chosenReplacementRange: replacementRange,
            context: context,
            handled: client != nil
        )
        client?.insertText(text, replacementRange: replacementRange)
    }

    func setMarkedText(
        _ text: InputClientMarkedText,
        selectionRange: NSRange,
        client: InputControllerClient,
        context: InputClientWriteContext,
        kind: String = "setMarkedText"
    ) {
        let replacementRange = Self.noOwnedReplacementRange
        trace(
            kind: kind,
            client: client,
            chosenReplacementRange: replacementRange,
            context: context,
            handled: true
        )
        client.setMarkedText(
            text,
            selectionRange: selectionRange,
            replacementRange: replacementRange
        )
    }

    func traceDecision(
        kind: String,
        client: InputControllerClient?,
        context: InputClientWriteContext,
        handled: Bool
    ) {
        trace(
            kind: kind,
            client: client,
            chosenReplacementRange: Self.noOwnedReplacementRange,
            context: context,
            handled: handled
        )
    }

    private func trace(
        kind: String,
        client: InputControllerClient?,
        chosenReplacementRange: NSRange,
        context: InputClientWriteContext,
        handled: Bool
    ) {
        _ = chosenReplacementRange
        InputDebugDiagnostics.emit(
            category: .clientWrite,
            fields: [
                .init(.stage, kind),
                .init(.compositionID, context.compositionID),
                .init(.rawLength, context.rawLength),
                .init(.bundleID, client?.bundleIdentifier ?? "unknown"),
                .init(.writeMode, context.writeMode.rawValue),
                .init(.handled, handled),
                .init(.reason, context.reason)
            ]
        )
    }
}
