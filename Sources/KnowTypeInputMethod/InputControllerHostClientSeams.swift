import Foundation
import KnowTypeCore

struct InputClientMarkedText: @unchecked Sendable {
    static let tsmUnderlineAttribute = NSAttributedString.Key("NSUnderline")
    static let tsmMarkedClauseSegmentAttribute = NSAttributedString.Key("NSMarkedClauseSegment")

    private enum Storage {
        case plain(String)
        case attributed(NSAttributedString)
    }

    private let storage: Storage

    var string: String {
        switch storage {
        case .plain(let text):
            return text
        case .attributed(let text):
            return text.string
        }
    }

    var isAttributed: Bool {
        if case .attributed = storage {
            return true
        }
        return false
    }

    var attributeKeyNames: Set<String> {
        guard case .attributed(let text) = storage,
              text.length > 0 else {
            return []
        }
        var names: Set<String> = []
        text.enumerateAttributes(
            in: NSRange(location: 0, length: text.length),
            options: []
        ) { attributes, _, _ in
            attributes.keys.forEach { names.insert($0.rawValue) }
        }
        return names
    }

    var imkObject: Any {
        switch storage {
        case .plain(let text):
            return text
        case .attributed(let text):
            return text
        }
    }

    static func plain(_ text: String) -> InputClientMarkedText {
        InputClientMarkedText(storage: .plain(text))
    }

    static func attributed(_ text: NSAttributedString) -> InputClientMarkedText {
        InputClientMarkedText(storage: .attributed(text))
    }

    static func emptyAttributed() -> InputClientMarkedText {
        .attributed(NSAttributedString())
    }

    static func composition(_ text: String) -> InputClientMarkedText {
        .attributed(markedAttributedString(text))
    }

    static func placeholder(_ text: String) -> InputClientMarkedText {
        .attributed(markedAttributedString(text))
    }

    private static func markedAttributedString(_ text: String) -> NSAttributedString {
        let range = NSRange(location: 0, length: (text as NSString).length)
        let attributedText = NSMutableAttributedString(string: text)
        if range.length > 0 {
            attributedText.setAttributes(
                [
                    tsmUnderlineAttribute: 1,
                    tsmMarkedClauseSegmentAttribute: 0
                ],
                range: range
            )
        }
        return attributedText
    }
}

protocol InputControllerClient: AnyObject, Sendable, InputClientGeometryProviding {
    var bundleIdentifier: String? { get }
    var feedbackTrackingID: ObjectIdentifier { get }

    func setMarkedText(
        _ text: InputClientMarkedText,
        selectionRange: NSRange,
        replacementRange: NSRange
    )
    func insertText(_ text: String, replacementRange: NSRange)
}

extension InputControllerClient {
    var feedbackTrackingID: ObjectIdentifier {
        ObjectIdentifier(self)
    }
}

protocol InputControllerHost: AnyObject {
    var currentClient: InputControllerClient? { get }

    func updateComposition()
    func applyCandidatePanelFrame(_ frame: CandidatePanelFrame, locale: KnowTypeLocale)
    func scheduleDelayedReanchor(_ operation: @escaping @Sendable () -> Void)
    func schedulePostInsertCaretVerification(_ operation: @escaping @Sendable () -> Void)
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

    var feedbackTrackingID: ObjectIdentifier {
        ObjectIdentifier(client as AnyObject)
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
        _ text: InputClientMarkedText,
        selectionRange: NSRange,
        replacementRange: NSRange
    ) {
        client.setMarkedText(
            text.imkObject,
            selectionRange: selectionRange,
            replacementRange: replacementRange
        )
    }

    func insertText(_ text: String, replacementRange: NSRange) {
        client.insertText(text, replacementRange: replacementRange)
    }
}
#endif
