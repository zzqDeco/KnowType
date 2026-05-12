import Foundation

public enum SuggestionPublicationGuard {
    public static func shouldPublish(
        requestedRawInput: String,
        currentRawInput: String,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled && requestedRawInput == currentRawInput
    }
}
