import Foundation

public enum SuggestionRefreshPolicy {
    public static func shouldRefresh(rawInput: String) -> Bool {
        !rawInput.isEmpty
    }
}
