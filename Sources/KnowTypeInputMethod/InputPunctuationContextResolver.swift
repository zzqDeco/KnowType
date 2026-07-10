import Foundation

enum InputPunctuationContextSource: String, Sendable, Equatable {
    case client
    case recordedInsertion
    case unavailable
    case activeComposition
}

struct InputPreviousCharacterContext: Sendable, Equatable {
    var kind: InputPreviousCharacterKind
    var source: InputPunctuationContextSource

    var quoteContext: InputQuoteContext {
        switch kind {
        case .whitespace, .openingPunctuation:
            return .opening
        case .asciiDigit, .closingPunctuation, .text:
            return .closing
        case .unknown:
            return .unknown
        }
    }
}

struct InputPunctuationContextResolution: Sendable, Equatable {
    var previousCharacter: InputPreviousCharacterContext
    var didSelectionOrFocusChange: Bool
}

struct InputPunctuationContextResolver: Sendable {
    private struct RecordedInsertion: Sendable {
        var clientID: ObjectIdentifier
        var expectedCaretLocation: Int
        var characterKind: InputPreviousCharacterKind
    }

    private var recordedInsertion: RecordedInsertion?
    private var observedClientID: ObjectIdentifier?
    private var expectedCaretLocation: Int?

    mutating func resolve(
        client: InputControllerClient?,
        hasActiveComposition: Bool,
        readsCharacterBeforeCaret: Bool = true
    ) -> InputPunctuationContextResolution {
        let didSelectionOrFocusChange = contextDidChange(client: client)
        guard !hasActiveComposition else {
            return InputPunctuationContextResolution(
                previousCharacter: InputPreviousCharacterContext(kind: .text, source: .activeComposition),
                didSelectionOrFocusChange: didSelectionOrFocusChange
            )
        }
        guard let client else {
            return unavailableResolution(didSelectionOrFocusChange: didSelectionOrFocusChange)
        }
        let selectedRange = client.selectedRange
        guard Self.isKnownCollapsedRange(selectedRange) else {
            return unavailableResolution(didSelectionOrFocusChange: didSelectionOrFocusChange)
        }
        observedClientID = client.feedbackTrackingID
        expectedCaretLocation = selectedRange.location
        if selectedRange.location == 0 {
            return InputPunctuationContextResolution(
                previousCharacter: InputPreviousCharacterContext(
                    kind: .openingPunctuation,
                    source: .client
                ),
                didSelectionOrFocusChange: didSelectionOrFocusChange
            )
        }
        if readsCharacterBeforeCaret,
           let character = client.characterBeforeCaret() {
            return InputPunctuationContextResolution(
                previousCharacter: InputPreviousCharacterContext(
                    kind: Self.characterKind(character),
                    source: .client
                ),
                didSelectionOrFocusChange: didSelectionOrFocusChange
            )
        }
        if let recordedInsertion,
           recordedInsertion.clientID == client.feedbackTrackingID,
           recordedInsertion.expectedCaretLocation == selectedRange.location {
            return InputPunctuationContextResolution(
                previousCharacter: InputPreviousCharacterContext(
                    kind: recordedInsertion.characterKind,
                    source: .recordedInsertion
                ),
                didSelectionOrFocusChange: didSelectionOrFocusChange
            )
        }
        return unavailableResolution(didSelectionOrFocusChange: didSelectionOrFocusChange)
    }

    mutating func recordInsertion(
        _ text: String,
        client: InputControllerClient?,
        selectedRangeBeforeInsertion: NSRange?
    ) {
        guard let client,
              let selectedRangeBeforeInsertion,
              Self.isKnownRange(selectedRangeBeforeInsertion),
              let character = text.last else {
            invalidate()
            return
        }
        recordedInsertion = RecordedInsertion(
            clientID: client.feedbackTrackingID,
            expectedCaretLocation: selectedRangeBeforeInsertion.location + (text as NSString).length,
            characterKind: Self.characterKind(character)
        )
        observedClientID = client.feedbackTrackingID
        expectedCaretLocation = selectedRangeBeforeInsertion.location + (text as NSString).length
    }

    mutating func invalidate() {
        recordedInsertion = nil
        observedClientID = nil
        expectedCaretLocation = nil
    }

    private mutating func contextDidChange(client: InputControllerClient?) -> Bool {
        guard observedClientID != nil || expectedCaretLocation != nil else {
            return false
        }
        guard let client,
              observedClientID == client.feedbackTrackingID,
              let expectedCaretLocation,
              Self.isKnownCollapsedRange(client.selectedRange),
              client.selectedRange.location == expectedCaretLocation else {
            recordedInsertion = nil
            observedClientID = nil
            expectedCaretLocation = nil
            return true
        }
        return false
    }

    private func unavailableResolution(
        didSelectionOrFocusChange: Bool
    ) -> InputPunctuationContextResolution {
        InputPunctuationContextResolution(
            previousCharacter: InputPreviousCharacterContext(kind: .unknown, source: .unavailable),
            didSelectionOrFocusChange: didSelectionOrFocusChange
        )
    }

    private static func characterKind(_ character: Character) -> InputPreviousCharacterKind {
        if character.isWhitespace {
            return .whitespace
        }
        guard let scalar = character.unicodeScalars.last else {
            return .unknown
        }
        if (48...57).contains(scalar.value) || (0xFF10...0xFF19).contains(scalar.value) {
            return .asciiDigit
        }
        switch scalar.properties.generalCategory {
        case .openPunctuation, .initialPunctuation:
            return .openingPunctuation
        case .closePunctuation, .finalPunctuation:
            return .closingPunctuation
        default:
            return .text
        }
    }

    private static func isKnownCollapsedRange(_ range: NSRange) -> Bool {
        isKnownRange(range) && range.length == 0
    }

    private static func isKnownRange(_ range: NSRange) -> Bool {
        range.location != NSNotFound && range.length != NSNotFound
    }
}
