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
            InputPunctuationContextResolution(
                previousCharacter: InputPreviousCharacterContext(kind: .asciiDigit, source: .client),
                didSelectionOrFocusChange: false
            )
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
            InputPunctuationContextResolution(
                previousCharacter: InputPreviousCharacterContext(kind: .asciiDigit, source: .recordedInsertion),
                didSelectionOrFocusChange: false
            )
        )

        client.selectedRangeValue = NSRange(location: 12, length: 0)
        XCTAssertEqual(
            resolver.resolve(client: client, hasActiveComposition: false),
            InputPunctuationContextResolution(
                previousCharacter: InputPreviousCharacterContext(kind: .unknown, source: .unavailable),
                didSelectionOrFocusChange: true
            )
        )
    }

    func testRecordedDigitCanResolveWithoutReadingClientCharacter() {
        var resolver = InputPunctuationContextResolver()
        let client = PunctuationContextClient()
        client.selectedRangeValue = NSRange(location: 4, length: 0)
        resolver.recordInsertion(
            "３",
            client: client,
            selectedRangeBeforeInsertion: client.selectedRangeValue
        )
        client.selectedRangeValue = NSRange(location: 5, length: 0)
        client.characterBeforeCaretValue = "文"

        let resolution = resolver.resolve(
            client: client,
            hasActiveComposition: false,
            readsCharacterBeforeCaret: false
        )

        XCTAssertEqual(resolution.previousCharacter.kind, .asciiDigit)
        XCTAssertEqual(resolution.previousCharacter.source, .recordedInsertion)
        XCTAssertEqual(client.characterBeforeCaretReadCount, 0)
    }

    func testSelectionAndActiveCompositionDisableContext() {
        var resolver = InputPunctuationContextResolver()
        let client = PunctuationContextClient()
        client.characterBeforeCaretValue = "7"
        client.selectedRangeValue = NSRange(location: 3, length: 1)

        XCTAssertEqual(
            resolver.resolve(client: client, hasActiveComposition: false),
            InputPunctuationContextResolution(
                previousCharacter: InputPreviousCharacterContext(kind: .unknown, source: .unavailable),
                didSelectionOrFocusChange: false
            )
        )

        client.selectedRangeValue = NSRange(location: 3, length: 0)
        XCTAssertEqual(
            resolver.resolve(client: client, hasActiveComposition: true),
            InputPunctuationContextResolution(
                previousCharacter: InputPreviousCharacterContext(kind: .text, source: .activeComposition),
                didSelectionOrFocusChange: false
            )
        )
    }

    func testQuoteContextClassifiesWhitespaceOpeningTextAndClosingPunctuation() {
        var resolver = InputPunctuationContextResolver()
        let client = PunctuationContextClient()
        client.selectedRangeValue = NSRange(location: 2, length: 0)

        for (character, expectedKind, expectedQuoteContext) in [
            (Character(" "), InputPreviousCharacterKind.whitespace, InputQuoteContext.opening),
            (Character("（"), .openingPunctuation, .opening),
            (Character("文"), .text, .closing),
            (Character("）"), .closingPunctuation, .closing)
        ] {
            client.characterBeforeCaretValue = character
            let resolution = resolver.resolve(client: client, hasActiveComposition: false)
            XCTAssertEqual(resolution.previousCharacter.kind, expectedKind)
            XCTAssertEqual(resolution.previousCharacter.quoteContext, expectedQuoteContext)
        }
    }

    func testKnownDocumentStartOpensQuoteWithoutReadingCharacter() {
        var resolver = InputPunctuationContextResolver()
        let client = PunctuationContextClient()

        let resolution = resolver.resolve(client: client, hasActiveComposition: false)

        XCTAssertEqual(resolution.previousCharacter.kind, .openingPunctuation)
        XCTAssertEqual(resolution.previousCharacter.quoteContext, .opening)
        XCTAssertEqual(client.characterBeforeCaretReadCount, 0)
    }

    func testSelectionAndFocusChangesAreReportedAgainstRecordedInsertion() {
        var resolver = InputPunctuationContextResolver()
        let firstClient = PunctuationContextClient()
        firstClient.selectedRangeValue = NSRange(location: 4, length: 0)
        resolver.recordInsertion(
            "“",
            client: firstClient,
            selectedRangeBeforeInsertion: firstClient.selectedRangeValue
        )

        firstClient.selectedRangeValue = NSRange(location: 2, length: 0)
        XCTAssertTrue(
            resolver.resolve(client: firstClient, hasActiveComposition: false)
                .didSelectionOrFocusChange
        )

        resolver.recordInsertion(
            "“",
            client: firstClient,
            selectedRangeBeforeInsertion: firstClient.selectedRangeValue
        )
        let secondClient = PunctuationContextClient()
        secondClient.selectedRangeValue = NSRange(location: 3, length: 0)
        XCTAssertTrue(
            resolver.resolve(client: secondClient, hasActiveComposition: false)
                .didSelectionOrFocusChange
        )
    }
}

private final class PunctuationContextClient: InputControllerClient, @unchecked Sendable {
    var bundleIdentifier: String? = "com.example.punctuation-context"
    var selectedRangeValue = NSRange(location: 0, length: 0)
    var characterBeforeCaretValue: Character?
    private(set) var characterBeforeCaretReadCount = 0

    var selectedRange: NSRange { selectedRangeValue }
    var markedRange: NSRange? { nil }

    func characterBeforeCaret() -> Character? {
        characterBeforeCaretReadCount += 1
        return characterBeforeCaretValue
    }
    func firstRect(forCharacterRange _: NSRange) -> CGRect { .zero }
    func lineHeightRect(forCharacterIndex _: Int) -> CGRect { .zero }
    func setMarkedText(_: InputClientMarkedText, selectionRange _: NSRange, replacementRange _: NSRange) {}
    func insertText(_: String, replacementRange _: NSRange) {}
}
