import CoreGraphics
import Foundation
import KnowTypeAI
import KnowTypeCore
@testable import KnowTypeInputMethod
import XCTest

final class InputAIAcceptanceRuntimeTests: XCTestCase {
    func testCommitKindAndCandidateSourceMatchCoordinatorBehavior() async {
        let recorder = RecordingAcceptanceContextRecorder()
        let runtime = InputAIAcceptanceRuntime(
            contextEventRecorder: recorder,
            acceptedLearningRecorder: nil,
            acceptedFeedbackRecorder: nil,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            canRequestAIRecommendations: true,
            runtimePreferences: InputMethodRuntimePreferences(cloudContinuationEnabled: true)
        )
        let aiCandidate = AIRecommendationCandidate(
            prefixText: "我觉得",
            continuationText: "可以继续",
            displayText: "我觉得可以继续",
            confidence: 0.9,
            provider: "ai-test",
            contextVersion: "ctx"
        )

        XCTAssertTrue(
            runtime.recordCommit(
                context: commitContext(text: "ni", rawInput: "ni")
            ).shouldRecordLexicalCommit
        )
        XCTAssertTrue(
            runtime.recordCommit(
                context: commitContext(
                    text: "你",
                    rawInput: "ni",
                    selectedNativeCandidateSource: "traditional-full"
                )
            ).shouldRecordLexicalCommit
        )
        XCTAssertTrue(
            runtime.recordCommit(
                context: commitContext(
                    text: "你",
                    rawInput: "ni",
                    prefixCandidateSource: "traditional-prefix"
                )
            ).shouldRecordLexicalCommit
        )
        XCTAssertFalse(
            runtime.recordCommit(
                context: commitContext(text: "，", rawInput: "")
            ).shouldRecordLexicalCommit
        )
        XCTAssertTrue(
            runtime.recordCommit(
                context: commitContext(
                    text: "我觉得可以继续",
                    rawInput: "wojuede",
                    acceptedAIRecommendation: aiCandidate
                )
            ).shouldRecordLexicalCommit
        )

        let recorded = await waitUntil {
            await recorder.events.count == 4
        }
        XCTAssertTrue(recorded)
        let events = await recorder.events
        XCTAssertTrue(events.contains { $0.commitKind == .raw && $0.candidateSource == "raw" })
        XCTAssertTrue(events.contains { $0.commitKind == .traditional && $0.candidateSource == "traditional-full" })
        XCTAssertTrue(events.contains { $0.commitKind == .traditional && $0.candidateSource == "traditional-prefix" })
        XCTAssertTrue(events.contains { $0.commitKind == .ai && $0.candidateSource == "ai:ai-test" })
    }

    func testAcceptedAICommitRecordsAcceptedLearningHistory() async throws {
        let acceptedLearning = AIAcceptedLearningStore.inMemory()
        let runtime = InputAIAcceptanceRuntime(
            contextEventRecorder: nil,
            acceptedLearningRecorder: acceptedLearning,
            acceptedFeedbackRecorder: nil,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            canRequestAIRecommendations: true,
            runtimePreferences: InputMethodRuntimePreferences()
        )
        let acceptID = UUID()
        let candidate = AIRecommendationCandidate(
            prefixText: "我觉得",
            continuationText: "可以继续",
            displayText: "我觉得可以继续",
            confidence: 0.9,
            provider: "ai-test",
            contextVersion: "ctx"
        )

        _ = runtime.recordCommit(
            context: commitContext(
                text: "我觉得可以继续",
                rawInput: "wojuede",
                acceptedAIRecommendation: candidate,
                acceptID: acceptID
            )
        )

        let recorded = await waitUntil {
            acceptedLearning.allRecords().count == 1
        }
        XCTAssertTrue(recorded)
        let record = try XCTUnwrap(acceptedLearning.allRecords().first)
        XCTAssertEqual(record.acceptID, acceptID)
        XCTAssertEqual(record.schemaID, "pinyin_simp")
        XCTAssertEqual(record.appBundleID, "com.apple.TextEdit")
        XCTAssertEqual(record.rawInput, "wojuede")
        XCTAssertEqual(record.lockedPrefix, "我觉得")
        XCTAssertEqual(record.acceptedText, "我觉得可以继续")
        XCTAssertEqual(record.provider, "ai-test")
        XCTAssertEqual(record.contextVersion, "ctx")
        XCTAssertEqual(record.candidateSource, "ai:ai-test")
    }

