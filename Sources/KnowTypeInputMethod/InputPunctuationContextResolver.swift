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
}

struct InputPunctuationContextResolver: Sendable {
    private struct RecordedInsertion: Sendable {
        var clientID: ObjectIdentifier
        var expectedCaretLocation: Int
        var characterKind: InputPreviousCharacterKind
    }

    private var recordedInsertion: RecordedInsertion?

    mutating func resolve(
        client: InputControllerClient?,
        hasActiveComposition: Bool
    ) -> InputPreviousCharacterContext {
        guard !hasActiveComposition else {
            return InputPreviousCharacterContext(kind: .unknown, source: .activeComposition)
        }
        guard let client else {
            return InputPreviousCharacterContext(kind: .unknown, source: .unavailable)
        }
        let selectedRange = client.selectedRange
        guard Self.isKnownCollapsedRange(selectedRange) else {
            return InputPreviousCharacterContext(kind: .unknown, source: .unavailable)
        }
        if let character = client.characterBeforeCaret() {
            return InputPreviousCharacterContext(
                kind: Self.characterKind(character),
                source: .client
            )
        }
        if let recordedInsertion,
           recordedInsertion.clientID == client.feedbackTrackingID,
           recordedInsertion.expectedCaretLocation == selectedRange.location {
            return InputPreviousCharacterContext(
                kind: recordedInsertion.characterKind,
                source: .recordedInsertion
            )
        }
        return InputPreviousCharacterContext(kind: .unknown, source: .unavailable)
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
            recordedInsertion = nil
            return
        }
        recordedInsertion = RecordedInsertion(
            clientID: client.feedbackTrackingID,
            expectedCaretLocation: selectedRangeBeforeInsertion.location + (text as NSString).length,
            characterKind: Self.characterKind(character)
        )
    }

    mutating func invalidate() {
        recordedInsertion = nil
    }

    private static func characterKind(_ character: Character) -> InputPreviousCharacterKind {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              scalar.value >= 48,
              scalar.value <= 57 else {
            return .other
        }
        return .asciiDigit
    }

    private static func isKnownCollapsedRange(_ range: NSRange) -> Bool {
        isKnownRange(range) && range.length == 0
    }

    private static func isKnownRange(_ range: NSRange) -> Bool {
        range.location != NSNotFound && range.length != NSNotFound
    }
}
