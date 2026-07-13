import CoreGraphics
import Foundation
import KnowTypeAI
import KnowTypeCore
@testable import KnowTypeInputMethod
import XCTest

final class InputCommitApplicationRuntimeTests: XCTestCase {
    func testPlanMatchesCommitResultPolicy() {
        let runtime = InputCommitApplicationRuntime()

        XCTAssertEqual(runtime.plan(for: .commit("你"), hasComposition: true), .insertAndReset("你"))
        XCTAssertEqual(runtime.plan(for: .noAction, hasComposition: true), .noAction(consume: true))
        XCTAssertEqual(runtime.plan(for: .noAction, hasComposition: false), .noAction(consume: false))
    }

    func testAcceptedFeedbackContextPreservesInputs() {
        let runtime = InputCommitApplicationRuntime()
        let client = FakeCommitApplicationClient(bundleIdentifier: "com.example.editor")
        let candidate = aiCandidate(displayText: "我觉得可以继续")

        let context = runtime.acceptedFeedbackContext(
            text: "我觉得可以继续",
            schemaID: "luna_pinyin",
            appBundleID: client.bundleIdentifier,
            acceptedAIRecommendation: candidate,
            client: client
        )

        XCTAssertEqual(context.text, "我觉得可以继续")
        XCTAssertEqual(context.schemaID, "luna_pinyin")
        XCTAssertEqual(context.appBundleID, "com.example.editor")
        XCTAssertEqual(context.acceptedAIRecommendation, candidate)
        XCTAssertTrue(context.client === client)
    }

    func testSideEffectContextsPreserveCommitFactsFromCompositionSnapshot() {
        let runtime = InputCommitApplicationRuntime()
        let client = FakeCommitApplicationClient(bundleIdentifier: "com.example.editor")
        let acceptID = UUID()
        let candidate = aiCandidate(displayText: "我觉得可以继续")
        let snapshot = compositionSnapshot(rawInput: "wojuede", compositionID: 42, deleteCountBeforeCommit: 2)

        let contexts = runtime.sideEffectContexts(
            text: "我觉得可以继续",
            schemaID: "luna_pinyin",
            appBundleID: client.bundleIdentifier,
            acceptedAIRecommendation: candidate,
            acceptID: acceptID,
            selectedNativeCandidateSource: "rime:selected",
            prefixCandidateSource: "rime:first",
            compositionSnapshot: snapshot,
            client: client
        )

        XCTAssertEqual(contexts.aiAcceptance.text, "我觉得可以继续")
        XCTAssertEqual(contexts.aiAcceptance.rawInput, "wojuede")
        XCTAssertEqual(contexts.aiAcceptance.schemaID, "luna_pinyin")
        XCTAssertEqual(contexts.aiAcceptance.appBundleID, "com.example.editor")
        XCTAssertEqual(contexts.aiAcceptance.acceptedAIRecommendation, candidate)
        XCTAssertEqual(contexts.aiAcceptance.acceptID, acceptID)
        XCTAssertEqual(contexts.aiAcceptance.selectedNativeCandidateSource, "rime:selected")
        XCTAssertEqual(contexts.aiAcceptance.prefixCandidateSource, "rime:first")
        XCTAssertEqual(contexts.aiAcceptance.deleteCountBeforeCommit, 2)
        XCTAssertTrue(contexts.aiAcceptance.client === client)

        XCTAssertEqual(contexts.lexicalCommit.text, "我觉得可以继续")
        XCTAssertEqual(contexts.lexicalCommit.schemaID, "luna_pinyin")
        XCTAssertEqual(contexts.lexicalCommit.compositionID, 42)
    }

    private func compositionSnapshot(
        rawInput: String,
        compositionID: Int,
        deleteCountBeforeCommit: Int = 0
    ) -> InputCompositionStateSnapshot {
        InputCompositionStateSnapshot(
            rawInput: rawInput,
            compositionBuffer: CompositionBuffer(rawInput: rawInput),
            compositionID: compositionID,
            rawRevision: 3,
            deleteCountBeforeCommit: deleteCountBeforeCommit
        )
    }

    private func aiCandidate(displayText: String) -> AIRecommendationCandidate {
        AIRecommendationCandidate(
            prefixText: "我觉得",
            continuationText: "可以继续",
            displayText: displayText,
            confidence: 0.9,
            provider: "test",
            contextVersion: "v1"
        )
    }
}

private final class FakeCommitApplicationClient: InputControllerClient, @unchecked Sendable {
    var bundleIdentifier: String?
    var selectedRange = NSRange(location: 0, length: 0)
    var markedRange: NSRange?

    init(bundleIdentifier: String?) {
        self.bundleIdentifier = bundleIdentifier
    }

    func firstRect(forCharacterRange _: NSRange) -> CGRect {
        .zero
    }

    func lineHeightRect(forCharacterIndex _: Int) -> CGRect {
        .zero
    }

    func setMarkedText(
        _: InputClientMarkedText,
        selectionRange _: NSRange,
        replacementRange _: NSRange
    ) {}

    func insertText(_: String, replacementRange _: NSRange) {}
}
