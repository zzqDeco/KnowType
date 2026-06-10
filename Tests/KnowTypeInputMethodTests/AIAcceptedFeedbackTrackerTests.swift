import CoreGraphics
import Foundation
import KnowTypeAI
@testable import KnowTypeInputMethod
import XCTest

final class AIAcceptedFeedbackTrackerTests: XCTestCase {
    func testDeleteInsideVerifiedAcceptedSpanRecordsFeedback() async throws {
        let store = AIAcceptedFeedbackStore.inMemory()
        let tracker = AIAcceptedFeedbackTracker(
            recorder: store,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            debounceNanoseconds: 0
        )
        let client = FeedbackTrackerClient(selectedRange: NSRange(location: 10, length: 0))
        let acceptedText = "这个方案需要继续推进"

        let acceptID = UUID()
        XCTAssertTrue(
            tracker.armAcceptedSpan(
                acceptID: acceptID,
                acceptedText: acceptedText,
                schemaID: "pinyin_simp",
                appBundleID: "com.apple.TextEdit",
                provider: "test-provider",
                contextVersion: "ctx",
                client: client
            )
        )
        client.selectedRangeValue = NSRange(location: 10 + (acceptedText as NSString).length, length: 0)
        tracker.verifyPostInsertCaret(client: client)

        XCTAssertTrue(tracker.observeDeleteBackward(client: client))
        try await Task.sleep(nanoseconds: 50_000_000)

        let records = store.allRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].acceptID, acceptID)
        XCTAssertEqual(records[0].deletedTexts, ["进"])
        XCTAssertEqual(records[0].deletedRanges.first?.location, 10 + (acceptedText as NSString).length - 1)
    }

    func testMovedCursorCancelsTrackingWithoutFeedback() async throws {
        let store = AIAcceptedFeedbackStore.inMemory()
        let tracker = AIAcceptedFeedbackTracker(
            recorder: store,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            debounceNanoseconds: 0
        )
        let client = FeedbackTrackerClient(selectedRange: NSRange(location: 4, length: 0))
        let acceptedText = "这个方案"
        _ = tracker.armAcceptedSpan(
            acceptID: UUID(),
            acceptedText: acceptedText,
            schemaID: "pinyin_simp",
            appBundleID: "com.apple.TextEdit",
            provider: "test-provider",
            contextVersion: "ctx",
            client: client
        )
        client.selectedRangeValue = NSRange(location: 4 + (acceptedText as NSString).length, length: 0)
        tracker.verifyPostInsertCaret(client: client)

        client.selectedRangeValue = NSRange(location: 1, length: 0)
        XCTAssertFalse(tracker.observeDeleteBackward(client: client))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(store.allRecords().isEmpty)
    }

    func testUnverifiedPreInsertRangeDoesNotArmTracker() async throws {
        let store = AIAcceptedFeedbackStore.inMemory()
        let tracker = AIAcceptedFeedbackTracker(
            recorder: store,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            debounceNanoseconds: 0
        )
        let client = FeedbackTrackerClient(selectedRange: NSRange(location: 4, length: 2))

        XCTAssertFalse(
            tracker.armAcceptedSpan(
                acceptID: UUID(),
                acceptedText: "这个方案",
                schemaID: "pinyin_simp",
                appBundleID: "com.apple.TextEdit",
                provider: "test-provider",
                contextVersion: "ctx",
                client: client
            )
        )
        client.selectedRangeValue = NSRange(location: 8, length: 0)
        XCTAssertFalse(tracker.observeDeleteBackward(client: client))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(store.allRecords().isEmpty)
    }
}

private final class FeedbackTrackerClient: InputControllerClient, @unchecked Sendable {
    var selectedRangeValue: NSRange
    var bundleIdentifier: String? = "com.apple.TextEdit"
    var markedRange: NSRange?

    init(selectedRange: NSRange) {
        selectedRangeValue = selectedRange
    }

    var selectedRange: NSRange {
        selectedRangeValue
    }

    func firstRect(forCharacterRange _: NSRange) -> CGRect {
        .zero
    }

    func lineHeightRect(forCharacterIndex _: Int) -> CGRect {
        .zero
    }

    func setMarkedText(_: String, selectionRange _: NSRange, replacementRange _: NSRange) {}

    func insertText(_: String, replacementRange _: NSRange) {}
}
