import Foundation
import KnowTypeCore

protocol InputControllerClient: AnyObject, Sendable, InputClientGeometryProviding {
    var bundleIdentifier: String? { get }

    func setMarkedText(
        _ text: String,
        selectionRange: NSRange,
        replacementRange: NSRange
    )
    func insertText(_ text: String, replacementRange: NSRange)
}

protocol InputControllerHost: AnyObject {
    var currentClient: InputControllerClient? { get }

    func updateComposition()
    func updateCandidatePanel(state: CandidatePanelState, locale: KnowTypeLocale)
    func hideCandidatePanel()
    func scheduleDelayedReanchor(_ operation: @escaping @Sendable () -> Void)
}

protocol InputControllerUserSelectionHistoryPersisting: AnyObject, Sendable {
    func loadHistory(maxEntries: Int) -> [String]
    func recordSelection(
        _ text: String,
        currentHistory: [String],
        maxEntries: Int
    ) -> [String]
    func flushHistory(_ currentHistory: [String], maxEntries: Int)
}

extension UserSelectionHistoryPersistence: InputControllerUserSelectionHistoryPersisting {}

#if canImport(InputMethodKit)
@preconcurrency import InputMethodKit

final class IMKInputControllerClientAdapter: InputControllerClient, @unchecked Sendable {
    private let client: IMKTextInput

    init(client: IMKTextInput) {
        self.client = client
    }

    var bundleIdentifier: String? {
        client.bundleIdentifier()
    }

    var selectedRange: NSRange {
        client.selectedRange()
    }

    var markedRange: NSRange? {
        let range = client.markedRange()
        guard range.location != NSNotFound,
              range.length != NSNotFound else {
            return nil
        }
        return range
    }

    func firstRect(forCharacterRange range: NSRange) -> CGRect {
        client.firstRect(forCharacterRange: range, actualRange: nil)
    }

    func lineHeightRect(forCharacterIndex index: Int) -> CGRect {
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: index, lineHeightRectangle: &rect)
        return rect
    }

    func setMarkedText(
        _ text: String,
        selectionRange: NSRange,
        replacementRange: NSRange
    ) {
        client.setMarkedText(
            text,
            selectionRange: selectionRange,
            replacementRange: replacementRange
        )
    }

    func insertText(_ text: String, replacementRange: NSRange) {
        client.insertText(text, replacementRange: replacementRange)
    }
}
#endif
