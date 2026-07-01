import Foundation

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
        guard ProcessInfo.processInfo.environment["KNOWTYPE_CLIENT_WRITE_DEBUG"] == "1" else {
            return
        }
        let message = "KnowType client write: kind=\(kind) " +
            "compositionID=\(context.compositionID) rawLength=\(context.rawLength) " +
            "bundleID=\(client?.bundleIdentifier ?? "<unknown>") " +
            "writeMode=\(context.writeMode.rawValue) handled=\(handled) " +
            "selectedRange=\(Self.describeRange(client?.selectedRange)) " +
            "reportedMarkedRange=\(Self.describeRange(client?.markedRange)) " +
            "chosenReplacementRange=\(Self.describeRange(chosenReplacementRange)) " +
            "reason=\(context.reason)\n"
        fputs(message, stderr)
    }

    private static func describeRange(_ range: NSRange?) -> String {
        guard let range else {
            return "nil"
        }
        if range.location == NSNotFound {
            return "{NSNotFound,\(range.length)}"
        }
        return "{\(range.location),\(range.length)}"
    }
}