    func testAcceptedAIMismatchedTextDoesNotRecordAcceptedLearning() async {
        let acceptedLearning = AIAcceptedLearningStore.inMemory()
        let runtime = InputAIAcceptanceRuntime(
            contextEventRecorder: nil,
            acceptedLearningRecorder: acceptedLearning,
            acceptedFeedbackRecorder: nil,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            canRequestAIRecommendations: true,
            runtimePreferences: InputMethodRuntimePreferences()
        )
        let candidate = AIRecommendationCandidate(
            prefixText: "",
            displayText: "AI 续写",
            confidence: 0.9,
            provider: "ai-test",
            contextVersion: "ctx"
        )

        _ = runtime.recordCommit(
            context: commitContext(
                text: "人工提交",
                rawInput: "rengong",
                acceptedAIRecommendation: candidate
            )
        )

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(acceptedLearning.allRecords().isEmpty)
    }

    func testProtectedAppSkipsAcceptedLearningAndFeedbackTracking() async {
        let acceptedLearning = AIAcceptedLearningStore.inMemory()
        let acceptedFeedback = AIAcceptedFeedbackStore.inMemory()
        let diagnosticSink = RecordingAcceptanceDiagnosticSink()
        let runtime = InputAIAcceptanceRuntime(
            contextEventRecorder: nil,
            acceptedLearningRecorder: acceptedLearning,
            acceptedFeedbackRecorder: acceptedFeedback,
            diagnosticSink: diagnosticSink,
            canRequestAIRecommendations: true,
            runtimePreferences: InputMethodRuntimePreferences()
        )
        let client = AcceptanceRuntimeClient(selectedRange: NSRange(location: 10, length: 0))
        client.bundleIdentifier = "com.apple.Terminal"
        let candidate = AIRecommendationCandidate(
            prefixText: "我觉得",
            continuationText: "可以继续",
            displayText: "我觉得可以继续",
            confidence: 0.9,
            provider: "ai-test",
            contextVersion: "ctx"
        )

        let acceptID = runtime.prepareAcceptedFeedbackTracking(
            context: InputAIAcceptanceFeedbackContext(
                text: "我觉得可以继续",
                schemaID: "pinyin_simp",
                appBundleID: "com.apple.Terminal",
                acceptedAIRecommendation: candidate,
                client: client
            )
        )
        let effects = runtime.recordCommit(
            context: commitContext(
                text: "我觉得可以继续",
                rawInput: "wojuede",
                appBundleID: "com.apple.Terminal",
                acceptedAIRecommendation: candidate,
                client: client
            )
        )

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(acceptID)
        XCTAssertFalse(effects.shouldRecordLexicalCommit)
        XCTAssertTrue(acceptedLearning.allRecords().isEmpty)
        XCTAssertTrue(acceptedFeedback.allRecords().isEmpty)
        XCTAssertTrue(diagnosticSink.events.contains { $0.stage == .acceptedFeedbackTrackingCancelled })
        XCTAssertTrue(diagnosticSink.events.contains { $0.stage == .acceptedLearningSkippedSecret })
    }

    func testSecretLikeCommitDoesNotRecordTypingEventOrLexicalEffect() async {
        let recorder = RecordingAcceptanceContextRecorder()
        let runtime = InputAIAcceptanceRuntime(
            contextEventRecorder: recorder,
            acceptedLearningRecorder: nil,
            acceptedFeedbackRecorder: nil,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            canRequestAIRecommendations: true,
            runtimePreferences: InputMethodRuntimePreferences(cloudContinuationEnabled: true)
        )

        let effects = runtime.recordCommit(
            context: commitContext(
                text: "sk-proj-abcdefghijklmnopqrstuvwxyz",
                rawInput: "abc"
            )
        )

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(effects.shouldRecordLexicalCommit)
        let events = await recorder.events
        XCTAssertTrue(events.isEmpty)
    }

