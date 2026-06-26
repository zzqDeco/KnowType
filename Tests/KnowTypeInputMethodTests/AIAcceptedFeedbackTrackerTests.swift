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

    func testMarkedRangeProvidesAcceptedSpanStartWhenCompositionIsActive() async throws {
        let store = AIAcceptedFeedbackStore.inMemory()
        let tracker = AIAcceptedFeedbackTracker(
            recorder: store,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            debounceNanoseconds: 0
        )
        let client = FeedbackTrackerClient(selectedRange: NSRange(location: 12, length: 0))
        client.markedRange = NSRange(location: 10, length: 2)
        let acceptedText = "这个方案需要继续推进"

        XCTAssertTrue(
            tracker.armAcceptedSpan(
                acceptID: UUID(),
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

        XCTAssertEqual(store.allRecords().count, 1)
        XCTAssertEqual(store.allRecords().first?.deletedTexts, ["进"])
    }

    func testTrackingOffsetRejectsDeletionInsideConfirmedPrefix() async throws {
        let store = AIAcceptedFeedbackStore.inMemory()
        let tracker = AIAcceptedFeedbackTracker(
            recorder: store,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            debounceNanoseconds: 0
        )
        let client = FeedbackTrackerClient(selectedRange: NSRange(location: 10, length: 0))
        let prefix = "我觉得这个方案"
        let suffix = "需要调整"
        let acceptedText = prefix + suffix
        let prefixLength = (prefix as NSString).length

        XCTAssertTrue(
            tracker.armAcceptedSpan(
                acceptID: UUID(),
                acceptedText: acceptedText,
                trackingText: suffix,
                trackingOffsetUTF16: prefixLength,
                schemaID: "pinyin_simp",
                appBundleID: "com.apple.TextEdit",
                provider: "test-provider",
                contextVersion: "ctx",
                client: client
            )
        )
        client.selectedRangeValue = NSRange(location: 10 + (acceptedText as NSString).length, length: 0)
        tracker.verifyPostInsertCaret(client: client)

        client.selectedRangeValue = NSRange(location: 10 + prefixLength, length: 0)
        XCTAssertFalse(tracker.observeDeleteBackward(client: client))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(store.allRecords().isEmpty)
    }

    func testTrackingOffsetRecordsDeletionInsideGeneratedSuffix() async throws {
        let store = AIAcceptedFeedbackStore.inMemory()
        let tracker = AIAcceptedFeedbackTracker(
            recorder: store,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            debounceNanoseconds: 0
        )
        let client = FeedbackTrackerClient(selectedRange: NSRange(location: 10, length: 0))
        let prefix = "我觉得这个方案"
        let suffix = "需要调整"
        let acceptedText = prefix + suffix
        let prefixLength = (prefix as NSString).length

        XCTAssertTrue(
            tracker.armAcceptedSpan(
                acceptID: UUID(),
                acceptedText: acceptedText,
                trackingText: suffix,
                trackingOffsetUTF16: prefixLength,
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

        let record = try XCTUnwrap(store.allRecords().first)
        XCTAssertEqual(record.deletedTexts, ["整"])
        XCTAssertEqual(record.deletedRanges.first?.location, 10 + prefixLength + (suffix as NSString).length - 1)
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

    func testFreshAdapterForSameUnderlyingClientKeepsTracking() async throws {
        let store = AIAcceptedFeedbackStore.inMemory()
        let tracker = AIAcceptedFeedbackTracker(
            recorder: store,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            debounceNanoseconds: 0
        )
        let underlyingClient = NSObject()
        let acceptedText = "这个方案需要调整"
        let acceptClient = FeedbackTrackerClient(
            selectedRange: NSRange(location: 6, length: 0),
            identityObject: underlyingClient
        )
        XCTAssertTrue(
            tracker.armAcceptedSpan(
                acceptID: UUID(),
                acceptedText: acceptedText,
                schemaID: "pinyin_simp",
                appBundleID: "com.apple.TextEdit",
                provider: "test-provider",
                contextVersion: "ctx",
                client: acceptClient
            )
        )

        let verifyClient = FeedbackTrackerClient(
            selectedRange: NSRange(location: 6 + (acceptedText as NSString).length, length: 0),
            identityObject: underlyingClient
        )
        tracker.verifyPostInsertCaret(client: verifyClient)
        let deleteClient = FeedbackTrackerClient(
            selectedRange: NSRange(location: 6 + (acceptedText as NSString).length, length: 0),
            identityObject: underlyingClient
        )

        XCTAssertTrue(tracker.observeDeleteBackward(client: deleteClient))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(store.allRecords().count, 1)
    }

    func testReplacementCompositionPreservesPendingDeletionUntilCommit() async throws {
        let store = AIAcceptedFeedbackStore.inMemory()
        let tracker = AIAcceptedFeedbackTracker(
            recorder: store,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            debounceNanoseconds: 10_000_000_000
        )
        let client = FeedbackTrackerClient(selectedRange: NSRange(location: 10, length: 0))
        let acceptedText = "这个方案需要调整"
        XCTAssertTrue(
            tracker.armAcceptedSpan(
                acceptID: UUID(),
                acceptedText: acceptedText,
                schemaID: "pinyin_simp",
                appBundleID: "com.apple.TextEdit",
                provider: "test-provider",
                contextVersion: "ctx",
                client: client
            )
        )
        let acceptedLength = (acceptedText as NSString).length
        client.selectedRangeValue = NSRange(location: 10 + acceptedLength, length: 0)
        tracker.verifyPostInsertCaret(client: client)
        XCTAssertTrue(tracker.observeDeleteBackward(client: client))

        client.selectedRangeValue = NSRange(location: 10 + acceptedLength - 1, length: 0)
        XCTAssertTrue(tracker.preserveForReplacementComposition(client: client))
        tracker.observeVerifiedReplacementCommit("优化", client: client)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(store.allRecords().count, 1)
        XCTAssertEqual(store.allRecords().first?.replacementText, "优化")
    }
}

private final class FeedbackTrackerClient: InputControllerClient, @unchecked Sendable {
    var selectedRangeValue: NSRange
    var bundleIdentifier: String? = "com.apple.TextEdit"
    var markedRange: NSRange?
    let identityObject: AnyObject

    init(selectedRange: NSRange, identityObject: AnyObject? = nil) {
        selectedRangeValue = selectedRange
        self.identityObject = identityObject ?? NSObject()
    }

    var selectedRange: NSRange {
        selectedRangeValue
    }

    var feedbackTrackingID: ObjectIdentifier {
        ObjectIdentifier(identityObject)
    }

    func firstRect(forCharacterRange _: NSRange) -> CGRect {
        .zero
    }

    func lineHeightRect(forCharacterIndex _: Int) -> CGRect {
        .zero
    }

    func setMarkedText(_: InputClientMarkedText, selectionRange _: NSRange, replacementRange _: NSRange) {}

    func insertText(_: String, replacementRange _: NSRange) {}
}
