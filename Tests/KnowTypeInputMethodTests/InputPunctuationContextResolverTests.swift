import CoreGraphics
import Foundation
import XCTest
@testable import KnowTypeInputMethod

final class InputPunctuationContextResolverTests: XCTestCase {
    func testUsesClientCharacterWhenAvailable() {
        var resolver = InputPunctuationContextResolver()
        let client = PunctuationContextClient()
        client.selectedRangeValue = NSRange(location: 4, length: 0)
        client.characterBeforeCaretValue = "9"

        XCTAssertEqual(
            resolver.resolve(client: client, hasActiveComposition: false),
            InputPreviousCharacterContext(kind: .asciiDigit, source: .client)
        )
    }

    func testUsesRecordedInsertionOnlyAtExpectedCaret() {
        var resolver = InputPunctuationContextResolver()
        let client = PunctuationContextClient()
        client.selectedRangeValue = NSRange(location: 10, length: 0)
        resolver.recordInsertion(
            "1",
            client: client,
            selectedRangeBeforeInsertion: client.selectedRangeValue
        )

        client.selectedRangeValue = NSRange(location: 11, length: 0)
        XCTAssertEqual(
            resolver.resolve(client: client, hasActiveComposition: false),
            InputPreviousCharacterContext(kind: .asciiDigit, source: .recordedInsertion)
        )

        client.selectedRangeValue = NSRange(location: 12, length: 0)
        XCTAssertEqual(
            resolver.resolve(client: client, hasActiveComposition: false),
            InputPreviousCharacterContext(kind: .unknown, source: .unavailable)
        )
    }

    func testSelectionAndActiveCompositionDisableContext() {
        var resolver = InputPunctuationContextResolver()
        let client = PunctuationContextClient()
        client.characterBeforeCaretValue = "7"
        client.selectedRangeValue = NSRange(location: 3, length: 1)

        XCTAssertEqual(
            resolver.resolve(client: client, hasActiveComposition: false),
            InputPreviousCharacterContext(kind: .unknown, source: .unavailable)
        )

        client.selectedRangeValue = NSRange(location: 3, length: 0)
        XCTAssertEqual(
            resolver.resolve(client: client, hasActiveComposition: true),
            InputPreviousCharacterContext(kind: .unknown, source: .activeComposition)
        )
    }
}

private final class PunctuationContextClient: InputControllerClient, @unchecked Sendable {
    var bundleIdentifier: String? = "com.example.punctuation-context"
    var selectedRangeValue = NSRange(location: 0, length: 0)
    var characterBeforeCaretValue: Character?

    var selectedRange: NSRange { selectedRangeValue }
    var markedRange: NSRange? { nil }

    func characterBeforeCaret() -> Character? { characterBeforeCaretValue }
    func firstRect(forCharacterRange _: NSRange) -> CGRect { .zero }
    func lineHeightRect(forCharacterIndex _: Int) -> CGRect { .zero }
    func setMarkedText(_: InputClientMarkedText, selectionRange _: NSRange, replacementRange _: NSRange) {}
    func insertText(_: String, replacementRange _: NSRange) {}
}