    func testReplacementCommitRecordsAcceptedFeedback() async throws {
        let acceptedFeedback = AIAcceptedFeedbackStore.inMemory()
        let runtime = InputAIAcceptanceRuntime(
            contextEventRecorder: nil,
            acceptedLearningRecorder: nil,
            acceptedFeedbackRecorder: acceptedFeedback,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            canRequestAIRecommendations: true,
            runtimePreferences: InputMethodRuntimePreferences()
        )
        let client = AcceptanceRuntimeClient(selectedRange: NSRange(location: 10, length: 0))
        let prefix = "我觉得"
        let suffix = "可以继续"
        let acceptedText = prefix + suffix
        let candidate = AIRecommendationCandidate(
            prefixText: prefix,
            continuationText: suffix,
            displayText: acceptedText,
            confidence: 0.9,
            provider: "ai-test",
            contextVersion: "ctx"
        )

        let acceptID = runtime.prepareAcceptedFeedbackTracking(
            context: InputAIAcceptanceFeedbackContext(
                text: acceptedText,
                schemaID: "pinyin_simp",
                appBundleID: "com.apple.TextEdit",
                acceptedAIRecommendation: candidate,
                client: client
            )
        )
        XCTAssertNotNil(acceptID)
        client.selectedRangeValue = NSRange(location: 10 + (acceptedText as NSString).length, length: 0)
        runtime.verifyPostInsertCaret(client: client)
        XCTAssertTrue(runtime.observeDeleteBackward(client: client))
        client.selectedRangeValue = NSRange(location: 10 + (acceptedText as NSString).length - 1, length: 0)
        XCTAssertTrue(runtime.preserveFeedbackForReplacementComposition(client: client))

        _ = runtime.recordCommit(
            context: commitContext(
                text: "优化",
                rawInput: "youhua",
                client: client
            )
        )

        let recorded = await waitUntil {
            acceptedFeedback.allRecords().count == 1
        }
        XCTAssertTrue(recorded)
        let record = try XCTUnwrap(acceptedFeedback.allRecords().first)
        XCTAssertEqual(record.acceptID, acceptID)
        XCTAssertEqual(record.replacementText, "优化")
        XCTAssertEqual(record.deletedTexts, ["续"])
    }

    func testExternalDeleteRecordsTypingEventWhenEnabled() async {
        let recorder = RecordingAcceptanceContextRecorder()
        let runtime = InputAIAcceptanceRuntime(
            contextEventRecorder: recorder,
            acceptedLearningRecorder: nil,
            acceptedFeedbackRecorder: nil,
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            canRequestAIRecommendations: true,
            runtimePreferences: InputMethodRuntimePreferences(cloudContinuationEnabled: true)
        )

        runtime.recordExternalDelete(appBundleID: "com.apple.TextEdit")

        let recorded = await waitUntil {
            await recorder.events.count == 1
        }
        XCTAssertTrue(recorded)
        let event = await recorder.events.first
        XCTAssertEqual(event?.commitKind, .externalDelete)
        XCTAssertEqual(event?.candidateSource, "external-delete")
        XCTAssertEqual(event?.deleteCountBeforeCommit, 1)
        XCTAssertEqual(event?.appBundleID, "com.apple.TextEdit")
    }

    private func commitContext(
        text: String,
        rawInput: String,
        schemaID: String = "pinyin_simp",
        appBundleID: String? = "com.apple.TextEdit",
        acceptedAIRecommendation: AIRecommendationCandidate? = nil,
        acceptID: UUID? = nil,
        selectedNativeCandidateSource: String? = nil,
        prefixCandidateSource: String? = nil,
        deleteCountBeforeCommit: Int = 0,
        client: InputControllerClient? = nil
    ) -> InputAIAcceptanceCommitContext {
        InputAIAcceptanceCommitContext(
            text: text,
            rawInput: rawInput,
            schemaID: schemaID,
            appBundleID: appBundleID,
            acceptedAIRecommendation: acceptedAIRecommendation,
            acceptID: acceptID,
            selectedNativeCandidateSource: selectedNativeCandidateSource,
            prefixCandidateSource: prefixCandidateSource,
            deleteCountBeforeCommit: deleteCountBeforeCommit,
            client: client
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping () async -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await condition()
    }
}

private actor RecordingAcceptanceContextRecorder: AIContextEventRecording {
    private var recordedEvents: [AITypingEvent] = []

    func record(_ event: AITypingEvent) async {
        recordedEvents.append(event)
    }

    var events: [AITypingEvent] {
        recordedEvents
    }
}

private final class RecordingAcceptanceDiagnosticSink: AIRecommendationDiagnosticSink, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [AIRecommendationDiagnosticEvent] = []

    func record(_ event: AIRecommendationDiagnosticEvent) {
        lock.lock()
        recordedEvents.append(event)
        lock.unlock()
    }

    var events: [AIRecommendationDiagnosticEvent] {
        lock.lock()
        let events = recordedEvents
        lock.unlock()
        return events
    }
}

private final class AcceptanceRuntimeClient: InputControllerClient, @unchecked Sendable {
    var selectedRangeValue: NSRange
    var bundleIdentifier: String? = "com.apple.TextEdit"
    var markedRange: NSRange?
    private let identityObject = NSObject()

    init(selectedRange: NSRange) {
        selectedRangeValue = selectedRange
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
