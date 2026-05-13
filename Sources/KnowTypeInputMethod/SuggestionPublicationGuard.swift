import Foundation

public enum SuggestionPublicationGuard {
    public static func shouldPublish(
        requestedRawInput: String,
        currentRawInput: String,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled && requestedRawInput == currentRawInput
    }

    public static func hasCurrentSuggestion(
        suggestionRawInput: String?,
        currentRawInput: String
    ) -> Bool {
        suggestionRawInput == currentRawInput
    }
}
