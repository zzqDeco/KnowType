import Foundation
import XCTest
@testable import KnowTypeInputMethod
import KnowTypeCore

#if canImport(InputMethodKit)
import AppKit
import InputMethodKit
#endif

final class InputControllerCoordinatorTests: XCTestCase {
    func testAppendWritesMarkedTextThroughClientSeam() {
        let client = FakeInputControllerClient()
        client.markedRangeValue = NSRange(location: 4, length: 1)
        let (coordinator, host, _) = makeCoordinator(client: client)

        let handled = coordinator.handle(
            stroke: InputKeyStroke(text: "n", keyCode: 45),
            client: client
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(client.markedTextWrites.count, 1)
        XCTAssertFalse(client.markedTextWrites[0].text.isEmpty)
        XCTAssertEqual(client.markedTextWrites[0].replacementRange, NSRange(location: 4, length: 1))
        XCTAssertEqual(
            client.markedTextWrites[0].selectionRange.location,
            (client.markedTextWrites[0].text as NSString).length
        )
        XCTAssertEqual(host.scheduledOperations.count, 1)
        XCTAssertEqual(host.panelStates.last?.windowState.isVisible, true)
    }

    func testTextOnlySpaceCommitsWithActiveMarkedReplacementRange() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("i", client: client))
        client.markedRangeValue = NSRange(location: 7, length: 1)

