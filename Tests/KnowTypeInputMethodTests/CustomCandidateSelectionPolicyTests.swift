import XCTest
import KnowTypeCore
@testable import KnowTypeInputMethod

final class CustomCandidateSelectionPolicyTests: XCTestCase {
    private let policy = CustomCandidateSelectionPolicy()

    func testVisiblePrefixDigitCommitsMatchingCandidate() {
        XCTAssertEqual(
            policy.decision(
                for: InputKeyStroke(text: "2", keyCode: 19),
                rawInput: "wo jue",
                suggestion: suggestion(prefixCount: 3),
                suggestionRawInput: "wo jue"
            ),
            .commitPrefixCandidate(1)
        )
    }

    func testZeroCommitsRawInputWhenSuggestionIsCurrent() {
        XCTAssertEqual(
            policy.decision(
                for: InputKeyStroke(text: "0", keyCode: 29),
                rawInput: "wo jue",
                suggestion: suggestion(prefixCount: 1),
                suggestionRawInput: "wo jue"
            ),
            .commitRawInput
        )
    }

    func testShiftedDigitPassesThrough() {
        XCTAssertEqual(
            policy.decision(
                for: InputKeyStroke(text: "!", keyCode: 18),
                rawInput: "wo jue",
                suggestion: suggestion(prefixCount: 3),
                suggestionRawInput: "wo jue"
            ),
            .passThrough
        )
    }

    func testUnmappedPrefixDigitPassesThrough() {
        XCTAssertEqual(
            policy.decision(
                for: InputKeyStroke(text: "4", keyCode: 21),
                rawInput: "wo jue",
                suggestion: suggestion(prefixCount: 3),
                suggestionRawInput: "wo jue"
            ),
            .passThrough
        )
    }

    func testOptionDigitPassesThroughToShortcutMapper() {
        XCTAssertEqual(
            policy.decision(
                for: InputKeyStroke(text: "1", keyCode: 18, modifiers: [.option]),
                rawInput: "wo jue",
                suggestion: suggestion(prefixCount: 3),
                suggestionRawInput: "wo jue"
            ),
            .passThrough
        )
    }

    private func suggestion(prefixCount: Int) -> SuggestionResponse {
        let prefixes = (0..<prefixCount).map { index in
            CorrectionCandidate(
                text: "prefix \(index)",
                source: "test",
                confidence: 0.9,
                correctionLevel: .contextual
            )
        }
        return SuggestionResponse(
            prefixCandidates: prefixes,
            lockedPrefix: nil,
            continuationCandidates: [],
            latencyMs: 1
        )
    }
}
