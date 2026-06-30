import KnowTypeCore
@testable import KnowTypeInputMethod
import XCTest

final class InputSuggestionStateRuntimeTests: XCTestCase {
    func testStoreThenCurrentSnapshotReturnsSuggestionAndRawInput() {
        let runtime = InputSuggestionStateRuntime()
        let suggestion = makeSuggestion(rawInput: "ni")

        runtime.store(suggestion: suggestion, rawInput: "ni")

        XCTAssertEqual(
            runtime.currentSnapshot(),
            InputSuggestionStateSnapshot(suggestion: suggestion, rawInput: "ni")
        )
        XCTAssertTrue(runtime.hasCurrentSuggestion(rawInput: "ni"))
    }

    func testRawInputMismatchIsNotCurrentSuggestion() {
        let runtime = InputSuggestionStateRuntime()
        runtime.store(suggestion: makeSuggestion(rawInput: "ni"), rawInput: "ni")

        XCTAssertFalse(runtime.hasCurrentSuggestion(rawInput: "nin"))
    }

    func testClearAndInvalidateDropSuggestionAndRawInput() {
        let runtime = InputSuggestionStateRuntime()
        runtime.store(suggestion: makeSuggestion(rawInput: "ni"), rawInput: "ni")

        runtime.clear()

        XCTAssertEqual(runtime.currentSnapshot(), InputSuggestionStateSnapshot(suggestion: nil, rawInput: nil))

        runtime.store(suggestion: makeSuggestion(rawInput: "wo"), rawInput: "wo")
        runtime.invalidate()

        XCTAssertEqual(runtime.currentSnapshot(), InputSuggestionStateSnapshot(suggestion: nil, rawInput: nil))
    }

    func testCommitSnapshotReturnsStoredSuggestionWithoutPendingFallback() {
        let runtime = InputSuggestionStateRuntime()
        let suggestion = makeSuggestion(rawInput: "ni")
        runtime.store(suggestion: suggestion, rawInput: "ni")

        let snapshot = runtime.commitSnapshot(
            action: .tab,
            rawInput: "ni",
            asyncEnabled: true
        )

        XCTAssertEqual(snapshot.suggestion, suggestion)
        XCTAssertEqual(snapshot.rawInput, "ni")
        XCTAssertFalse(snapshot.usesPendingFallback)
    }

    func testCommitSnapshotForStaleSuggestionDoesNotCreateFallback() {
        let runtime = InputSuggestionStateRuntime()
        let suggestion = makeSuggestion(rawInput: "ni")
        runtime.store(suggestion: suggestion, rawInput: "ni")

        let snapshot = runtime.commitSnapshot(
            action: .tab,
            rawInput: "nin",
            asyncEnabled: true
        )

        XCTAssertEqual(snapshot.suggestion, suggestion)
        XCTAssertEqual(snapshot.rawInput, "ni")
        XCTAssertFalse(snapshot.usesPendingFallback)
    }

    func testKnownProviderClearsResolvedCompositionFallbackContinuations() {
        let runtime = InputSuggestionStateRuntime()
        let suggestion = makeSuggestion(
            rawInput: "ni",
            lockedPrefixCandidateID: "composition-buffer",
            continuations: [
                ContinuationCandidate(
                    text: "继续",
                    lengthLevel: .medium,
                    confidence: 0.5,
                    provider: "local-fallback"
                )
            ],
            latencyMs: 17
        )
        runtime.store(suggestion: suggestion, rawInput: "ni")

        XCTAssertTrue(runtime.clearNoProviderFallbackContinuationsIfNeeded(hasKnownProvider: true))

        let updated = runtime.currentSnapshot().suggestion
        XCTAssertEqual(updated?.prefixCandidates, suggestion.prefixCandidates)
        XCTAssertEqual(updated?.lockedPrefix, suggestion.lockedPrefix)
        XCTAssertEqual(updated?.continuationCandidates, [])
        XCTAssertEqual(updated?.latencyMs, 17)
    }

    func testFallbackContinuationClearIsSkippedWhenNotApplicable() {
        let runtime = InputSuggestionStateRuntime()
        let suggestion = makeSuggestion(
            rawInput: "ni",
            lockedPrefixCandidateID: "rime",
            continuations: [
                ContinuationCandidate(
                    text: "继续",
                    lengthLevel: .short,
                    confidence: 0.4,
                    provider: "local-fallback"
                )
            ]
        )
        runtime.store(suggestion: suggestion, rawInput: "ni")

        XCTAssertFalse(runtime.clearNoProviderFallbackContinuationsIfNeeded(hasKnownProvider: false))
        XCTAssertEqual(runtime.currentSnapshot().suggestion, suggestion)
        XCTAssertFalse(runtime.clearNoProviderFallbackContinuationsIfNeeded(hasKnownProvider: true))
        XCTAssertEqual(runtime.currentSnapshot().suggestion, suggestion)

        runtime.store(suggestion: makeSuggestion(rawInput: "wo", lockedPrefixCandidateID: "composition-buffer"), rawInput: "wo")
        XCTAssertFalse(runtime.clearNoProviderFallbackContinuationsIfNeeded(hasKnownProvider: true))
    }

    private func makeSuggestion(
        rawInput: String,
        lockedPrefixCandidateID: String? = nil,
        continuations: [ContinuationCandidate] = [],
        latencyMs: Int = 3
    ) -> SuggestionResponse {
        SuggestionResponse(
            prefixCandidates: [
                CorrectionCandidate(
                    text: "你",
                    source: "rime",
                    confidence: 1,
                    correctionLevel: .none,
                    rawRange: TextRange(start: 0, length: rawInput.count)
                )
            ],
            lockedPrefix: lockedPrefixCandidateID.map {
                LockedPrefix(text: "你", rawInput: rawInput, candidateID: $0)
            },
            continuationCandidates: continuations,
            latencyMs: latencyMs
        )
    }
}