        let handled = coordinator.handleText(" ", client: client)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertTextWrites.count, 1)
        XCTAssertEqual(client.insertTextWrites[0].text, "你")
        XCTAssertEqual(client.insertTextWrites[0].replacementRange, NSRange(location: 7, length: 1))
        XCTAssertEqual(host.hideCandidatePanelCount, 1)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testCompositionDisplaysRawPinyinUntilCandidateIsConfirmed() {
        let client = FakeInputControllerClient()
        let (coordinator, _, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("i", client: client))

        XCTAssertEqual(client.markedTextWrites.last?.text, "ni")
        XCTAssertEqual(coordinator.composedString() as? String, "ni")
        XCTAssertEqual(client.insertTextWrites.count, 0)
    }

    func testReturnCommitsRawInputInsteadOfSelectedChineseCandidate() {
        let client = FakeInputControllerClient()
        let (coordinator, _, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("i", client: client))
        let handled = coordinator.handle(
            stroke: InputKeyStroke(text: "\r", keyCode: 36),
            client: client
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertTextWrites.last?.text, "ni")
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testNumberSelectingSegmentCandidateUpdatesMarkedTextWithoutInsert() throws {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(client: client)

        for character in "nishishei" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let viewModel = try XCTUnwrap(host.panelStates.last?.windowState.viewModel)
        let segmentIndex = try XCTUnwrap(
            viewModel.prefixCandidates.firstIndex {
                $0.text == "你" && $0.rawRange == KnowTypeCore.TextRange(start: 0, length: 2)
            }
        )
        XCTAssertLessThan(segmentIndex, 9)

        let shortcutNumber = segmentIndex + 1
        let handled = coordinator.handle(
            stroke: InputKeyStroke(
                text: String(shortcutNumber),
                keyCode: keyCode(forNumber: shortcutNumber)
            ),
            client: client
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(client.markedTextWrites.last?.text, "你shishei")
        XCTAssertEqual(client.insertTextWrites.count, 0)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\r", keyCode: 36),
                client: client
            )
        )
        XCTAssertEqual(client.insertTextWrites.last?.text, "nishishei")
    }

    @MainActor
    func testFullyResolvedSegmentSelectionRefreshesProviderContinuations() async throws {
        let client = FakeInputControllerClient()
        let provider = RecordingContinuationProvider()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: provider,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "nishishei" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        try selectCandidate(
            text: "你",
            rawRange: KnowTypeCore.TextRange(start: 0, length: 2),
            coordinator: coordinator,
            host: host,
            client: client
        )
        XCTAssertEqual(client.markedTextWrites.last?.text, "你shishei")

        try selectCandidate(
            text: "是谁",
            rawRange: KnowTypeCore.TextRange(start: 2, length: 7),
            coordinator: coordinator,
            host: host,
            client: client
        )
        XCTAssertEqual(client.markedTextWrites.last?.text, "你是谁")

        let hasContinuation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.continuationCandidates
                .contains { $0.text == "继续推进" } == true
        }
        XCTAssertTrue(hasContinuation)
        let requests = await provider.requests
        XCTAssertTrue(requests.contains { $0.task == .continuation && $0.lockedPrefix == "你是谁" })

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\t", keyCode: 48),
                client: client
            )
        )
        XCTAssertEqual(client.insertTextWrites.last?.text, "你是谁继续推进")
    }

    @MainActor
    func testSelectedContinuationAfterSegmentResolutionIsCommitted() async throws {
        let client = FakeInputControllerClient()
        let provider = RecordingContinuationProvider()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: provider,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "nishishei" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        try selectCandidate(
            text: "你",
            rawRange: KnowTypeCore.TextRange(start: 0, length: 2),
            coordinator: coordinator,
            host: host,
            client: client
        )
        try selectCandidate(
            text: "是谁",
            rawRange: KnowTypeCore.TextRange(start: 2, length: 7),
            coordinator: coordinator,
            host: host,
            client: client
        )
        let hasContinuationPage = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.continuationCandidates.count == 2
        }
        XCTAssertTrue(hasContinuationPage)

        XCTAssertTrue(coordinator.handle(stroke: InputKeyStroke(text: "", keyCode: 125), client: client))
        XCTAssertTrue(coordinator.handle(stroke: InputKeyStroke(text: "", keyCode: 125), client: client))
        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "你是谁第二延续")
    }

    func testPunctuationAfterPartialSegmentSelectionCommitsDisplayedComposition() throws {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(client: client)

        for character in "nishishei" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        try selectCandidate(
            text: "你",
            rawRange: KnowTypeCore.TextRange(start: 0, length: 2),
            coordinator: coordinator,
            host: host,
            client: client
        )
        try selectCandidate(
            text: "是",
            rawRange: KnowTypeCore.TextRange(start: 2, length: 3),
            coordinator: coordinator,
            host: host,
            client: client
        )

        XCTAssertEqual(client.markedTextWrites.last?.text, "你是shei")
        XCTAssertTrue(coordinator.handleText(",", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "你是shei，")
    }

    func testCancelClearsMarkedTextAndHidesCandidatePanel() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("n", client: client))
        client.markedRangeValue = NSRange(location: 12, length: 1)

        let handled = coordinator.handle(
            stroke: InputKeyStroke(text: "\u{1B}", keyCode: 53),
            client: client
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(client.markedTextWrites.last?.text, "")
        XCTAssertEqual(client.markedTextWrites.last?.selectionRange, NSRange(location: 0, length: 0))
        XCTAssertEqual(client.markedTextWrites.last?.replacementRange, NSRange(location: 12, length: 1))
        XCTAssertEqual(host.hideCandidatePanelCount, 1)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testDelayedReanchorAppliesOnlyForCurrentComposition() {
        let client = FakeInputControllerClient()
        client.firstRectValue = CGRect(x: 40, y: 500, width: 0, height: 18)
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("n", client: client))
        let initialUpdateCount = host.panelStates.count
        client.firstRectValue = CGRect(x: 90, y: 520, width: 0, height: 18)

        host.runScheduledOperations()

        XCTAssertEqual(host.panelStates.count, initialUpdateCount + 1)
        XCTAssertEqual(host.panelStates.last?.windowState.anchorRect, client.firstRectValue)

        XCTAssertTrue(coordinator.handleText("i", client: client))
        let pendingAfterSecondAppend = host.scheduledOperations.count
        XCTAssertGreaterThan(pendingAfterSecondAppend, 0)
        let updatesBeforeCancel = host.panelStates.count

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\u{1B}", keyCode: 53),
                client: client
            )
        )
        client.firstRectValue = CGRect(x: 140, y: 540, width: 0, height: 18)
        host.runScheduledOperations()

        XCTAssertEqual(host.panelStates.count, updatesBeforeCancel)
    }

    func testDeactivateFlushesAndGatesPendingReanchorWhileCloseHides() {
        let client = FakeInputControllerClient()
        let persistence = FakeUserSelectionHistoryPersistence()
        let (coordinator, host, persistenceSpy) = makeCoordinator(
            client: client,
            persistence: persistence
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))
        let updatesBeforeDeactivate = host.panelStates.count

        coordinator.deactivateServer()
        client.firstRectValue = CGRect(x: 200, y: 500, width: 0, height: 18)
        host.runScheduledOperations()

        XCTAssertEqual(persistenceSpy.flushCalls.count, 1)
        XCTAssertEqual(host.panelStates.count, updatesBeforeDeactivate)
        XCTAssertEqual(host.hideCandidatePanelCount, 0)

        coordinator.inputControllerWillClose()

        XCTAssertEqual(persistenceSpy.flushCalls.count, 2)
        XCTAssertEqual(host.hideCandidatePanelCount, 1)
    }

    func testKeyIntentForwardingIgnoresNonComposingEventsAndHandlesAppend() {
        let client = FakeInputControllerClient()
        let (coordinator, _, _) = makeCoordinator(client: client)

        XCTAssertFalse(
            coordinator.handle(
                stroke: InputKeyStroke(text: "n", keyCode: 45, eventKind: .keyUp),
                client: client
            )
        )
        XCTAssertFalse(
            coordinator.handle(
                stroke: InputKeyStroke(text: "v", keyCode: 9, modifiers: [.command]),
                client: client
            )
        )
        XCTAssertEqual(client.markedTextWrites.count, 0)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "n", keyCode: 45, eventKind: .keyDown),
                client: client
            )
        )

        XCTAssertEqual(client.markedTextWrites.count, 1)
    }

    #if canImport(InputMethodKit)
    func testIMKClientAdapterForwardsMarkedTextInsertAndGeometry() {
        let imkClient = FakeIMKTextInput()
        imkClient.bundleIdentifierValue = "com.example.adapter"
        imkClient.selectedRangeValue = NSRange(location: 3, length: 2)
        imkClient.markedRangeValue = NSRange(location: 5, length: 1)
        imkClient.firstRectValue = CGRect(x: 20, y: 30, width: 0, height: 18)
        imkClient.lineHeightRectValue = CGRect(x: 25, y: 35, width: 0, height: 18)
        let adapter = IMKInputControllerClientAdapter(client: imkClient)

        adapter.setMarkedText(
            "你",
            selectionRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 5, length: 1)
        )
        adapter.insertText("你", replacementRange: NSRange(location: 5, length: 1))

        XCTAssertEqual(adapter.bundleIdentifier, "com.example.adapter")
        XCTAssertEqual(adapter.selectedRange, NSRange(location: 3, length: 2))
        XCTAssertEqual(adapter.markedRange, NSRange(location: 5, length: 1))
        XCTAssertEqual(
            adapter.firstRect(forCharacterRange: NSRange(location: 6, length: 0)),
            imkClient.firstRectValue
        )
        XCTAssertEqual(adapter.lineHeightRect(forCharacterIndex: 0), imkClient.lineHeightRectValue)
        XCTAssertEqual(imkClient.markedTextWrites.count, 1)
        XCTAssertEqual(imkClient.markedTextWrites[0].text, "你")
        XCTAssertEqual(imkClient.insertTextWrites.count, 1)
        XCTAssertEqual(imkClient.insertTextWrites[0].text, "你")
    }

    func testIMKClientAdapterTreatsUnknownMarkedRangeAsInactive() {
        let imkClient = FakeIMKTextInput()
        imkClient.markedRangeValue = NSRange(location: NSNotFound, length: NSNotFound)
        let adapter = IMKInputControllerClientAdapter(client: imkClient)

        XCTAssertNil(adapter.markedRange)
    }

    func testInputControllerWrapperAdaptsOnlyIMKTextInputClients() {
        let imkClient = FakeIMKTextInput()
        imkClient.bundleIdentifierValue = "com.example.wrapper"

        let adapted = KnowTypeInputController.inputControllerClient(from: imkClient)
        let ignored = KnowTypeInputController.inputControllerClient(from: NSObject())

        XCTAssertEqual(adapted?.bundleIdentifier, "com.example.wrapper")
        XCTAssertNil(ignored)
    }
    #endif

    private func makeCoordinator(
        client: FakeInputControllerClient,
        persistence: FakeUserSelectionHistoryPersistence = FakeUserSelectionHistoryPersistence(),
        provider: (any LLMProvider)? = nil,
        enablesAsyncSuggestionRefresh: Bool = false
    ) -> (
        InputControllerCoordinator,
        FakeInputControllerHost,
        FakeUserSelectionHistoryPersistence
    ) {
        let host = FakeInputControllerHost()
        host.currentClientValue = client
        let lexiconRuntime = InputMethodLexiconRuntime.defaultRuntime()
        let coordinator = InputControllerCoordinator(
            provider: provider,
            traditionalInputEngine: lexiconRuntime.makeEngine(),
            lexiconRuntimeSnapshot: lexiconRuntime.snapshot(),
            inputModePreferenceStore: FixedInputModePreferenceStore(),
            initialAppBundleID: client.bundleIdentifier,
            userSelectionHistoryPersistence: persistence,
            host: host,
            anchorResolver: CandidateAnchorResolver(
                screenProvider: FixedInputControllerScreenProvider(),
                accessibilityProvider: NoopAccessibilityAnchorProvider(),
                traceEnabled: false
            ),
            enablesAsyncSuggestionRefresh: enablesAsyncSuggestionRefresh
        )
        return (coordinator, host, persistence)
    }

    private func selectCandidate(
        text: String,
        rawRange: KnowTypeCore.TextRange,
        coordinator: InputControllerCoordinator,
        host: FakeInputControllerHost,
        client: FakeInputControllerClient
    ) throws {
        let viewModel = try XCTUnwrap(host.panelStates.last?.windowState.viewModel)
        let index = try XCTUnwrap(
            viewModel.prefixCandidates.firstIndex {
                $0.text == text && $0.rawRange == rawRange
            }
        )
        XCTAssertLessThan(index, 9)
        let shortcutNumber = index + 1
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(
                    text: String(shortcutNumber),
                    keyCode: keyCode(forNumber: shortcutNumber)
                ),
                client: client
            )
        )
    }

    @MainActor
    private func waitUntilOnMainActor(
        timeout: TimeInterval = 3,
        condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    private func keyCode(forNumber number: Int) -> Int {
        switch number {
        case 0: return 29
        case 1: return 18
        case 2: return 19
        case 3: return 20
        case 4: return 21
        case 5: return 23
        case 6: return 22
        case 7: return 26
        case 8: return 28
        case 9: return 25
        default: return -1
        }
    }
}

