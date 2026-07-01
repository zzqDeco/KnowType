import Foundation
import KnowTypeCore

struct InputSuggestionStateSnapshot: Sendable, Equatable {
    var suggestion: SuggestionResponse?
    var rawInput: String?
}

struct InputSuggestionCommitSnapshot: Sendable, Equatable {
    var suggestion: SuggestionResponse?
    var rawInput: String?
    var usesPendingFallback: Bool
}

final class InputSuggestionStateRuntime: @unchecked Sendable {
    private var suggestion: SuggestionResponse?
    private var rawInput: String?

    func store(suggestion: SuggestionResponse, rawInput: String) {
        self.suggestion = suggestion
        self.rawInput = rawInput
    }

    func clear() {
        suggestion = nil
        rawInput = nil
    }

    func invalidate() {
        clear()
    }

    func currentSnapshot() -> InputSuggestionStateSnapshot {
        InputSuggestionStateSnapshot(
            suggestion: suggestion,
            rawInput: rawInput
        )
    }

    func hasCurrentSuggestion(rawInput currentRawInput: String) -> Bool {
        SuggestionPublicationGuard.hasCurrentSuggestion(
            suggestionRawInput: rawInput,
            currentRawInput: currentRawInput
        )
    }

    func commitSnapshot(
        action _: InputAction,
        rawInput _: String,
        asyncEnabled _: Bool
    ) -> InputSuggestionCommitSnapshot {
        InputSuggestionCommitSnapshot(
            suggestion: suggestion,
            rawInput: rawInput,
            usesPendingFallback: false
        )
    }

    @discardableResult
    func clearNoProviderFallbackContinuationsIfNeeded(hasKnownProvider: Bool) -> Bool {
        guard hasKnownProvider,
              let currentSuggestion = suggestion,
              currentSuggestion.lockedPrefix?.candidateID == "composition-buffer",
              !currentSuggestion.continuationCandidates.isEmpty else {
            return false
        }
        suggestion = SuggestionResponse(
            prefixCandidates: currentSuggestion.prefixCandidates,
            lockedPrefix: currentSuggestion.lockedPrefix,
            continuationCandidates: [],
            latencyMs: currentSuggestion.latencyMs
        )
        return true
    }
}