private struct FixedInputModePreferenceStore: InputModePreferenceStore {
    var preferences = InputModePreferences.standard

    func loadPreferences() -> InputModePreferences {
        preferences
    }

    func savePreferences(_ preferences: InputModePreferences) throws {}
}

private actor RecordingContinuationProvider: LLMProvider {
    nonisolated let providerName = "recording-continuation"
    private var recordedRequests: [LLMRequest] = []

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        recordedRequests.append(request)
        guard request.task == .continuation else {
            return LLMResponse(candidates: [])
        }
        return LLMResponse(candidates: [
            LLMCandidate(text: "继续推进", confidence: 0.9),
            LLMCandidate(text: "第二延续", confidence: 0.8)
        ])
    }

    var requests: [LLMRequest] {
        recordedRequests
    }
}

private struct FixedInputControllerScreenProvider: ScreenGeometryProviding {
    var screens: [CandidateAnchorScreen] = [
        CandidateAnchorScreen(
            identifier: "main",
            frame: CGRect(x: 0, y: 0, width: 800, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 760)
        )
    ]
}

private final class FakeInputControllerHost: InputControllerHost {
    var currentClientValue: InputControllerClient?
    private(set) var updateCompositionCount = 0
    private(set) var panelStates: [CandidatePanelState] = []
    private(set) var hideCandidatePanelCount = 0
    private(set) var scheduledOperations: [@Sendable () -> Void] = []

    var currentClient: InputControllerClient? {
        currentClientValue
    }

    func updateComposition() {
        updateCompositionCount += 1
    }

    func updateCandidatePanel(state: CandidatePanelState, locale: KnowTypeLocale) {
        panelStates.append(state)
    }

    func hideCandidatePanel() {
        hideCandidatePanelCount += 1
    }

    func scheduleDelayedReanchor(_ operation: @escaping @Sendable () -> Void) {
        scheduledOperations.append(operation)
    }

    func runScheduledOperations() {
        let operations = scheduledOperations
        scheduledOperations.removeAll()
        operations.forEach { $0() }
    }
}

private final class FakeInputControllerClient: InputControllerClient, @unchecked Sendable {
    struct MarkedTextWrite: Equatable {
        var text: String
        var selectionRange: NSRange
        var replacementRange: NSRange
    }

    struct InsertTextWrite: Equatable {
        var text: String
        var replacementRange: NSRange
    }

    var bundleIdentifier: String? = "com.example.host"
    var selectedRangeValue = NSRange(location: 10, length: 0)
    var markedRangeValue: NSRange?
    var firstRectValue = CGRect(x: 40, y: 500, width: 0, height: 18)
    var lineHeightRectValue = CGRect(x: 40, y: 500, width: 0, height: 18)
    private(set) var markedTextWrites: [MarkedTextWrite] = []
    private(set) var insertTextWrites: [InsertTextWrite] = []

    var selectedRange: NSRange {
        selectedRangeValue
    }

    var markedRange: NSRange? {
        markedRangeValue
    }

    func firstRect(forCharacterRange range: NSRange) -> CGRect {
        firstRectValue
    }

    func lineHeightRect(forCharacterIndex index: Int) -> CGRect {
        lineHeightRectValue
    }

    func setMarkedText(
        _ text: String,
        selectionRange: NSRange,
        replacementRange: NSRange
    ) {
        markedTextWrites.append(
            MarkedTextWrite(
                text: text,
                selectionRange: selectionRange,
                replacementRange: replacementRange
            )
        )
        if text.isEmpty {
            markedRangeValue = nil
        } else {
            let location = replacementRange.location == NSNotFound
                ? selectedRangeValue.location
                : replacementRange.location
            markedRangeValue = NSRange(location: location, length: (text as NSString).length)
        }
    }

    func insertText(_ text: String, replacementRange: NSRange) {
        insertTextWrites.append(
            InsertTextWrite(
                text: text,
                replacementRange: replacementRange
            )
        )
    }
}

private final class FakeUserSelectionHistoryPersistence: InputControllerUserSelectionHistoryPersisting, @unchecked Sendable {
    private(set) var flushCalls: [[String]] = []
    private(set) var recordedSelections: [String] = []

    func loadHistory(maxEntries: Int) -> [String] {
        []
    }

    func recordSelection(
        _ text: String,
        currentHistory: [String],
        maxEntries: Int
    ) -> [String] {
        recordedSelections.append(text)
        return Array((currentHistory + [text]).suffix(maxEntries))
    }

    func flushHistory(_ currentHistory: [String], maxEntries: Int) {
        flushCalls.append(Array(currentHistory.suffix(maxEntries)))
    }
}

#if canImport(InputMethodKit)
private final class FakeIMKTextInput: NSObject, IMKTextInput {
    var bundleIdentifierValue = "com.example.host"
    var selectedRangeValue = NSRange(location: 0, length: 0)
    var markedRangeValue = NSRange(location: NSNotFound, length: NSNotFound)
    var firstRectValue = CGRect(x: 0, y: 0, width: 0, height: 18)
    var lineHeightRectValue = CGRect(x: 0, y: 0, width: 0, height: 18)
    private(set) var markedTextWrites: [FakeInputControllerClient.MarkedTextWrite] = []
    private(set) var insertTextWrites: [FakeInputControllerClient.InsertTextWrite] = []

    func insertText(_ string: Any!, replacementRange: NSRange) {
        insertTextWrites.append(
            FakeInputControllerClient.InsertTextWrite(
                text: string as? String ?? "",
                replacementRange: replacementRange
            )
        )
    }

    func setMarkedText(
        _ string: Any!,
        selectionRange: NSRange,
        replacementRange: NSRange
    ) {
        markedTextWrites.append(
            FakeInputControllerClient.MarkedTextWrite(
                text: string as? String ?? "",
                selectionRange: selectionRange,
                replacementRange: replacementRange
            )
        )
    }

    func selectedRange() -> NSRange {
        selectedRangeValue
    }

    func markedRange() -> NSRange {
        markedRangeValue
    }

    func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        nil
    }

    func length() -> Int {
        0
    }

    func characterIndex(
        for point: NSPoint,
        tracking mappingMode: IMKLocationToOffsetMappingMode,
        inMarkedRange: UnsafeMutablePointer<ObjCBool>!
    ) -> Int {
        NSNotFound
    }

    func attributes(
        forCharacterIndex index: Int,
        lineHeightRectangle lineRect: NSRectPointer!
    ) -> [AnyHashable: Any]! {
        lineRect?.pointee = lineHeightRectValue
        return [:]
    }

    func validAttributesForMarkedText() -> [Any]! {
        []
    }

    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}

    func selectMode(_ modeIdentifier: String!) {}

    func supportsUnicode() -> Bool {
        true
    }

    func bundleIdentifier() -> String! {
        bundleIdentifierValue
    }

    func windowLevel() -> CGWindowLevel {
        0
    }

    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool {
        false
    }

    func uniqueClientIdentifierString() -> String! {
        "fake-imk-client"
    }

    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! {
        ""
    }

    func firstRect(
        forCharacterRange aRange: NSRange,
        actualRange: NSRangePointer!
    ) -> NSRect {
        firstRectValue
    }
}
#endif
