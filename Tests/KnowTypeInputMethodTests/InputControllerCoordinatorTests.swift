import Foundation
import XCTest
import KnowTypeAI
@testable import KnowTypeInputMethod
import KnowTypeCore

#if canImport(InputMethodKit)
import AppKit
import InputMethodKit
#endif

final class InputControllerCoordinatorTests: XCTestCase {
    override func setUpWithError() throws {
        let retiredLocalConversionTests = [
            "testAsyncNoProviderRefreshPublishesLocalFallbackContinuations",
            "testAsyncPendingPunctuationAppliesRemainingSegmentBeforeCommit",
            "testAsyncPendingPunctuationDoesNotApplyPartialFallbackSegment",
            "testAsyncPendingSpaceAppliesRemainingSegmentBeforeCommit",
            "testAsyncRawIdentityVisibleSpaceDoesNotCommitHiddenAlternative",
            "testCommitCompositionPreservesResolvedSegments",
            "testDisabledAIKeepsResolvedCompositionWithoutLocalContinuations",
            "testFullyResolvedCompositionSpaceWinsBeforeNativeSpace",
            "testFullyResolvedSegmentSelectionHonorsDisabledLocalContinuationsWithoutProvider",
            "testFullyResolvedSegmentSelectionKeepsNoProviderFallbackContinuations",
            "testFullyResolvedSegmentSelectionRefreshesAIRecommendationSlot",
            "testNativeFullCandidateSelectionMapsAugmentedRowsToStableNativeIndex",
            "testNativeNoProviderSuggestionsKeepLocalFallbackContinuations",
            "testNativeSpaceHonorsSelectedContinuationBeforeRime",
            "testNumberSelectingSegmentCandidateUpdatesMarkedTextWithoutInsert",
            "testNumberTwoCommitsReadyAIRecommendationAfterSegmentResolution",
            "testPartialSegmentRefreshDoesNotAskProvider",
            "testPunctuationAfterPartialSegmentSelectionCommitsDisplayedComposition",
            "testRuntimeLexiconReloadReplaysActiveRawInputIntoReplacementConversionEngine",
            "testSegmentSpaceSelectionWinsBeforeNativeSpace",
            "testSpaceCommitsHighlightedReadyAIRecommendation",
            "testTabCommitsVisibleNoProviderFallbackContinuation",
            "testTabDoesNotCommitContinuationForPartialSegmentCandidate"
        ]
        if retiredLocalConversionTests.contains(where: name.contains) {
            throw XCTSkip("Rime-only hot path retired local conversion, segment selection, sync fallback continuations, and runtime lexicon reload behavior")
        }
    }

    func testAppendWritesMarkedTextWithoutTrustingStaleHostMarkedRange() {
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
        XCTAssertEqual(
            client.markedTextWrites[0].replacementRange,
            NSRange(location: NSNotFound, length: NSNotFound)
        )
        XCTAssertEqual(
            client.markedTextWrites[0].selectionRange.location,
            (client.markedTextWrites[0].text as NSString).length
        )
        XCTAssertEqual(host.scheduledOperations.count, 1)
        XCTAssertEqual(host.panelStates.last?.windowState.isVisible, true)
    }

    func testSpotlightClientPrefersVisualAboveCandidatePanelPlacement() {
        let client = FakeInputControllerClient()
        client.bundleIdentifier = "com.apple.Spotlight"
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("n", client: client))

        XCTAssertEqual(host.panelStates.last?.windowState.placementPreference, .preferVisualAbove)
    }

    func testNonSpotlightClientUsesAutomaticCandidatePanelPlacement() {
        let client = FakeInputControllerClient()
        client.bundleIdentifier = "com.apple.TextEdit"
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("n", client: client))

        XCTAssertEqual(host.panelStates.last?.windowState.placementPreference, .automatic)
    }

    func testTextOnlySpaceCommitIgnoresStaleHostMarkedRange() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("i", client: client))
        let firstCandidate = host.panelStates.last?.windowState.viewModel.prefixCandidates.first?.text
        XCTAssertNotNil(firstCandidate)
        client.markedRangeValue = NSRange(location: 7, length: 1)

        let handled = coordinator.handleText(" ", client: client)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertTextWrites.count, 1)
        XCTAssertEqual(client.insertTextWrites[0].text, firstCandidate)
        XCTAssertEqual(
            client.insertTextWrites[0].replacementRange,
            NSRange(location: NSNotFound, length: NSNotFound)
        )
        XCTAssertEqual(host.hideCandidatePanelCount, 1)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testIdleSpaceInsertsDirectPassthroughText() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(client.insertTextWrites.map(\.text), [" "])
        XCTAssertEqual(
            client.insertTextWrites.last?.replacementRange,
            NSRange(location: NSNotFound, length: NSNotFound)
        )
        XCTAssertTrue(client.markedTextWrites.isEmpty)
        XCTAssertTrue(host.panelStates.isEmpty)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testIdleDigitsInsertDirectPassthroughTextWithoutComposition() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(client: client)

        for number in [1, 2, 3] {
            XCTAssertTrue(coordinator.handleText("\(number)", client: client))
        }

        XCTAssertEqual(client.insertTextWrites.map(\.text), ["1", "2", "3"])
        XCTAssertEqual(
            client.insertTextWrites.map(\.replacementRange),
            Array(repeating: NSRange(location: NSNotFound, length: NSNotFound), count: 3)
        )
        XCTAssertTrue(client.markedTextWrites.isEmpty)
        XCTAssertTrue(host.panelStates.isEmpty)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testIdleDigitKeyCodesInsertDirectPassthroughTextWithoutComposition() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(client: client)

        for number in [0, 1, 2] {
            XCTAssertTrue(
                coordinator.handle(
                    stroke: InputKeyStroke(text: "\(number)", keyCode: keyCode(forNumber: number)),
                    client: client
                )
            )
        }

        XCTAssertEqual(client.insertTextWrites.map(\.text), ["0", "1", "2"])
        XCTAssertTrue(client.markedTextWrites.isEmpty)
        XCTAssertTrue(host.panelStates.isEmpty)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testIdlePassthroughIgnoresStaleHostMarkedRange() {
        let client = FakeInputControllerClient()
        client.markedRangeValue = NSRange(location: 7, length: 2)
        let (coordinator, _, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, " ")
        XCTAssertEqual(
            client.insertTextWrites.last?.replacementRange,
            NSRange(location: NSNotFound, length: NSNotFound)
        )
    }

    func testIdleDigitsIgnoreStaleHostMarkedRange() {
        let client = FakeInputControllerClient()
        client.markedRangeValue = NSRange(location: 7, length: 2)
        let (coordinator, _, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("1", client: client))
        XCTAssertTrue(coordinator.handleText("2", client: client))

        XCTAssertEqual(client.insertTextWrites.map(\.text), ["1", "2"])
        XCTAssertEqual(
            client.insertTextWrites.map(\.replacementRange),
            Array(repeating: NSRange(location: NSNotFound, length: NSNotFound), count: 2)
        )
    }

    func testIdleReturnDoesNotClearStaleHostMarkedRange() {
        let client = FakeInputControllerClient()
        client.selectedRangeValue = NSRange(location: 12, length: 3)
        client.markedRangeValue = NSRange(location: 7, length: 2)
        let (coordinator, _, _) = makeCoordinator(client: client)

        let handled = coordinator.handle(
            stroke: InputKeyStroke(text: "\r", keyCode: 36),
            client: client
        )

        XCTAssertFalse(handled)
        XCTAssertTrue(client.markedTextWrites.isEmpty)
        XCTAssertTrue(client.insertTextWrites.isEmpty)
        XCTAssertEqual(client.markedRangeValue, NSRange(location: 7, length: 2))
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
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("i", client: client))
        client.markedRangeValue = NSRange(location: 99, length: 2)
        let handled = coordinator.handle(
            stroke: InputKeyStroke(text: "\r", keyCode: 36),
            client: client
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertTextWrites.last?.text, "ni")
        XCTAssertEqual(
            client.insertTextWrites.last?.replacementRange,
            NSRange(location: NSNotFound, length: NSNotFound)
        )
        XCTAssertEqual(host.hideCandidatePanelCount, 1)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testFastSpaceThenReturnDoesNotDuplicateCommitOrReopenPanel() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("i", client: client))
        XCTAssertTrue(coordinator.handleText(" ", client: client))
        let updatesAfterCommit = host.panelStates.count

        XCTAssertFalse(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\r", keyCode: 36),
                client: client
            )
        )
        host.runScheduledOperations()

        XCTAssertEqual(client.insertTextWrites.count, 1)
        XCTAssertEqual(client.insertTextWrites.last?.text, "你")
        XCTAssertEqual(host.panelStates.count, updatesAfterCommit)
        XCTAssertEqual(coordinator.composedString() as? String, "")
        XCTAssertGreaterThanOrEqual(host.hideCandidatePanelCount, 2)
    }

    func testFastSpaceThenSpaceDoesNotDuplicateCommitOrReopenPanel() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("i", client: client))
        XCTAssertTrue(coordinator.handleText(" ", client: client))
        let updatesAfterCommit = host.panelStates.count

        XCTAssertTrue(coordinator.handleText(" ", client: client))
        host.runScheduledOperations()

        XCTAssertEqual(client.insertTextWrites.map(\.text), ["你", " "])
        XCTAssertEqual(host.panelStates.count, updatesAfterCommit)
        XCTAssertEqual(coordinator.composedString() as? String, "")
        XCTAssertGreaterThanOrEqual(host.hideCandidatePanelCount, 2)
    }

    func testSingleLetterFastSpacePublishesOrderedHiddenFrameAfterVisibleFrame() throws {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("d", client: client))
        let visibleFrame = try XCTUnwrap(host.candidatePanelFrames.last)
        XCTAssertTrue(visibleFrame.isVisible)
        XCTAssertEqual(visibleFrame.panelModel.windowState.viewModel.rawInput, "d")

        XCTAssertTrue(coordinator.handleText(" ", client: client))
        let hiddenFrame = try XCTUnwrap(host.candidatePanelFrames.last)

        XCTAssertFalse(hiddenFrame.isVisible)
        XCTAssertEqual(hiddenFrame.visibilityReason, .reset)
        XCTAssertGreaterThan(hiddenFrame.presentationGeneration, visibleFrame.presentationGeneration)
        XCTAssertEqual(client.insertTextWrites.map(\.text), ["候选d"])
    }

    func testCommitCompositionPreservesResolvedSegments() throws {
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

        coordinator.commitComposition(client: client)

        XCTAssertEqual(client.insertTextWrites.last?.text, "你shishei")
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testNumberSelectingSegmentCandidateUpdatesMarkedTextWithoutInsert() throws {
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

    func testTabDoesNotCommitContinuationForPartialSegmentCandidate() throws {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(client: client)

        for character in "nish" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let viewModel = try XCTUnwrap(host.panelStates.last?.windowState.viewModel)

        XCTAssertTrue(
            viewModel.prefixCandidates.contains {
                $0.text == "你" && $0.rawRange == KnowTypeCore.TextRange(start: 0, length: 2)
            }
        )

        _ = coordinator.candidates()
        coordinator.candidateSelectionChanged("你")
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\t", keyCode: 48),
                client: client
            )
        )

        XCTAssertEqual(client.insertTextWrites.count, 0)
        XCTAssertEqual(coordinator.composedString() as? String, "nish")
    }

    @MainActor
    func testAsyncAppendPublishesMarkedTextAndImmediateIndexedCandidates() async {
        let client = FakeInputControllerClient()
        let lexiconRuntime = InputMethodLexiconRuntime(directories: [])
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true,
            lexiconRuntime: lexiconRuntime
        )

        let start = ContinuousClock.now
        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let elapsed = start.duration(to: .now)
        let milliseconds = Int(
            Double(elapsed.components.seconds) * 1000
                + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        )

        XCTAssertLessThan(milliseconds, 250)
        XCTAssertEqual(client.markedTextWrites.last?.text, "zhegeapi")
        XCTAssertFalse(
            host.panelStates.last?.windowState.viewModel.prefixCandidates.isEmpty ?? true,
            "indexed local candidates should be available before async AI refreshes"
        )

        let hasCandidates = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.rawInput == "zhegeapi"
                && host.panelStates.last?.windowState.viewModel.prefixCandidates.isEmpty == false
        }
        XCTAssertTrue(hasCandidates)
    }

    @MainActor
    func testRuntimeLexiconReloadReplaysActiveRawInputIntoReplacementConversionEngine() async throws {
        let client = FakeInputControllerClient()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lexiconRuntime = InputMethodLexiconRuntime(directories: [directory])
        let recorder = ConversionReplayRecorder()
        let nativeRecorder = NativeSelectionRecorder()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true,
            lexiconRuntime: lexiconRuntime,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["你"],
                recorder: nativeRecorder
            ),
            conversionEngineFactory: { _ in
                ReplayRecordingConversionEngine(recorder: recorder)
            }
        )
        try? await Task.sleep(nanoseconds: 120_000_000)
        try Data("ce shi ci\t测试词\t0.995\n".utf8)
            .write(to: directory.appendingPathComponent("user.tsv"))

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("i", client: client))

        let replayedActiveInput = await waitUntilOnMainActor {
            recorder.processedTexts.contains { !$0.isEmpty }
        }
        XCTAssertTrue(replayedActiveInput)
    }

    @MainActor
    func testAsyncPendingSpaceCommitsFirstNativeCandidateWithoutBlocking() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let firstCandidate = host.panelStates.last?.windowState.viewModel.prefixCandidates.first?.text
        XCTAssertNotNil(firstCandidate)
        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, firstCandidate)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    @MainActor
    func testAsyncImmediateNumberSelectionCommitsCandidateWithoutAppendingDigit() throws {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let viewModel = try XCTUnwrap(host.panelStates.last?.windowState.viewModel)
        let secondCandidate = try XCTUnwrap(viewModel.prefixCandidates.dropFirst().first?.text)
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "2", keyCode: keyCode(forNumber: 2)),
                client: client
            )
        )

        XCTAssertEqual(client.insertTextWrites.last?.text, secondCandidate)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testNativeHandledSpaceWithoutCommitConsumesInsteadOfFallingBack() {
        let client = FakeInputControllerClient()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            conversionEngine: NativeHandledNoCommitConversionEngine()
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("i", client: client))
        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(client.insertTextWrites.count, 0)
        XCTAssertEqual(coordinator.composedString() as? String, "ni")
    }

    func testNativeHandledNumberSelectionWithoutCommitConsumesInsteadOfFallingBack() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: NativeHandledNoCommitConversionEngine()
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("i", client: client))
        XCTAssertTrue(host.panelStates.last?.windowState.isVisible == true)
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "1", keyCode: keyCode(forNumber: 1)),
                client: client
            )
        )

        XCTAssertEqual(client.insertTextWrites.count, 0)
        XCTAssertEqual(coordinator.composedString() as? String, "ni")
    }

    @MainActor
    func testNativeHandledSpaceCancelsPendingAsyncSuggestionPublication() async {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true,
            conversionEngine: SpaceUpdatingNativeConversionEngine(),
            asyncSuggestionDelayNanoseconds: 200_000_000
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertEqual(host.panelStates.last?.windowState.viewModel.prefixCandidates.first?.text, "before-space")

        XCTAssertTrue(coordinator.handleText(" ", client: client))
        XCTAssertEqual(host.panelStates.last?.windowState.viewModel.prefixCandidates.first?.text, "after-space")

        try? await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(host.panelStates.last?.windowState.viewModel.prefixCandidates.first?.text, "after-space")
        XCTAssertEqual(client.insertTextWrites.count, 0)
    }

    func testDeleteToEmptyResetsConversionEngineBeforeNextComposition() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: BypassUntilResetConversionEngine()
        )

        XCTAssertTrue(coordinator.handleText("\u{E9}", client: client))
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\u{7F}", keyCode: 51),
                client: client
            )
        )
        XCTAssertEqual(coordinator.composedString() as? String, "")

        XCTAssertTrue(coordinator.handleText("n", client: client))

        XCTAssertEqual(host.panelStates.last?.windowState.viewModel.prefixCandidates.first?.text, "native-n")
    }

    func testSegmentSpaceSelectionWinsBeforeNativeSpace() throws {
        let client = FakeInputControllerClient()
        let recorder = NativeSelectionRecorder()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["候一", "候二", "候三", "候四", "候五", "候六"],
                recorder: recorder,
                spaceCommit: "native-space"
            )
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

        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "你是谁")
        XCTAssertEqual(recorder.spaceProcessCount, 0)
    }

    func testFullyResolvedCompositionSpaceWinsBeforeNativeSpace() throws {
        let client = FakeInputControllerClient()
        let recorder = NativeSelectionRecorder()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["native-one", "native-two"],
                recorder: recorder,
                spaceCommit: "native-space"
            )
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

        XCTAssertEqual(client.insertTextWrites.count, 0)
        XCTAssertEqual(coordinator.composedString() as? String, "你是谁")
        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "你是谁")
        XCTAssertEqual(recorder.spaceProcessCount, 0)
    }

    func testNativeFullCandidateSelectionMapsAugmentedRowsToStableNativeIndex() throws {
        let client = FakeInputControllerClient()
        let recorder = NativeSelectionRecorder()
        let nativeCandidates = ["候一", "候二", "候三", "候四", "候五", "候六"]
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: nativeCandidates,
                recorder: recorder
            )
        )

        for character in "nishishei" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let viewModel = try XCTUnwrap(host.panelStates.last?.windowState.viewModel)
        XCTAssertTrue(
            viewModel.prefixCandidates.contains {
                $0.text == "你" && $0.rawRange == KnowTypeCore.TextRange(start: 0, length: 2)
            }
        )
        let shortcutNumber = try visibleShortcutNumber(
            text: "候六",
            coordinator: coordinator,
            host: host,
            client: client
        )

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: String(shortcutNumber), keyCode: keyCode(forNumber: shortcutNumber)),
                client: client
            )
        )

        XCTAssertEqual(recorder.selectedIndices, [5])
        XCTAssertEqual(client.insertTextWrites.last?.text, "候六")
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testNativeDuplicateCandidateSelectionUsesStableNativeIndex() throws {
        let client = FakeInputControllerClient()
        let recorder = NativeSelectionRecorder()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["重复", "重复", "其他"],
                recorder: recorder
            )
        )

        for character in "chongfu" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let viewModel = try XCTUnwrap(host.panelStates.last?.windowState.viewModel)
        XCTAssertEqual(viewModel.prefixCandidates.filter { $0.text == "重复" }.count, 2)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "2", keyCode: keyCode(forNumber: 2)),
                client: client
            )
        )

        XCTAssertEqual(recorder.selectedIndices, [1])
        XCTAssertEqual(client.insertTextWrites.last?.text, "重复")
    }

    func testNativeCandidateSelectionFailureKeepsCompositionInsteadOfCommittingRaw() throws {
        let client = FakeInputControllerClient()
        let recorder = NativeSelectionRecorder()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["候一", "候二"],
                recorder: recorder,
                commitsSelection: false
            )
        )

        for character in "hou" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let viewModel = try XCTUnwrap(host.panelStates.last?.windowState.viewModel)
        XCTAssertEqual(viewModel.prefixCandidates.map(\.text), ["候一", "候二"])

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "2", keyCode: keyCode(forNumber: 2)),
                client: client
            )
        )

        XCTAssertEqual(recorder.selectedIndices, [1])
        XCTAssertTrue(client.insertTextWrites.isEmpty)
        XCTAssertEqual(coordinator.composedString() as? String, "hou")
    }

    func testRimeOnlyNativeSuggestionDoesNotAddSynchronousLocalFallbackContinuations() throws {
        let client = FakeInputControllerClient()
        let recorder = NativeSelectionRecorder()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            runtimePreferences: InputMethodRuntimePreferences(
                localContinuationEnabledWhenNoProvider: true
            ),
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["你"],
                recorder: recorder
            )
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("i", client: client))
        let viewModel = try XCTUnwrap(host.panelStates.last?.windowState.viewModel)

        XCTAssertEqual(viewModel.prefixCandidates.map { $0.text }, ["你"])
        XCTAssertTrue(viewModel.continuationCandidates.isEmpty)
    }

    func testNativeSpaceUsesRimeSpaceForDuplicateTextWithoutStableNativeIndex() {
        let client = FakeInputControllerClient()
        let recorder = NativeSelectionRecorder()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["重复", "重复"],
                recorder: recorder,
                spaceCommit: "native-space",
                source: "traditional-fallback"
            )
        )

        for character in "chongfu" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\u{F701}", keyCode: 125),
                client: client
            )
        )
        XCTAssertEqual(host.panelStates.last?.windowState.selection, .fullCandidate(1))

        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(recorder.spaceProcessCount, 1)
        XCTAssertEqual(recorder.selectedIndices, [])
        XCTAssertEqual(client.insertTextWrites.last?.text, "native-space")
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testNativeArrowSelectionUpdatesRimeHighlightBeforeSpace() throws {
        let client = FakeInputControllerClient()
        let recorder = NativeSelectionRecorder()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["候一", "候二", "候三"],
                recorder: recorder,
                spaceCommit: "native-space"
            )
        )

        for character in "hou" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        XCTAssertEqual(host.panelStates.last?.windowState.selection, .fullCandidate(0))
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\u{F701}", keyCode: 125),
                client: client
            )
        )
        XCTAssertEqual(host.panelStates.last?.windowState.selection, .fullCandidate(1))

        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(recorder.highlightedIndices, [1])
        XCTAssertEqual(recorder.selectedIndices, [])
        XCTAssertEqual(recorder.spaceProcessCount, 1)
        XCTAssertEqual(client.insertTextWrites.last?.text, "native-space")
    }

    @MainActor
    func testNativeNoProviderSuggestionsKeepLocalFallbackContinuations() async {
        let client = FakeInputControllerClient()
        let recorder = NativeSelectionRecorder()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["我觉得这个方案"],
                recorder: recorder
            )
        )

        for character in "wojuedezhegefagnan" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }

        let hasFallbackContinuation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.continuationCandidates.contains {
                $0.text == "还有进一步优化空间"
            } == true
        }
        XCTAssertTrue(hasFallbackContinuation)
    }

    @MainActor
    func testNativeSpaceHonorsSelectedContinuationBeforeRime() async throws {
        let client = FakeInputControllerClient()
        let recorder = NativeSelectionRecorder()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["我觉得这个方案"],
                recorder: recorder,
                spaceCommit: "native-space"
            )
        )

        for character in "wojuedezhegefagnan" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasFallbackContinuation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.continuationCandidates.contains {
                $0.text == "还有进一步优化空间"
            } == true
        }
        XCTAssertTrue(hasFallbackContinuation)
        let viewModel = try XCTUnwrap(host.panelStates.last?.windowState.viewModel)
        let prefix = try XCTUnwrap(viewModel.prefixCandidates.first?.text)
        let continuation = try XCTUnwrap(viewModel.continuationCandidates.first?.text)

        for _ in 0..<20 where host.panelStates.last?.windowState.selection != .continuationCandidate(0) {
            XCTAssertTrue(
                coordinator.handle(
                    stroke: InputKeyStroke(text: "\u{F701}", keyCode: 125),
                    client: client
                )
            )
        }
        XCTAssertEqual(host.panelStates.last?.windowState.selection, .continuationCandidate(0))
        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "\(prefix)\(continuation)")
        XCTAssertEqual(recorder.spaceProcessCount, 0)
    }

    @MainActor
    func testAsyncReadyLocalPrefixCommitsAfterCandidatePublication() async {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "wsm" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasPrefix = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.isEmpty == false
        }
        XCTAssertTrue(hasPrefix)

        let visiblePrefix = host.panelStates.last?.windowState.viewModel.prefixCandidates.first?.text
        XCTAssertNotNil(visiblePrefix)
        XCTAssertTrue(host.panelStates.last?.windowState.isVisible == true)
        XCTAssertTrue(coordinator.handleText(" ", client: client))
        XCTAssertEqual(client.insertTextWrites.last?.text, visiblePrefix)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    @MainActor
    func testAsyncProviderPathShowsLocalPrefixesWithoutFallbackContinuations() async {
        let client = FakeInputControllerClient()
        let provider = RecordingContinuationProvider()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: provider,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "wsm" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasPrefix = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.isEmpty == false
        }
        XCTAssertTrue(hasPrefix)

        let viewModel = host.panelStates.last?.windowState.viewModel
        XCTAssertFalse(viewModel?.prefixCandidates.isEmpty ?? true)
        XCTAssertTrue(viewModel?.continuationCandidates.isEmpty == true)
    }

    @MainActor
    func testAsyncNoProviderRefreshPublishesLocalFallbackContinuations() async {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "wo jue de zhege fagnan" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }

        let hasFallbackContinuation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.continuationCandidates.contains {
                $0.text == "还有进一步优化空间"
            } == true
        }

        XCTAssertTrue(hasFallbackContinuation)
    }

    func testLazyAIRecommendationRuntimeDoesNotSuppressNoProviderFallbackContinuations() {
        let client = FakeInputControllerClient()
        let aiProvider = UnavailableAIRecommendationProvider()
        let providerAvailability = AIRecommendationProviderAvailabilityState(.unknown)
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            aiRecommendationProvider: aiProvider,
            aiRecommendationProviderAvailability: providerAvailability,
            enablesAsyncSuggestionRefresh: true
        )

        let continuations = coordinator.resolvedCompositionFallbackContinuations(
            lockedPrefixText: "我觉得这个方案",
            rawInput: "wo jue de zhege fagnan",
            client: client
        )

        XCTAssertTrue(continuations.contains { $0.text == "还有进一步优化空间" })
    }

    func testLoadedLazyProviderSuppressesNoProviderFallbackContinuations() {
        let client = FakeInputControllerClient()
        let aiProvider = UnavailableAIRecommendationProvider()
        let providerAvailability = AIRecommendationProviderAvailabilityState(.available)
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            aiRecommendationProvider: aiProvider,
            aiRecommendationProviderAvailability: providerAvailability,
            enablesAsyncSuggestionRefresh: true
        )

        let continuations = coordinator.resolvedCompositionFallbackContinuations(
            lockedPrefixText: "我觉得这个方案",
            rawInput: "wo jue de zhege fagnan",
            client: client
        )

        XCTAssertTrue(continuations.isEmpty)
    }

    func testEagerProviderSuppressesNoProviderFallbackContinuations() {
        let client = FakeInputControllerClient()
        let provider = RecordingContinuationProvider()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            provider: provider,
            enablesAsyncSuggestionRefresh: true
        )

        let continuations = coordinator.resolvedCompositionFallbackContinuations(
            lockedPrefixText: "我觉得这个方案",
            rawInput: "wo jue de zhege fagnan",
            client: client
        )

        XCTAssertTrue(continuations.isEmpty)
    }

    @MainActor
    func testTabCommitsVisibleNoProviderFallbackContinuation() async throws {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "wo jue de zhege fagnan" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }

        let hasFallbackContinuation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.continuationCandidates.contains {
                $0.text == "还有进一步优化空间"
            } == true
        }
        XCTAssertTrue(hasFallbackContinuation)
        let viewModel = try XCTUnwrap(host.panelStates.last?.windowState.viewModel)
        let prefix = try XCTUnwrap(viewModel.prefixCandidates.first?.text)
        let continuation = try XCTUnwrap(viewModel.continuationCandidates.first?.text)
        client.markedRangeValue = NSRange(location: 99, length: 2)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\t", keyCode: 48),
                client: client
            )
        )

        XCTAssertEqual(client.insertTextWrites.last?.text, "\(prefix)\(continuation)")
        XCTAssertEqual(
            client.insertTextWrites.last?.replacementRange,
            NSRange(location: NSNotFound, length: NSNotFound)
        )
    }

    @MainActor
    func testPendingAIRecommendationKeepsSecondSlotAndTabDoesNotCommit() async {
        let client = FakeInputControllerClient()
        let provider = RecordingContinuationProvider()
        let aiProvider = PendingAIRecommendationProvider()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: provider,
            aiRecommendationProvider: aiProvider,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasPendingAI = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText == "AI 推荐中..."
        }
        XCTAssertTrue(hasPendingAI)
        let viewModel = host.panelStates.last?.windowState.viewModel
        let rendered = CandidatePanelRenderer(locale: .zhCN).render(viewModel!)

        XCTAssertEqual(viewModel?.aiRecommendation.displayText, "AI 推荐中...")
        XCTAssertEqual(rendered.rows.prefix(2).map(\.kind), [.prefixCandidate, .aiRecommendation])
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\t", keyCode: 48),
                client: client
            )
        )
        XCTAssertEqual(client.insertTextWrites.count, 0)
        XCTAssertEqual(coordinator.composedString() as? String, "zhegeapi")
    }

    @MainActor
    func testAIRecommendationDiagnosticsRecordTransportCancellationOnNewInput() async {
        let client = FakeInputControllerClient()
        let provider = RecordingContinuationProvider()
        let aiProvider = PendingAIRecommendationProvider()
        let diagnosticSink = RecordingDiagnosticSink()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            provider: provider,
            aiRecommendationProvider: aiProvider,
            aiDiagnosticSink: diagnosticSink,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasTransportStarted = await waitUntilOnMainActor {
            diagnosticSink.events.contains { $0.stage == .transportStarted }
        }
        XCTAssertTrue(hasTransportStarted)
        let staleRequestID = diagnosticSink.events.last { $0.stage == .transportStarted }?.requestID

        XCTAssertTrue(coordinator.handleText("x", client: client))
        let hasStaleTransport = await waitUntilOnMainActor {
            diagnosticSink.events.contains {
                $0.stage == .cancelPrevious && $0.requestID == staleRequestID
            } && diagnosticSink.events.contains {
                $0.stage == .transportLeftStale && $0.requestID == staleRequestID
            } && diagnosticSink.events.contains {
                $0.stage == .transportCancellationRequested && $0.requestID == staleRequestID
            } && diagnosticSink.events.contains {
                $0.stage == .transportCancelledByNewInput && $0.requestID == staleRequestID
            }
        }

        XCTAssertTrue(hasStaleTransport, "\(diagnosticSink.events.map(\.stage))")
        let hasCancelledTransport = await waitUntilOnMainActor {
            diagnosticSink.events.contains {
                $0.stage == .cancelled && $0.requestID == staleRequestID
            }
        }
        XCTAssertTrue(hasCancelledTransport, "\(diagnosticSink.events.map(\.stage))")
    }

    @MainActor
    func testAIRecommendationDiagnosticsRecordReleasedCoordinatorStaleDrop() async {
        let client = FakeInputControllerClient()
        let provider = RecordingContinuationProvider()
        let aiProvider = DelayedAIRecommendationProvider(delayNanoseconds: 20_000_000)
        let diagnosticSink = RecordingDiagnosticSink()
        var coordinator: InputControllerCoordinator? = makeCoordinator(
            client: client,
            provider: provider,
            aiRecommendationProvider: aiProvider,
            aiDiagnosticSink: diagnosticSink,
            enablesAsyncSuggestionRefresh: true
        ).0

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator?.handleText(String(character), client: client) == true)
        }
        let hasScheduled = await waitUntilOnMainActor {
            diagnosticSink.events.contains { $0.stage == .scheduled }
        }
        XCTAssertTrue(hasScheduled)

        coordinator = nil
        let hasStaleDrop = await waitUntilOnMainActor {
            diagnosticSink.events.contains {
                $0.stage == .staleResultDropped && $0.reason == "coordinator_released"
            }
        }

        XCTAssertTrue(hasStaleDrop, "\(diagnosticSink.events.map(\.stage))")
    }

    @MainActor
    func testCompletedAIRecommendationDoesNotEmitCancelPreviousOnNextSchedule() async {
        let client = FakeInputControllerClient()
        let provider = RecordingContinuationProvider()
        let aiProvider = RecordingAIRecommendationProvider()
        let diagnosticSink = RecordingDiagnosticSink()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            provider: provider,
            aiRecommendationProvider: aiProvider,
            aiDiagnosticSink: diagnosticSink,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasApplied = await waitUntilOnMainActor {
            diagnosticSink.events.contains { $0.stage == .stateApplied }
        }
        XCTAssertTrue(hasApplied)
        let cancelCountAfterCompletion = diagnosticSink.events.filter {
            $0.stage == .cancelPrevious
        }.count

        XCTAssertTrue(coordinator.handleText("x", client: client))
        let hasLaterSchedule = await waitUntilOnMainActor {
            diagnosticSink.events.filter { $0.stage == .scheduled }.count >= 2
        }
        XCTAssertTrue(hasLaterSchedule)

        XCTAssertEqual(
            diagnosticSink.events.filter { $0.stage == .cancelPrevious }.count,
            cancelCountAfterCompletion
        )
    }

    @MainActor
    func testInvalidatingCompositionLogsActiveAIRequestID() async {
        let client = FakeInputControllerClient()
        let provider = RecordingContinuationProvider()
        let aiProvider = PendingAIRecommendationProvider()
        let diagnosticSink = RecordingDiagnosticSink()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            provider: provider,
            aiRecommendationProvider: aiProvider,
            aiDiagnosticSink: diagnosticSink,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasScheduled = await waitUntilOnMainActor {
            diagnosticSink.events.contains { $0.stage == .scheduled }
        }
        XCTAssertTrue(hasScheduled)
        let cancelledRequestID = diagnosticSink.events.last { $0.stage == .scheduled }?.requestID

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\u{1B}", keyCode: 53),
                client: client
            )
        )
        let hasInvalidationCancel = await waitUntilOnMainActor {
            diagnosticSink.events.contains {
                $0.stage == .cancelPrevious
                    && $0.requestID == cancelledRequestID
                    && $0.reason == "composition_invalidated"
            }
        }

        XCTAssertTrue(hasInvalidationCancel, "\(diagnosticSink.events)")
    }

    @MainActor
    func testStartedAIRecommendationDoesNotApplyAfterInputControllerWillClose() async {
        let client = FakeInputControllerClient()
        let provider = RecordingContinuationProvider()
        let aiProvider = PendingAIRecommendationProvider()
        let diagnosticSink = RecordingDiagnosticSink()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: provider,
            aiRecommendationProvider: aiProvider,
            aiDiagnosticSink: diagnosticSink,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasTransportStarted = await waitUntilOnMainActor {
            diagnosticSink.events.contains { $0.stage == .transportStarted }
        }
        XCTAssertTrue(hasTransportStarted)
        let staleRequestID = diagnosticSink.events.last { $0.stage == .transportStarted }?.requestID

        coordinator.inputControllerWillClose()
        let panelUpdatesAfterClose = host.panelStates.count
        let hasStaleTransportBeforeApply = await waitUntilOnMainActor {
            diagnosticSink.events.contains {
                $0.stage == .cancelPrevious
                    && $0.requestID == staleRequestID
                    && $0.reason == "input_controller_will_close"
            } && diagnosticSink.events.contains {
                $0.stage == .transportLeftStale
                    && $0.requestID == staleRequestID
                    && $0.reason == "input_controller_will_close"
            } && diagnosticSink.events.contains {
                $0.stage == .transportCancellationRequested
                    && $0.requestID == staleRequestID
                    && $0.reason == "input_controller_will_close"
            }
        }

        XCTAssertTrue(hasStaleTransportBeforeApply, "\(diagnosticSink.events.map(\.stage))")
        let hasCancelledTransport = await waitUntilOnMainActor {
            diagnosticSink.events.contains {
                $0.stage == .cancelled && $0.requestID == staleRequestID
            }
        }
        XCTAssertTrue(hasCancelledTransport, "\(diagnosticSink.events.map(\.stage))")
        XCTAssertEqual(host.panelStates.count, panelUpdatesAfterClose)
        XCTAssertEqual(host.hideCandidatePanelCount, 1)
    }

    @MainActor
    func testReturnedAIRecommendationDoesNotApplyAfterInputControllerWillClose() async {
        let client = FakeInputControllerClient()
        let provider = RecordingContinuationProvider()
        let returnSignal = RecommendationReturnSignal()
        let aiProvider = SignaledAIRecommendationProvider(returnSignal: returnSignal)
        let diagnosticSink = RecordingDiagnosticSink()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: provider,
            aiRecommendationProvider: aiProvider,
            aiDiagnosticSink: diagnosticSink,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasScheduled = await waitUntilOnMainActor {
            diagnosticSink.events.contains { $0.stage == .scheduled }
        }
        XCTAssertTrue(hasScheduled)
        let cancelledRequestID = diagnosticSink.events.last { $0.stage == .scheduled }?.requestID

        let didStartReturning = await waitUntilOnMainActor {
            returnSignal.isSignaled
        }
        XCTAssertTrue(didStartReturning)
        usleep(20_000)
        coordinator.inputControllerWillClose()
        let panelUpdatesAfterClose = host.panelStates.count

        let hasTerminalEvent = await waitUntilOnMainActor {
            diagnosticSink.events.contains {
                $0.stage == .cancelled && $0.requestID == cancelledRequestID
            } || diagnosticSink.events.contains {
                $0.stage == .staleResultDropped
                    && $0.requestID == cancelledRequestID
                    && $0.reason == "request_inactive"
            }
        }

        XCTAssertTrue(hasTerminalEvent, "\(diagnosticSink.events)")
        XCTAssertFalse(
            diagnosticSink.events.contains {
                $0.stage == .stateApplied && $0.requestID == cancelledRequestID
            },
            "\(diagnosticSink.events)"
        )
        XCTAssertEqual(host.panelStates.count, panelUpdatesAfterClose)
        XCTAssertEqual(host.hideCandidatePanelCount, 1)
    }

    @MainActor
    func testAsyncRawIdentityVisibleSpaceDoesNotCommitHiddenAlternative() async {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "vxqz" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasPrefix = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.isEmpty == false
        }
        XCTAssertTrue(hasPrefix)

        let visiblePrefix = host.panelStates.last?.windowState.viewModel.prefixCandidates.first?.text
        XCTAssertEqual(visiblePrefix, "vxqz")
        XCTAssertTrue(coordinator.handleText(" ", client: client))
        XCTAssertEqual(client.insertTextWrites.last?.text, visiblePrefix)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testTerminalAppDefaultsToAsciiPassthroughWithoutComposition() {
        let client = FakeInputControllerClient()
        client.bundleIdentifier = "com.apple.Terminal"
        let (coordinator, _, _) = makeCoordinator(client: client)

        XCTAssertFalse(coordinator.handleText("a", client: client))
        XCTAssertFalse(coordinator.handleText("1", client: client))
        XCTAssertFalse(coordinator.handleText(" ", client: client))
        XCTAssertFalse(coordinator.handleText(".", client: client))

        XCTAssertTrue(client.markedTextWrites.isEmpty)
        XCTAssertTrue(client.insertTextWrites.isEmpty)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testCodexDefaultsToChineseInlineComposition() {
        let client = FakeInputControllerClient()
        client.bundleIdentifier = "com.openai.codex"
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertEqual(client.markedTextWrites.last?.text, "n")
        XCTAssertEqual(client.markedTextWrites.last?.isAttributed, true)
        XCTAssertNil(host.panelStates.last?.windowState.viewModel.preeditDisplayText)
        XCTAssertEqual(
            client.markedTextWrites.last?.attributeKeyNames,
            Set([
                InputClientMarkedText.tsmUnderlineAttribute.rawValue,
                InputClientMarkedText.tsmMarkedClauseSegmentAttribute.rawValue
            ])
        )
        XCTAssertEqual(client.markedTextWrites.last?.selectionRange, NSRange(location: 1, length: 0))
        XCTAssertEqual(
            client.markedTextWrites.last?.replacementRange,
            NSRange(location: NSNotFound, length: NSNotFound)
        )
        XCTAssertTrue(coordinator.handleText("i", client: client))
        let windowState = host.panelStates.last?.windowState
        XCTAssertNil(windowState?.viewModel.preeditDisplayText)
        let rendered = windowState.map {
            CandidatePanelRenderer(locale: .zhCN).render(
                $0.viewModel,
                selected: $0.selection,
                paging: $0.paging
            )
        }
        XCTAssertFalse(rendered?.rows.contains(where: { $0.kind == .preedit }) ?? true)
        XCTAssertEqual(rendered?.rows.first?.shortcutLabel, "1")
        let firstCandidate = windowState?.viewModel.prefixCandidates.first?.text
        XCTAssertNotNil(firstCandidate)

        XCTAssertEqual(client.markedTextWrites.map(\.text), ["n", "ni"])
        XCTAssertTrue(client.markedTextWrites.allSatisfy(\.isAttributed))
        XCTAssertGreaterThan(host.scheduledOperations.count, 0)
        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(client.markedTextWrites.last?.text, "")
        XCTAssertEqual(client.markedTextWrites.last?.isAttributed, true)
        XCTAssertEqual(Array(client.writeEventKinds.suffix(2)), ["markedText", "insertText"])
        XCTAssertEqual(client.insertTextWrites.last?.text, firstCandidate)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testTerminalOptionSlashEntersChineseCommitOnlyComposition() {
        let client = FakeInputControllerClient()
        client.bundleIdentifier = "com.apple.Terminal"
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "/", keyCode: 44, modifiers: [.option]),
                client: client
            )
        )
        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("i", client: client))
        let windowState = host.panelStates.last?.windowState
        XCTAssertEqual(windowState?.viewModel.preeditDisplayText, "ni")
        let renderedKinds = windowState.map {
            CandidatePanelRenderer(locale: .zhCN).render(
                $0.viewModel,
                selected: $0.selection,
                paging: $0.paging
            ).rows.map(\.kind)
        }
        XCTAssertEqual(renderedKinds?.first, .modeStatus)
        XCTAssertTrue(renderedKinds?.contains(.preedit) == true)
        let firstCandidate = windowState?.viewModel.prefixCandidates.first?.text
        XCTAssertNotNil(firstCandidate)

        XCTAssertEqual(Set(client.markedTextWrites.map(\.text)), ["\u{3000}"])
        XCTAssertTrue(client.markedTextWrites.allSatisfy(\.isAttributed))
        XCTAssertGreaterThan(host.scheduledOperations.count, 0)
        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(client.markedTextWrites.last?.text, "")
        XCTAssertEqual(client.markedTextWrites.last?.isAttributed, true)
        XCTAssertEqual(Array(client.writeEventKinds.suffix(2)), ["markedText", "insertText"])
        XCTAssertEqual(client.insertTextWrites.last?.text, firstCandidate)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testInputModeReloadsImmediatelyWhenFocusedBundleChanges() {
        let codeClient = FakeInputControllerClient()
        codeClient.bundleIdentifier = "com.apple.Terminal"
        let textClient = FakeInputControllerClient()
        textClient.bundleIdentifier = "com.apple.TextEdit"
        let (coordinator, _, _) = makeCoordinator(client: codeClient)

        XCTAssertFalse(coordinator.handleText("a", client: codeClient))
        XCTAssertTrue(coordinator.handleText("n", client: textClient))

        XCTAssertEqual(coordinator.composedString() as? String, "n")
        XCTAssertTrue(codeClient.insertTextWrites.isEmpty)
        XCTAssertTrue(textClient.insertTextWrites.isEmpty)
        XCTAssertEqual(textClient.markedTextWrites.last?.text, "n")
    }

    func testTextEditInlineCompositionUsesAttributedMarkedTextCarrier() {
        let client = FakeInputControllerClient()
        client.bundleIdentifier = "com.apple.TextEdit"
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("n", client: client))

        XCTAssertEqual(client.markedTextWrites.last?.text, "n")
        XCTAssertEqual(client.markedTextWrites.last?.isAttributed, true)
        XCTAssertEqual(
            client.markedTextWrites.last?.attributeKeyNames,
            Set([
                InputClientMarkedText.tsmUnderlineAttribute.rawValue,
                InputClientMarkedText.tsmMarkedClauseSegmentAttribute.rawValue
            ])
        )
        XCTAssertNil(host.panelStates.last?.windowState.viewModel.preeditDisplayText)
    }

    func testCodeAppDefaultKeepsIdleOperatorsAsciiWhileAllowingChineseComposition() {
        let client = FakeInputControllerClient()
        client.bundleIdentifier = "com.openai.codex"
        let (coordinator, _, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("/", client: client))
        XCTAssertTrue(coordinator.handleText("-", client: client))
        XCTAssertTrue(coordinator.handleText("_", client: client))
        XCTAssertTrue(coordinator.handleText("{", client: client))
        XCTAssertTrue(coordinator.handleText("}", client: client))

        XCTAssertEqual(client.insertTextWrites.map(\.text), ["/", "-", "_", "{", "}"])

        XCTAssertTrue(coordinator.handleText("n", client: client))

        XCTAssertEqual(client.markedTextWrites.last?.text, "n")
    }

    func testCodeAppSavedChinesePunctuationPreferenceIsNotOverridden() {
        let client = FakeInputControllerClient()
        client.bundleIdentifier = "com.openai.codex"
        let preferences = InputModePreferences(
            codeAppState: InputModeState(punctuationMode: .chinese, symbolWidth: .halfWidth)
        )
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            inputModePreferences: preferences
        )

        XCTAssertTrue(coordinator.handleText(".", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "。")
    }

    func testMissingClientPrintableInputPassesThroughWithoutComposition() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(client: client)
        host.currentClientValue = nil

        XCTAssertFalse(coordinator.handleText("a", client: nil))

        XCTAssertTrue(client.markedTextWrites.isEmpty)
        XCTAssertTrue(client.insertTextWrites.isEmpty)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testIdleMissingSenderDoesNotUseStaleHostClient() {
        let staleClient = FakeInputControllerClient()
        staleClient.bundleIdentifier = "com.openai.codex"
        let (coordinator, host, _) = makeCoordinator(client: staleClient)
        host.currentClientValue = staleClient

        XCTAssertFalse(coordinator.handleText("a", client: nil))

        XCTAssertTrue(staleClient.markedTextWrites.isEmpty)
        XCTAssertTrue(staleClient.insertTextWrites.isEmpty)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testCommitOnlyCancelClearsOwnedPlaceholderAndHidesPanel() {
        let client = FakeInputControllerClient()
        client.bundleIdentifier = "com.apple.Terminal"
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "/", keyCode: 44, modifiers: [.option]),
                client: client
            )
        )
        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertEqual(client.markedTextWrites.last?.text, "\u{3000}")
        XCTAssertEqual(client.markedTextWrites.last?.isAttributed, true)

        let handled = coordinator.handle(
            stroke: InputKeyStroke(text: "\u{1B}", keyCode: 53),
            client: client
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(client.markedTextWrites.last?.text, "")
        XCTAssertEqual(client.markedTextWrites.last?.isAttributed, true)
        XCTAssertTrue(client.insertTextWrites.isEmpty)
        XCTAssertEqual(host.hideCandidatePanelCount, 1)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testCommitOnlyCancelUsesCallbackClientWhenCurrentHostClientIsMissing() {
        let client = FakeInputControllerClient()
        client.bundleIdentifier = "com.apple.Terminal"
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "/", keyCode: 44, modifiers: [.option]),
                client: client
            )
        )
        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertEqual(client.markedTextWrites.last?.text, "\u{3000}")
        host.currentClientValue = nil

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\u{1B}", keyCode: 53),
                client: client
            )
        )

        XCTAssertEqual(client.markedTextWrites.last?.text, "")
        XCTAssertEqual(client.markedTextWrites.last?.isAttributed, true)
        XCTAssertTrue(client.insertTextWrites.isEmpty)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testCommitOnlyCancelDoesNotDropOwnedMarkWhenCurrentHostClientIsStale() {
        let client = FakeInputControllerClient()
        client.bundleIdentifier = "com.apple.Terminal"
        let staleClient = FakeInputControllerClient()
        staleClient.bundleIdentifier = "com.apple.Terminal"
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "/", keyCode: 44, modifiers: [.option]),
                client: client
            )
        )
        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertEqual(client.markedTextWrites.last?.text, "\u{3000}")
        host.currentClientValue = staleClient

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\u{1B}", keyCode: 53),
                client: client
            )
        )

        XCTAssertEqual(client.markedTextWrites.last?.text, "")
        XCTAssertTrue(staleClient.markedTextWrites.isEmpty)
        XCTAssertTrue(client.insertTextWrites.isEmpty)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testOptionPeriodTogglesCurrentSessionPunctuationMode() {
        let client = FakeInputControllerClient()
        let (coordinator, _, _) = makeCoordinator(client: client)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: ".", keyCode: 47, modifiers: [.option]),
                client: client
            )
        )
        XCTAssertTrue(coordinator.handleText(".", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, ".")
    }

    @MainActor
    func testAsyncPendingPunctuationCommitsFirstNativeCandidateWithoutBlocking() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "ni" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let firstCandidate = host.panelStates.last?.windowState.viewModel.prefixCandidates.first?.text
        XCTAssertNotNil(firstCandidate)
        XCTAssertTrue(coordinator.handleText(",", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, firstCandidate.map { "\($0)，" })
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    @MainActor
    func testAsyncPendingTabKeepsCompositionWhenAIIsNotReady() {
        let client = FakeInputControllerClient()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "ni" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\t", keyCode: 48),
                client: client
            )
        )

        XCTAssertEqual(client.insertTextWrites.count, 0)
        XCTAssertEqual(coordinator.composedString() as? String, "ni")
    }

    @MainActor
    func testAsyncPendingSpaceAppliesRemainingSegmentBeforeCommit() async throws {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "nishishei" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasFirstSegment = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.contains {
                $0.text == "你" && $0.rawRange == KnowTypeCore.TextRange(start: 0, length: 2)
            } == true
        }
        XCTAssertTrue(hasFirstSegment)
        try selectCandidate(
            text: "你",
            rawRange: KnowTypeCore.TextRange(start: 0, length: 2),
            coordinator: coordinator,
            host: host,
            client: client
        )

        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "你是谁")
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    @MainActor
    func testAsyncPendingPunctuationAppliesRemainingSegmentBeforeCommit() async throws {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "nishishei" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasFirstSegment = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.contains {
                $0.text == "你" && $0.rawRange == KnowTypeCore.TextRange(start: 0, length: 2)
            } == true
        }
        XCTAssertTrue(hasFirstSegment)
        try selectCandidate(
            text: "你",
            rawRange: KnowTypeCore.TextRange(start: 0, length: 2),
            coordinator: coordinator,
            host: host,
            client: client
        )

        XCTAssertTrue(coordinator.handleText(",", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "你shishei，")
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    @MainActor
    func testAsyncPendingPunctuationDoesNotApplyPartialFallbackSegment() async throws {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "nishix" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasFirstSegment = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.contains {
                $0.text == "你" && $0.rawRange == KnowTypeCore.TextRange(start: 0, length: 2)
            } == true
        }
        XCTAssertTrue(hasFirstSegment)
        try selectCandidate(
            text: "你",
            rawRange: KnowTypeCore.TextRange(start: 0, length: 2),
            coordinator: coordinator,
            host: host,
            client: client
        )

        XCTAssertTrue(coordinator.handleText(",", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "你shix，")
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    @MainActor
    func testAsyncRawShortcutCommitsRawInputAfterCandidatePanelPublication() async {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasPanel = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.rawInput == "zhegeapi"
                && host.panelStates.last?.windowState.isVisible == true
        }
        XCTAssertTrue(hasPanel)
        XCTAssertEqual(host.panelStates.last?.windowState.viewModel.rawInput, "zhegeapi")
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "0", keyCode: keyCode(forNumber: 0)),
                client: client
            )
        )

        XCTAssertEqual(client.insertTextWrites.last?.text, "zhegeapi")
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    @MainActor
    func testPartialSegmentRefreshDoesNotAskProvider() async throws {
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
        let hasFirstSegment = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.contains {
                $0.text == "你" && $0.rawRange == KnowTypeCore.TextRange(start: 0, length: 2)
            } == true
        }
        XCTAssertTrue(hasFirstSegment)

        let requestsBeforeSegment = await provider.requests
        try selectCandidate(
            text: "你",
            rawRange: KnowTypeCore.TextRange(start: 0, length: 2),
            coordinator: coordinator,
            host: host,
            client: client
        )
        let hasSecondSegment = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.contains {
                $0.text == "是谁" && $0.rawRange == KnowTypeCore.TextRange(start: 2, length: 7)
            } == true
        }
        XCTAssertTrue(hasSecondSegment)
        let requestsAfterSegment = await provider.requests
        XCTAssertGreaterThanOrEqual(requestsAfterSegment.count, requestsBeforeSegment.count)
        XCTAssertFalse(requestsAfterSegment.contains { request in
            request.task == .continuation
                && (request.lockedPrefix == "你" || request.lockedPrefix == "你shishei")
        })
    }

    @MainActor
    func testFullyResolvedSegmentSelectionRefreshesAIRecommendationSlot() async throws {
        let client = FakeInputControllerClient()
        let provider = RecordingContinuationProvider()
        let aiProvider = RecordingAIRecommendationProvider()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: provider,
            aiRecommendationProvider: aiProvider,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "nishishei" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasFirstSegment = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.contains {
                $0.text == "你" && $0.rawRange == KnowTypeCore.TextRange(start: 0, length: 2)
            } == true
        }
        XCTAssertTrue(hasFirstSegment)
        try selectCandidate(
            text: "你",
            rawRange: KnowTypeCore.TextRange(start: 0, length: 2),
            coordinator: coordinator,
            host: host,
            client: client
        )
        XCTAssertEqual(client.markedTextWrites.last?.text, "你shishei")

        let hasSecondSegment = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.contains {
                $0.text == "是谁" && $0.rawRange == KnowTypeCore.TextRange(start: 2, length: 7)
            } == true
        }
        XCTAssertTrue(hasSecondSegment)
        try selectCandidate(
            text: "是谁",
            rawRange: KnowTypeCore.TextRange(start: 2, length: 7),
            coordinator: coordinator,
            host: host,
            client: client
        )
        XCTAssertEqual(client.markedTextWrites.last?.text, "你是谁")

        let hasAIRecommendation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText == "你是谁继续推进"
        }
        XCTAssertTrue(hasAIRecommendation)
        let requests = await aiProvider.requests
        XCTAssertTrue(requests.contains { $0.lockedPrefix == "你是谁" })

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\t", keyCode: 48),
                client: client
            )
        )
        XCTAssertEqual(client.insertTextWrites.last?.text, "你是谁继续推进")
    }

    func testConfirmedLockedPrefixTextPreservesUserWhitespaceForAIRequest() {
        let suggestion = SuggestionResponse(
            prefixCandidates: [],
            lockedPrefix: LockedPrefix(
                text: "  我觉得这个方案 \n",
                rawInput: "wojuedezhegefangan",
                candidateID: "test"
            ),
            continuationCandidates: [],
            latencyMs: 0
        )

        XCTAssertEqual(
            InputControllerCoordinator.confirmedLockedPrefixText(for: suggestion),
            "  我觉得这个方案 \n"
        )
    }

    func testConfirmedLockedPrefixTextReturnsNilForWhitespaceOnlyPrefix() {
        let suggestion = SuggestionResponse(
            prefixCandidates: [],
            lockedPrefix: LockedPrefix(
                text: " \n\t ",
                rawInput: " ",
                candidateID: "test"
            ),
            continuationCandidates: [],
            latencyMs: 0
        )

        XCTAssertNil(InputControllerCoordinator.confirmedLockedPrefixText(for: suggestion))
    }

    @MainActor
    func testAIRecommendationRequestDropsRealtimeCandidateHints() async throws {
        let client = FakeInputControllerClient()
        let provider = RecordingContinuationProvider()
        let aiProvider = RecordingAIRecommendationProvider()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: provider,
            aiRecommendationProvider: aiProvider,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasAIRecommendation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText == "继续推进"
        }
        XCTAssertTrue(hasAIRecommendation)
        let requests = await aiProvider.requests
        let request = try XCTUnwrap(requests.last)

        XCTAssertNil(request.lockedPrefix)
        XCTAssertEqual(request.rawInput, "zhegeapi")
        XCTAssertEqual(request.candidateHints, [])
        XCTAssertFalse(request.lexicalContext?.markdown.contains("这个 API") == true)
        XCTAssertFalse(request.lexicalContext?.sourceSummary.contains { $0.hasPrefix("rime-candidates: ") } == true)
    }

    @MainActor
    func testAIRecommendationSchedulesForThreeCharacterRawInputWithoutHints() async throws {
        let client = FakeInputControllerClient()
        let provider = RecordingContinuationProvider()
        let aiProvider = RecordingAIRecommendationProvider()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: provider,
            aiRecommendationProvider: aiProvider,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "api" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasAIRecommendation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText == "继续推进"
        }
        XCTAssertTrue(hasAIRecommendation)
        let requests = await aiProvider.requests
        let request = try XCTUnwrap(requests.last)

        XCTAssertNil(request.lockedPrefix)
        XCTAssertEqual(request.rawInput, "api")
        XCTAssertEqual(request.candidateHints, [])
    }

    @MainActor
    func testAIRecommendationRequestMergesPersistentLexicalProfile() async throws {
        let client = FakeInputControllerClient()
        let provider = RecordingContinuationProvider()
        let aiProvider = RecordingAIRecommendationProvider()
        let lexicalStore = LexicalProfileStore.inMemory()
        let persisted = try XCTUnwrap(
            LexicalContextBuilder().snapshot(
                persistentTerms: [
                    LexicalContextTerm(text: "长期高频", score: 1, source: "rime-userdb")
                ],
                persistentSourceSummary: ["rime-userdb-snapshot: abc123"]
            )
        )
        try lexicalStore.save(
            snapshot: persisted,
            schemaID: "pinyin_simp",
            rimeSnapshotURL: nil,
            rimeSnapshotModifiedAt: nil
        )
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: provider,
            aiRecommendationProvider: aiProvider,
            lexicalProfileStore: lexicalStore,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasAIRecommendation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText == "继续推进"
        }
        XCTAssertTrue(hasAIRecommendation)
        let requests = await aiProvider.requests
        let request = try XCTUnwrap(requests.last)

        XCTAssertEqual(request.candidateHints, [])
        XCTAssertTrue(request.lexicalContext?.markdown.contains("长期高频") == true)
        XCTAssertTrue(request.lexicalContext?.sourceSummary.contains("rime-userdb: 1") == true)
    }

    @MainActor
    func testAIRecommendationIgnoresPersistentLexicalProfileFromDifferentSchema() async throws {
        let client = FakeInputControllerClient()
        let provider = RecordingContinuationProvider()
        let aiProvider = RecordingAIRecommendationProvider()
        let lexicalStore = LexicalProfileStore.inMemory()
        let persisted = try XCTUnwrap(
            LexicalContextBuilder().snapshot(
                persistentTerms: [
                    LexicalContextTerm(text: "双拼高频", score: 1, source: "rime-userdb")
                ],
                persistentSourceSummary: ["rime-userdb-snapshot: stale"]
            )
        )
        try lexicalStore.save(
            snapshot: persisted,
            schemaID: "double_pinyin",
            rimeSnapshotURL: nil,
            rimeSnapshotModifiedAt: nil
        )
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: provider,
            aiRecommendationProvider: aiProvider,
            lexicalProfileStore: lexicalStore,
            enablesAsyncSuggestionRefresh: true,
            conversionEngine: FixtureNativeConversionEngine(activeSchemaID: "pinyin_simp")
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasAIRecommendation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText == "继续推进"
        }
        XCTAssertTrue(hasAIRecommendation)
        let requests = await aiProvider.requests
        let request = try XCTUnwrap(requests.last)

        XCTAssertFalse(request.lexicalContext?.markdown.contains("双拼高频") == true)
        XCTAssertFalse(request.lexicalContext?.sourceSummary.contains("rime-userdb: 1") == true)
    }

    @MainActor
    func testRimeUserDBSnapshotReadDoesNotRunOnPlainKeydown() async throws {
        let client = FakeInputControllerClient()
        let rimeProvider = CountingRimeUserDBTextSnapshotProvider()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            rimeUserDBTextProvider: rimeProvider
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))
        try await Task.sleep(nanoseconds: 650_000_000)

        let requestCount = await rimeProvider.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    @MainActor
    func testLexicalProfileSnapshotReadUsesActiveConversionSchemaIDAfterCommit() async throws {
        let client = FakeInputControllerClient()
        let rimeProvider = CountingRimeUserDBTextSnapshotProvider()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            rimeUserDBTextProvider: rimeProvider,
            conversionEngine: FixtureNativeConversionEngine(activeSchemaID: "custom_schema")
        )

        for character in "ni" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        XCTAssertTrue(coordinator.handleText(" ", client: client))

        for _ in 0..<30 {
            if await rimeProvider.requestCount > 0 {
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        let requestedSchemaIDs = await rimeProvider.requestedSchemaIDs
        XCTAssertEqual(requestedSchemaIDs, ["custom_schema"])
    }

    func testLexicalProfileRefreshGateRejectsStaleGenerations() {
        let gate = LexicalProfileRefreshGate()
        let first = gate.next()
        XCTAssertTrue(gate.isCurrent(first))

        let second = gate.next()

        XCTAssertFalse(gate.isCurrent(first))
        XCTAssertTrue(gate.isCurrent(second))
    }

    func testInputMethodLexicalProfileRuntimeSharesProcessWideState() {
        XCTAssertTrue(InputMethodLexicalProfileRuntime.store === InputMethodLexicalProfileRuntime.store)
        XCTAssertTrue(InputMethodLexicalProfileRuntime.refreshGate === InputMethodLexicalProfileRuntime.refreshGate)
    }

    @MainActor
    func testProtectedAppInputCanUseAIRecommendationButDoesNotReachLaterLexicalProfile() async throws {
        let client = FakeInputControllerClient()
        client.bundleIdentifier = "com.apple.Terminal"
        let provider = RecordingContinuationProvider()
        let aiProvider = RecordingAIRecommendationProvider()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            provider: provider,
            aiRecommendationProvider: aiProvider,
            enablesAsyncSuggestionRefresh: true,
            inputModePreferences: InputModePreferences(
                codeAppState: InputModeState(textMode: .chinese)
            )
        )

        for character in "secretphrase" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        var protectedRequests: [AIRecommendationRequest] = []
        for _ in 0..<60 {
            protectedRequests = await aiProvider.requests
            if !protectedRequests.isEmpty {
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(protectedRequests.isEmpty)
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\r", keyCode: 36),
                client: client
            )
        )

        for character in "wojuedezhegefagnan" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        var requestsAfterProtectedSelection: [AIRecommendationRequest] = []
        for _ in 0..<60 {
            requestsAfterProtectedSelection = await aiProvider.requests
            if requestsAfterProtectedSelection.count > protectedRequests.count {
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertGreaterThan(requestsAfterProtectedSelection.count, protectedRequests.count)
        XCTAssertTrue(coordinator.handleText(" ", client: client))
        XCTAssertFalse(requestsAfterProtectedSelection.isEmpty)

        client.bundleIdentifier = "com.example.host"
        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }

        var unprotectedRequest: AIRecommendationRequest?
        for _ in 0..<60 {
            let requests = await aiProvider.requests
            unprotectedRequest = requests.last { $0.rawInput == "zhegeapi" }
            if unprotectedRequest != nil {
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let request = try XCTUnwrap(unprotectedRequest)
        XCTAssertFalse(request.lexicalContext?.markdown.contains("secretphrase") ?? false)
        XCTAssertFalse(request.lexicalContext?.markdown.contains("我觉得这个方案") ?? false)
    }

    @MainActor
    func testDisabledAIKeepsResolvedCompositionWithoutLocalContinuations() async throws {
        let client = FakeInputControllerClient()
        let aiProvider = RecordingAIRecommendationProvider()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: RecordingContinuationProvider(),
            aiRecommendationProvider: aiProvider,
            enablesAsyncSuggestionRefresh: true,
            runtimePreferences: InputMethodRuntimePreferences(cloudContinuationEnabled: false)
        )

        for character in "nishishei" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasFirstSegment = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.contains {
                $0.text == "你" && $0.rawRange == KnowTypeCore.TextRange(start: 0, length: 2)
            } == true
        }
        XCTAssertTrue(hasFirstSegment)
        try selectCandidate(
            text: "你",
            rawRange: KnowTypeCore.TextRange(start: 0, length: 2),
            coordinator: coordinator,
            host: host,
            client: client
        )
        let hasSecondSegment = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.contains {
                $0.text == "是谁" && $0.rawRange == KnowTypeCore.TextRange(start: 2, length: 7)
            } == true
        }
        XCTAssertTrue(hasSecondSegment)
        try selectCandidate(
            text: "是谁",
            rawRange: KnowTypeCore.TextRange(start: 2, length: 7),
            coordinator: coordinator,
            host: host,
            client: client
        )

        XCTAssertEqual(client.markedTextWrites.last?.text, "你是谁")
        let hasDisabledAIState = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText == "AI 已关闭"
        }
        XCTAssertTrue(hasDisabledAIState)
        XCTAssertEqual(host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText, "AI 已关闭")
        XCTAssertTrue(host.panelStates.last?.windowState.viewModel.continuationCandidates.isEmpty == true)
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\t", keyCode: 48),
                client: client
            )
        )
        XCTAssertEqual(client.insertTextWrites.count, 0)
        XCTAssertEqual(coordinator.composedString() as? String, "你是谁")
    }

    @MainActor
    func testExternalRuntimePreferenceReloadRefreshesVisibleAIState() async throws {
        let client = FakeInputControllerClient()
        let runtimeStore = MutableInputMethodRuntimePreferenceStore(
            preferences: InputMethodRuntimePreferences(cloudContinuationEnabled: true)
        )
        let aiProvider = RecordingAIRecommendationProvider()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: RecordingContinuationProvider(),
            aiRecommendationProvider: aiProvider,
            enablesAsyncSuggestionRefresh: true,
            runtimePreferences: runtimeStore.preferences,
            runtimePreferenceStore: runtimeStore
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasReadyAI = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText == "继续推进"
        }
        XCTAssertTrue(hasReadyAI)

        runtimeStore.preferences = InputMethodRuntimePreferences(cloudContinuationEnabled: false)
        coordinator.reloadRuntimePreferencesForExternalChange()

        XCTAssertFalse(host.panelStates.last?.windowState.viewModel.prefixCandidates.isEmpty == true)
        XCTAssertEqual(host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText, "AI 已关闭")
        XCTAssertTrue(host.panelStates.last?.windowState.viewModel.continuationCandidates.isEmpty == true)
    }

    @MainActor
    func testExternalRuntimePreferenceReloadUsesPreferenceCancellationReasonForActiveAIRequest() async {
        let client = FakeInputControllerClient()
        let runtimeStore = MutableInputMethodRuntimePreferenceStore(
            preferences: InputMethodRuntimePreferences(cloudContinuationEnabled: true)
        )
        let diagnosticSink = RecordingDiagnosticSink()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            provider: RecordingContinuationProvider(),
            aiRecommendationProvider: PendingAIRecommendationProvider(),
            aiDiagnosticSink: diagnosticSink,
            enablesAsyncSuggestionRefresh: true,
            runtimePreferences: runtimeStore.preferences,
            runtimePreferenceStore: runtimeStore
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasScheduled = await waitUntilOnMainActor {
            diagnosticSink.events.contains { $0.stage == .scheduled }
        }
        XCTAssertTrue(hasScheduled)
        let requestID = diagnosticSink.events.last { $0.stage == .scheduled }?.requestID

        runtimeStore.preferences = InputMethodRuntimePreferences(cloudContinuationEnabled: false)
        coordinator.reloadRuntimePreferencesForExternalChange()

        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .cancelPrevious
                && $0.requestID == requestID
                && $0.reason == "runtime_preferences_changed"
        })
    }

    @MainActor
    func testFullyResolvedSegmentSelectionHonorsDisabledLocalContinuationsWithoutProvider() async throws {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true,
            runtimePreferences: InputMethodRuntimePreferences(localContinuationEnabledWhenNoProvider: false)
        )

        for character in "nishishei" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasFirstSegment = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.contains {
                $0.text == "你" && $0.rawRange == KnowTypeCore.TextRange(start: 0, length: 2)
            } == true
        }
        XCTAssertTrue(hasFirstSegment)
        try selectCandidate(
            text: "你",
            rawRange: KnowTypeCore.TextRange(start: 0, length: 2),
            coordinator: coordinator,
            host: host,
            client: client
        )
        let hasSecondSegment = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.contains {
                $0.text == "是谁" && $0.rawRange == KnowTypeCore.TextRange(start: 2, length: 7)
            } == true
        }
        XCTAssertTrue(hasSecondSegment)
        try selectCandidate(
            text: "是谁",
            rawRange: KnowTypeCore.TextRange(start: 2, length: 7),
            coordinator: coordinator,
            host: host,
            client: client
        )

        XCTAssertEqual(client.markedTextWrites.last?.text, "你是谁")
        XCTAssertTrue(
            host.panelStates.last?.windowState.viewModel.continuationCandidates.isEmpty == true
        )
    }

    @MainActor
    func testFullyResolvedSegmentSelectionKeepsNoProviderFallbackContinuations() async throws {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "nishishei" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasFirstSegment = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.contains {
                $0.text == "你" && $0.rawRange == KnowTypeCore.TextRange(start: 0, length: 2)
            } == true
        }
        XCTAssertTrue(hasFirstSegment)
        try selectCandidate(
            text: "你",
            rawRange: KnowTypeCore.TextRange(start: 0, length: 2),
            coordinator: coordinator,
            host: host,
            client: client
        )
        let hasSecondSegment = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.contains {
                $0.text == "是谁" && $0.rawRange == KnowTypeCore.TextRange(start: 2, length: 7)
            } == true
        }
        XCTAssertTrue(hasSecondSegment)
        try selectCandidate(
            text: "是谁",
            rawRange: KnowTypeCore.TextRange(start: 2, length: 7),
            coordinator: coordinator,
            host: host,
            client: client
        )

        let hasContinuation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.continuationCandidates.isEmpty == false
        }
        XCTAssertTrue(hasContinuation)
        let prefix = coordinator.composedString() as? String
        let continuation = try XCTUnwrap(host.panelStates.last?.windowState.viewModel.continuationCandidates.first?.text)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\t", keyCode: 48),
                client: client
            )
        )
        XCTAssertEqual(client.insertTextWrites.last?.text, "\(prefix ?? "")\(continuation)")
    }

    @MainActor
    func testAsyncSuggestionRefreshKeepsProviderCorrectionOffKeyPath() async {
        let client = FakeInputControllerClient()
        let provider = CorrectionFallbackProvider()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: provider,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "zz" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }

        let hasLocalCandidate = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.isEmpty == false
        }
        let requests = await provider.requests

        XCTAssertTrue(hasLocalCandidate)
        XCTAssertFalse(requests.contains { $0.task == .correction })
        XCTAssertFalse(requests.contains { $0.task == .continuation })
    }

    @MainActor
    func testDisabledCloudContinuationDoesNotRecordContextMemoryEvents() async {
        let client = FakeInputControllerClient()
        let recorder = RecordingAIContextEventRecorder()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            aiContextEventRecorder: recorder,
            runtimePreferences: InputMethodRuntimePreferences(cloudContinuationEnabled: false)
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("i", client: client))
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\r", keyCode: 36),
                client: client
            )
        )
        _ = coordinator.handle(
            stroke: InputKeyStroke(text: "", keyCode: 51),
            client: client
        )
        try? await Task.sleep(nanoseconds: 50_000_000)

        let events = await recorder.events
        XCTAssertTrue(events.isEmpty)
    }

    @MainActor
    func testBackspaceClearingCompositionResetsDeleteCountForNextCommit() async {
        let client = FakeInputControllerClient()
        let recorder = RecordingAIContextEventRecorder()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            provider: RecordingContinuationProvider(),
            aiContextEventRecorder: recorder
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "", keyCode: 51),
                client: client
            )
        )
        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("i", client: client))
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\r", keyCode: 36),
                client: client
            )
        )
        try? await Task.sleep(nanoseconds: 50_000_000)

        let events = await recorder.events
        XCTAssertEqual(events.last?.rawInput, "ni")
        XCTAssertEqual(events.last?.deleteCountBeforeCommit, 0)
    }

    @MainActor
    func testNoProviderDoesNotRecordContextMemoryEvents() async {
        let client = FakeInputControllerClient()
        let recorder = RecordingAIContextEventRecorder()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            aiContextEventRecorder: recorder
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("i", client: client))
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\r", keyCode: 36),
                client: client
            )
        )
        try? await Task.sleep(nanoseconds: 50_000_000)

        let events = await recorder.events
        XCTAssertTrue(events.isEmpty)
    }

    @MainActor
    func testNumberTwoCommitsReadyAIRecommendationAfterSegmentResolution() async throws {
        let client = FakeInputControllerClient()
        let provider = RecordingContinuationProvider()
        let aiProvider = RecordingAIRecommendationProvider(continuation: "第二推荐")
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: provider,
            aiRecommendationProvider: aiProvider,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "nishishei" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasFirstSegment = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.contains {
                $0.text == "你" && $0.rawRange == KnowTypeCore.TextRange(start: 0, length: 2)
            } == true
        }
        XCTAssertTrue(hasFirstSegment)
        try selectCandidate(
            text: "你",
            rawRange: KnowTypeCore.TextRange(start: 0, length: 2),
            coordinator: coordinator,
            host: host,
            client: client
        )
        let hasSecondSegment = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.contains {
                $0.text == "是谁" && $0.rawRange == KnowTypeCore.TextRange(start: 2, length: 7)
            } == true
        }
        XCTAssertTrue(hasSecondSegment)
        try selectCandidate(
            text: "是谁",
            rawRange: KnowTypeCore.TextRange(start: 2, length: 7),
            coordinator: coordinator,
            host: host,
            client: client
        )
        let hasAIRecommendation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText == "你是谁第二推荐"
        }
        XCTAssertTrue(hasAIRecommendation)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "2", keyCode: keyCode(forNumber: 2)),
                client: client
            )
        )

        XCTAssertEqual(client.insertTextWrites.last?.text, "你是谁第二推荐")
    }

    @MainActor
    func testSpaceCommitsHighlightedReadyAIRecommendation() async throws {
        let client = FakeInputControllerClient()
        let provider = RecordingContinuationProvider()
        let aiProvider = RecordingAIRecommendationProvider(continuation: "第二推荐")
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: provider,
            aiRecommendationProvider: aiProvider,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "nishishei" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasFirstSegment = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.contains {
                $0.text == "你" && $0.rawRange == KnowTypeCore.TextRange(start: 0, length: 2)
            } == true
        }
        XCTAssertTrue(hasFirstSegment)
        try selectCandidate(
            text: "你",
            rawRange: KnowTypeCore.TextRange(start: 0, length: 2),
            coordinator: coordinator,
            host: host,
            client: client
        )
        let hasSecondSegment = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.prefixCandidates.contains {
                $0.text == "是谁" && $0.rawRange == KnowTypeCore.TextRange(start: 2, length: 7)
            } == true
        }
        XCTAssertTrue(hasSecondSegment)
        try selectCandidate(
            text: "是谁",
            rawRange: KnowTypeCore.TextRange(start: 2, length: 7),
            coordinator: coordinator,
            host: host,
            client: client
        )
        let hasAIRecommendation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText == "你是谁第二推荐"
        }
        XCTAssertTrue(hasAIRecommendation)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\u{F701}", keyCode: 125),
                client: client
            )
        )
        XCTAssertEqual(host.panelStates.last?.windowState.selection, .aiRecommendation)
        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "你是谁第二推荐")
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
        XCTAssertEqual(
            client.markedTextWrites.last?.replacementRange,
            NSRange(location: NSNotFound, length: NSNotFound)
        )
        XCTAssertEqual(host.hideCandidatePanelCount, 1)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testAnchorFailureFallsBackToSafeScreenCandidatePanelLocation() {
        let client = FakeInputControllerClient()
        client.firstRectValue = .zero
        client.lineHeightRectValue = .zero
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("n", client: client))

        XCTAssertEqual(host.panelStates.last?.windowState.anchorSource, .safeScreenFallback)
        XCTAssertTrue(host.panelStates.last?.windowState.isVisible == true)
    }

    func testTransientEmptyNativeSnapshotKeepsRawFallbackPanelVisible() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: TransientEmptySnapshotConversionEngine()
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))

        XCTAssertEqual(host.panelStates.last?.windowState.viewModel.rawInput, "n")
        XCTAssertTrue(host.panelStates.last?.windowState.isVisible == true)
        XCTAssertEqual(host.hideCandidatePanelCount, 0)
    }

    func testDelayedReanchorAppliesOnlyForCurrentComposition() {
        let client = FakeInputControllerClient()
        client.firstRectValue = CGRect(x: 40, y: 500, width: 0, height: 18)
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            enablesAsyncSuggestionRefresh: true
        )

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

    func testDeactivateCommitsRawHidesPanelAndGatesPendingReanchor() {
        let client = FakeInputControllerClient()
        let persistence = FakeUserSelectionHistoryPersistence()
        let (coordinator, host, persistenceSpy) = makeCoordinator(
            client: client,
            persistence: persistence
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))
        let updatesBeforeDeactivate = host.panelStates.count

        coordinator.deactivateServer(client: nil)
        client.firstRectValue = CGRect(x: 200, y: 500, width: 0, height: 18)
        host.runScheduledOperations()

        XCTAssertEqual(persistenceSpy.flushCalls.count, 1)
        XCTAssertEqual(client.insertTextWrites.last?.text, "n")
        XCTAssertEqual(coordinator.composedString() as? String, "")
        XCTAssertEqual(host.panelStates.count, updatesBeforeDeactivate)
        XCTAssertEqual(host.hideCandidatePanelCount, 1)

        coordinator.inputControllerWillClose()

        XCTAssertEqual(persistenceSpy.flushCalls.count, 2)
        XCTAssertEqual(host.hideCandidatePanelCount, 2)
    }

    func testDeactivateWithoutAnyCurrentClientDoesNotCommitOrClearMarkedText() {
        let client = FakeInputControllerClient()
        client.markedRangeValue = NSRange(location: 10, length: 1)
        let persistence = FakeUserSelectionHistoryPersistence()
        let (coordinator, host, persistenceSpy) = makeCoordinator(
            client: client,
            persistence: persistence
        )
        host.currentClientValue = nil

        XCTAssertTrue(coordinator.handleText("n", client: client))

        coordinator.deactivateServer(client: nil)

        XCTAssertEqual(persistenceSpy.flushCalls.count, 1)
        XCTAssertEqual(client.insertTextWrites.count, 0)
        XCTAssertEqual(client.markedTextWrites.last?.text, "n")
        XCTAssertEqual(host.hideCandidatePanelCount, 1)
        XCTAssertEqual(coordinator.composedString() as? String, "")
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
            .placeholder("你"),
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
        XCTAssertEqual(imkClient.markedTextWrites[0].isAttributed, true)
        XCTAssertEqual(
            imkClient.markedTextWrites[0].attributeKeyNames,
            Set([
                InputClientMarkedText.tsmUnderlineAttribute.rawValue,
                InputClientMarkedText.tsmMarkedClauseSegmentAttribute.rawValue
            ])
        )
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

    func testAdaptiveRuntimePreferencesCapCandidatePanelPageSizeAtSix() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            runtimePreferences: InputMethodRuntimePreferences(
                candidatePageSize: 9,
                candidateLayoutMode: .adaptive
            )
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))

        XCTAssertEqual(host.panelStates.last?.windowState.paging.pageSize, 6)
        XCTAssertEqual(host.panelStates.last?.windowState.layoutMode, .adaptive)
    }

    func testVerticalRuntimePreferencesKeepConfiguredCandidatePanelPageSize() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            runtimePreferences: InputMethodRuntimePreferences(
                candidatePageSize: 9,
                candidateLayoutMode: .verticalPreferred
            )
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))

        XCTAssertEqual(host.panelStates.last?.windowState.paging.pageSize, 9)
        XCTAssertEqual(host.panelStates.last?.windowState.layoutMode, .verticalPreferred)
    }

    func testNativePageDownKeyRefreshesRimeCurrentPageSnapshot() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: PagedNativeConversionEngine()
        )

        XCTAssertTrue(coordinator.handleText("s", client: client))
        XCTAssertEqual(
            host.panelStates.last?.windowState.viewModel.prefixCandidates.map(\.text),
            ["第一页一", "第一页二"]
        )

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\u{F72D}", keyCode: 121),
                client: client
            )
        )

        XCTAssertEqual(
            host.panelStates.last?.windowState.viewModel.prefixCandidates.map(\.text),
            ["第二页一", "第二页二"]
        )
        XCTAssertTrue(client.insertTextWrites.isEmpty)
    }

    func testNativePageKeysUpdateRimeSnapshotWhenPanelIsHidden() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: PagedNativeConversionEngine(),
            screenProvider: FixedInputControllerScreenProvider(screens: [])
        )

        XCTAssertTrue(coordinator.handleText("s", client: client))
        XCTAssertEqual(host.candidatePanelFrames.last?.isVisible, false)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\u{F72D}", keyCode: 121),
                client: client
            )
        )
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: " ", keyCode: 49),
                client: client
            )
        )

        XCTAssertEqual(client.insertTextWrites.last?.text, "第二页一")
    }

    func testNativeRightArrowPagesRimeSnapshotAtCurrentPageBoundary() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: PagedNativeConversionEngine()
        )

        XCTAssertTrue(coordinator.handleText("s", client: client))

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\u{F703}", keyCode: 124),
                client: client
            )
        )
        XCTAssertEqual(host.panelStates.last?.windowState.selection, .fullCandidate(1))
        XCTAssertEqual(
            host.panelStates.last?.windowState.viewModel.prefixCandidates.map(\.text),
            ["第一页一", "第一页二"]
        )

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\u{F703}", keyCode: 124),
                client: client
            )
        )
        XCTAssertEqual(
            host.panelStates.last?.windowState.viewModel.prefixCandidates.map(\.text),
            ["第二页一", "第二页二"]
        )
        XCTAssertEqual(host.panelStates.last?.windowState.selection, .fullCandidate(0))
        XCTAssertTrue(client.insertTextWrites.isEmpty)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\u{F702}", keyCode: 123),
                client: client
            )
        )
        XCTAssertEqual(
            host.panelStates.last?.windowState.viewModel.prefixCandidates.map(\.text),
            ["第一页一", "第一页二"]
        )
        XCTAssertEqual(host.panelStates.last?.windowState.selection, .fullCandidate(1))
        XCTAssertTrue(coordinator.handleText(" ", client: client))
        XCTAssertEqual(client.insertTextWrites.last?.text, "第一页二")
    }

    func testNativeArrowFallsBackToPanelSelectionWhenHighlightIsUnavailable() {
        let client = FakeInputControllerClient()
        let recorder = NativeSelectionRecorder()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["候一", "候二"],
                recorder: recorder,
                spaceCommit: "native-space",
                handlesHighlight: false
            )
        )

        for character in "hou" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\u{F703}", keyCode: 124),
                client: client
            )
        )

        XCTAssertEqual(host.panelStates.last?.windowState.selection, .fullCandidate(1))
        XCTAssertEqual(recorder.highlightedIndices, [])
        XCTAssertTrue(coordinator.handleText(" ", client: client))
        XCTAssertEqual(recorder.selectedIndices, [1])
        XCTAssertEqual(recorder.spaceProcessCount, 0)
        XCTAssertEqual(client.insertTextWrites.last?.text, "候二")
    }

    func testNativeNumberSelectionWorksWhenPanelIsHidden() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: PagedNativeConversionEngine(),
            screenProvider: FixedInputControllerScreenProvider(screens: [])
        )

        XCTAssertTrue(coordinator.handleText("s", client: client))
        XCTAssertEqual(host.candidatePanelFrames.last?.isVisible, false)
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "2", keyCode: keyCode(forNumber: 2)),
                client: client
            )
        )

        XCTAssertEqual(client.insertTextWrites.last?.text, "第一页二")
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testNativeNumberSelectionRecordsSelectionHistory() {
        let client = FakeInputControllerClient()
        let persistence = FakeUserSelectionHistoryPersistence()
        let recorder = NativeSelectionRecorder()
        let (coordinator, _, persistenceSpy) = makeCoordinator(
            client: client,
            persistence: persistence,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["你", "尼"],
                recorder: recorder
            )
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "2", keyCode: keyCode(forNumber: 2)),
                client: client
            )
        )

        XCTAssertEqual(recorder.selectedIndices, [1])
        XCTAssertEqual(client.insertTextWrites.last?.text, "尼")
        XCTAssertEqual(persistenceSpy.recordedSelections, ["尼"])
    }

    @MainActor
    func testNativeNumberSelectionDoesNotCommitReadyAIRecommendation() async {
        let client = FakeInputControllerClient()
        let recorder = NativeSelectionRecorder()
        let aiProvider = RecordingAIRecommendationProvider(continuation: "AI 续写")
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            provider: RecordingContinuationProvider(),
            aiRecommendationProvider: aiProvider,
            enablesAsyncSuggestionRefresh: true,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["你", "尼"],
                recorder: recorder
            )
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        let requests = await aiProvider.requests
        XCTAssertFalse(requests.isEmpty)
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "2", keyCode: keyCode(forNumber: 2)),
                client: client
            )
        )

        XCTAssertEqual(recorder.selectedIndices, [1])
        XCTAssertEqual(client.insertTextWrites.last?.text, "尼")
    }

    func testNativeCandidateOnlySnapshotKeepsNumberSelectionActive() {
        let client = FakeInputControllerClient()
        let recorder = NativeSelectionRecorder()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            conversionEngine: CandidateOnlyNativeConversionEngine(
                candidates: ["候一", "候二"],
                recorder: recorder
            )
        )

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "2", keyCode: keyCode(forNumber: 2)),
                client: client
            )
        )

        XCTAssertEqual(recorder.selectedIndices, [1])
        XCTAssertEqual(client.insertTextWrites.last?.text, "候二")
    }

    func testNativeOutOfRangeNumberIsConsumedWithoutAppendingDigit() {
        let client = FakeInputControllerClient()
        let recorder = NativeSelectionRecorder()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["你"],
                recorder: recorder
            )
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "9", keyCode: keyCode(forNumber: 9)),
                client: client
            )
        )

        XCTAssertEqual(recorder.selectedIndices, [])
        XCTAssertTrue(client.insertTextWrites.isEmpty)
        XCTAssertEqual(coordinator.composedString() as? String, "n")
    }

    @MainActor
    func testOptionOneAIRecommendationDoesNotRecordPrefixSelectionHistory() async {
        let client = FakeInputControllerClient()
        let persistence = FakeUserSelectionHistoryPersistence()
        let aiProvider = RecordingAIRecommendationProvider(continuation: "AI 续写")
        let acceptedLearning = AIAcceptedLearningStore.inMemory()
        let (coordinator, host, persistenceSpy) = makeCoordinator(
            client: client,
            persistence: persistence,
            provider: RecordingContinuationProvider(),
            aiRecommendationProvider: aiProvider,
            aiAcceptedLearning: acceptedLearning,
            enablesAsyncSuggestionRefresh: true,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["你"],
                recorder: NativeSelectionRecorder()
            )
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasAIRecommendation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText == "AI 续写"
        }
        XCTAssertTrue(hasAIRecommendation)
        client.markedRangeValue = NSRange(location: 99, length: 2)
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "1", keyCode: keyCode(forNumber: 1), modifiers: [.option]),
                client: client
            )
        )

        XCTAssertEqual(client.insertTextWrites.last?.text, "AI 续写")
        XCTAssertEqual(
            client.insertTextWrites.last?.replacementRange,
            NSRange(location: NSNotFound, length: NSNotFound)
        )
        XCTAssertTrue(persistenceSpy.recordedSelections.isEmpty)
        let recorded = await waitUntilOnMainActor {
            acceptedLearning.allRecords().count == 1
        }
        XCTAssertTrue(recorded)
        XCTAssertEqual(acceptedLearning.allRecords().first?.acceptedText, "AI 续写")
    }

    @MainActor
    func testTabAcceptedAIRecommendationRecordsAcceptedLearningHistory() async throws {
        let client = FakeInputControllerClient()
        let aiProvider = RecordingAIRecommendationProvider(continuation: "JSON Schema 可以继续")
        let acceptedLearning = AIAcceptedLearningStore.inMemory()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: RecordingContinuationProvider(),
            aiRecommendationProvider: aiProvider,
            aiAcceptedLearning: acceptedLearning,
            enablesAsyncSuggestionRefresh: true,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["这个API"],
                recorder: NativeSelectionRecorder()
            )
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasAIRecommendation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText == "JSON Schema 可以继续"
        }
        XCTAssertTrue(hasAIRecommendation)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\t", keyCode: 48),
                client: client
            )
        )

        let recorded = await waitUntilOnMainActor {
            acceptedLearning.allRecords().count == 1
                && acceptedLearning.snapshot()?.termProfile.contains { $0.text == "JSON" } == true
        }
        XCTAssertTrue(recorded)
        let record = try XCTUnwrap(acceptedLearning.allRecords().first)
        XCTAssertEqual(record.rawInput, "zhegeapi")
        XCTAssertEqual(record.acceptedText, "JSON Schema 可以继续")
        XCTAssertEqual(record.provider, "ai-test")
        XCTAssertEqual(record.commitKind, "ai")
        XCTAssertEqual(record.candidateSource, "ai:ai-test")
        XCTAssertTrue(record.extractedTerms.contains { $0.text == "JSON" })
        XCTAssertTrue(acceptedLearning.snapshot()?.termProfile.contains { $0.text == "JSON" } == true)
    }

    @MainActor
    func testAIAcceptedCommitUsesImmediatePostInsertVerificationSeam() async throws {
        let client = FakeInputControllerClient()
        let aiProvider = RecordingAIRecommendationProvider(continuation: "JSON Schema 可以继续")
        let acceptedFeedback = AIAcceptedFeedbackStore.inMemory()
        let diagnosticSink = RecordingDiagnosticSink()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: RecordingContinuationProvider(),
            aiRecommendationProvider: aiProvider,
            aiAcceptedFeedback: acceptedFeedback,
            aiDiagnosticSink: diagnosticSink,
            enablesAsyncSuggestionRefresh: true,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["这个API"],
                recorder: NativeSelectionRecorder()
            )
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasAIRecommendation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText == "JSON Schema 可以继续"
        }
        XCTAssertTrue(hasAIRecommendation)
        host.runScheduledOperations()
        XCTAssertTrue(host.scheduledOperations.isEmpty)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\t", keyCode: 48),
                client: client
            )
        )

        let acceptedText = try XCTUnwrap(client.insertTextWrites.last?.text)
        XCTAssertTrue(host.scheduledOperations.isEmpty)
        XCTAssertEqual(host.postInsertVerificationOperations.count, 1)

        client.selectedRangeValue = NSRange(
            location: 10 + (acceptedText as NSString).length,
            length: 0
        )
        host.runPostInsertVerificationOperations()
        XCTAssertTrue(host.postInsertVerificationOperations.isEmpty)

        XCTAssertFalse(
            coordinator.handle(
                stroke: InputKeyStroke(text: "", keyCode: 51),
                client: client
            )
        )
        XCTAssertFalse(diagnosticSink.events.contains {
            $0.stage == .acceptedFeedbackTrackingCancelled
                && $0.reason == "delete_before_verified"
        })
    }

    @MainActor
    func testProtectedAppAcceptedAIRecommendationDoesNotRecordAcceptedLearningHistory() async throws {
        let client = FakeInputControllerClient()
        client.bundleIdentifier = "com.apple.Terminal"
        let aiProvider = RecordingAIRecommendationProvider(continuation: "JSON Schema 可以继续")
        let acceptedLearning = AIAcceptedLearningStore.inMemory()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: RecordingContinuationProvider(),
            aiRecommendationProvider: aiProvider,
            aiAcceptedLearning: acceptedLearning,
            enablesAsyncSuggestionRefresh: true,
            inputModePreferences: InputModePreferences(
                codeAppState: InputModeState(textMode: .chinese)
            ),
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["这个API"],
                recorder: NativeSelectionRecorder()
            )
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasAIRecommendation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText == "JSON Schema 可以继续"
        }
        XCTAssertTrue(hasAIRecommendation)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\t", keyCode: 48),
                client: client
            )
        )

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(client.insertTextWrites.last?.text, "JSON Schema 可以继续")
        XCTAssertTrue(acceptedLearning.allRecords().isEmpty)
        XCTAssertNil(acceptedLearning.snapshot())
    }

    @MainActor
    func testProtectedAppAcceptedAIRecommendationDoesNotRecordAcceptedFeedback() async throws {
        let client = FakeInputControllerClient()
        client.bundleIdentifier = "com.apple.Terminal"
        let aiProvider = RecordingAIRecommendationProvider(continuation: "JSON Schema 可以继续")
        let acceptedFeedback = AIAcceptedFeedbackStore.inMemory()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: RecordingContinuationProvider(),
            aiRecommendationProvider: aiProvider,
            aiAcceptedFeedback: acceptedFeedback,
            enablesAsyncSuggestionRefresh: true,
            inputModePreferences: InputModePreferences(
                codeAppState: InputModeState(textMode: .chinese)
            ),
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["这个API"],
                recorder: NativeSelectionRecorder()
            )
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasAIRecommendation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText == "JSON Schema 可以继续"
        }
        XCTAssertTrue(hasAIRecommendation)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\t", keyCode: 48),
                client: client
            )
        )
        client.selectedRangeValue = NSRange(location: 10 + ("JSON Schema 可以继续" as NSString).length, length: 0)
        host.runPostInsertVerificationOperations()
        XCTAssertFalse(
            coordinator.handle(
                stroke: InputKeyStroke(text: "", keyCode: 51),
                client: client
            )
        )
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(acceptedFeedback.allRecords().isEmpty)
        XCTAssertNil(acceptedFeedback.snapshot())
    }

    @MainActor
    func testPanelClickAcceptedAIRecommendationRecordsAcceptedLearningHistory() async throws {
        let client = FakeInputControllerClient()
        let aiProvider = RecordingAIRecommendationProvider(continuation: "AI 续写")
        let acceptedLearning = AIAcceptedLearningStore.inMemory()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: RecordingContinuationProvider(),
            aiRecommendationProvider: aiProvider,
            aiAcceptedLearning: acceptedLearning,
            enablesAsyncSuggestionRefresh: true,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["这个方案"],
                recorder: NativeSelectionRecorder()
            )
        )

        for character in "zhegefangan" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasAIRecommendation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText == "AI 续写"
        }
        XCTAssertTrue(hasAIRecommendation)

        coordinator.commitCandidatePanelSelection(.aiRecommendation, client: client)

        let recorded = await waitUntilOnMainActor {
            acceptedLearning.allRecords().count == 1
        }
        XCTAssertTrue(recorded)
        XCTAssertEqual(client.insertTextWrites.last?.text, "AI 续写")
        XCTAssertEqual(acceptedLearning.allRecords().first?.acceptedText, "AI 续写")
        XCTAssertEqual(acceptedLearning.allRecords().first?.candidateSource, "ai:ai-test")
    }

    @MainActor
    func testNativeCommitDoesNotRecordAcceptedLearningHistory() async {
        let client = FakeInputControllerClient()
        let recorder = NativeSelectionRecorder()
        let acceptedLearning = AIAcceptedLearningStore.inMemory()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            aiAcceptedLearning: acceptedLearning,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["你"],
                recorder: recorder,
                spaceCommit: "你"
            )
        )

        for character in "ni" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "你")
        XCTAssertTrue(acceptedLearning.allRecords().isEmpty)
    }

    @MainActor
    func testNativeCommitMatchingReadyAITextDoesNotRecordAcceptedLearningHistory() async {
        let client = FakeInputControllerClient()
        let recorder = NativeSelectionRecorder()
        let aiProvider = RecordingAIRecommendationProvider(continuation: "你")
        let acceptedLearning = AIAcceptedLearningStore.inMemory()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: RecordingContinuationProvider(),
            aiRecommendationProvider: aiProvider,
            aiAcceptedLearning: acceptedLearning,
            enablesAsyncSuggestionRefresh: true,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["你"],
                recorder: recorder,
                spaceCommit: "你"
            )
        )

        for character in "nihao" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasAIRecommendation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText == "你"
        }
        XCTAssertTrue(hasAIRecommendation)

        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "你")
        XCTAssertTrue(acceptedLearning.allRecords().isEmpty)
    }

    @MainActor
    func testNativeHighlightDoesNotRestartAIRecommendation() async {
        let client = FakeInputControllerClient()
        let recorder = NativeSelectionRecorder()
        let aiProvider = RecordingAIRecommendationProvider(continuation: "AI 续写")
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: RecordingContinuationProvider(),
            aiRecommendationProvider: aiProvider,
            enablesAsyncSuggestionRefresh: true,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["候一", "候二"],
                recorder: recorder
            )
        )

        for character in "houhou" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasAIRequest = await waitForAIRecommendationRequest(aiProvider)
        XCTAssertTrue(hasAIRequest)
        let requestCountBeforeHighlight = await waitForStableAIRecommendationRequestCount(aiProvider)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\u{F703}", keyCode: 124),
                client: client
            )
        )
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(host.panelStates.last?.windowState.selection, .fullCandidate(1))
        XCTAssertEqual(recorder.highlightedIndices, [1])
        let requestCountAfterHighlight = await waitForStableAIRecommendationRequestCount(aiProvider)
        XCTAssertEqual(requestCountAfterHighlight, requestCountBeforeHighlight)
    }

    func testNativeSpaceCommitRecordsSelectionHistory() {
        let client = FakeInputControllerClient()
        let persistence = FakeUserSelectionHistoryPersistence()
        let recorder = NativeSelectionRecorder()
        let (coordinator, _, persistenceSpy) = makeCoordinator(
            client: client,
            persistence: persistence,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["你"],
                recorder: recorder,
                spaceCommit: "你"
            )
        )

        for character in "ni" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "你")
        XCTAssertEqual(persistenceSpy.recordedSelections, ["你"])
    }

    @MainActor
    func testNativeSpaceCommitsExplicitSelectedAIRecommendationBeforeRime() async {
        let client = FakeInputControllerClient()
        let recorder = NativeSelectionRecorder()
        let aiProvider = RecordingAIRecommendationProvider(continuation: "AI 续写")
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: RecordingContinuationProvider(),
            aiRecommendationProvider: aiProvider,
            enablesAsyncSuggestionRefresh: true,
            conversionEngine: RecordingNativeConversionEngine(
                candidates: ["你"],
                recorder: recorder,
                spaceCommit: "rime-space"
            )
        )

        for character in "zhegeapi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasAIRecommendation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText == "AI 续写"
        }
        XCTAssertTrue(hasAIRecommendation)
        coordinator.hoverCandidatePanelSelection(.aiRecommendation)
        XCTAssertEqual(host.panelStates.last?.windowState.selection, .aiRecommendation)

        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "AI 续写")
        XCTAssertEqual(recorder.spaceProcessCount, 0)
    }

    func testNativeCommitCompositionFallsBackToRawWhenUnhandled() {
        let client = FakeInputControllerClient()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            conversionEngine: CommitCompositionUnhandledNativeConversionEngine()
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("i", client: client))
        coordinator.commitComposition(client: client)

        XCTAssertEqual(client.insertTextWrites.last?.text, "ni")
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testNativeHandledNoCommitWithEndedSnapshotFinishesComposition() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: NativeEndedNoCommitConversionEngine()
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("i", client: client))
        let updatesBeforeCommit = host.panelStates.count

        coordinator.commitComposition(client: client)
        host.runScheduledOperations()

        XCTAssertEqual(client.insertTextWrites.count, 0)
        XCTAssertEqual(client.markedTextWrites.last?.text, "")
        XCTAssertNil(client.markedRange)
        XCTAssertEqual(coordinator.composedString() as? String, "")
        XCTAssertEqual(host.panelStates.count, updatesBeforeCommit)
        XCTAssertEqual(host.hideCandidatePanelCount, 1)
    }

    func testNativePartialSpaceCommitKeepsRimePreeditAsMarkedText() {
        let client = FakeInputControllerClient()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            conversionEngine: PartialCommitNativeConversionEngine()
        )

        for character in "woxiangceshi" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "我想")
        XCTAssertEqual(client.markedTextWrites.last?.text, "我想ceshi")
        XCTAssertEqual(coordinator.composedString() as? String, "我想ceshi")

        XCTAssertTrue(coordinator.handleText(" ", client: client))
        XCTAssertEqual(client.insertTextWrites.map(\.text).suffix(2), ["我想", "测试"])
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testNativeSymbolKeyIsOfferedToRimeBeforeChinesePunctuationFallback() {
        let client = FakeInputControllerClient()
        let recorder = ConversionReplayRecorder()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            conversionEngine: SymbolRecordingNativeConversionEngine(recorder: recorder)
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("'", client: client))

        XCTAssertEqual(recorder.processedTexts, ["n", "'"])
        XCTAssertTrue(client.insertTextWrites.isEmpty)
        XCTAssertEqual(coordinator.composedString() as? String, "n'")
    }

    func testRimeDefaultPagingSymbolsRefreshNativePageBeforePunctuationCommit() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: PagedNativeConversionEngine()
        )

        XCTAssertTrue(coordinator.handleText("s", client: client))

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "=", keyCode: -1),
                client: client
            )
        )

        XCTAssertEqual(
            host.panelStates.last?.windowState.viewModel.prefixCandidates.map(\.text),
            ["第二页一", "第二页二"]
        )
        XCTAssertTrue(client.insertTextWrites.isEmpty)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "-", keyCode: -1),
                client: client
            )
        )

        XCTAssertEqual(
            host.panelStates.last?.windowState.viewModel.prefixCandidates.map(\.text),
            ["第一页一", "第一页二"]
        )
        XCTAssertTrue(client.insertTextWrites.isEmpty)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: ".", keyCode: -1),
                client: client
            )
        )

        XCTAssertEqual(
            host.panelStates.last?.windowState.viewModel.prefixCandidates.map(\.text),
            ["第二页一", "第二页二"]
        )
        XCTAssertTrue(client.insertTextWrites.isEmpty)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: ",", keyCode: -1),
                client: client
            )
        )

        XCTAssertEqual(
            host.panelStates.last?.windowState.viewModel.prefixCandidates.map(\.text),
            ["第一页一", "第一页二"]
        )
        XCTAssertTrue(client.insertTextWrites.isEmpty)
    }

    func testPagingSymbolFallsBackToPunctuationWhenRimeHasNoTargetPage() {
        let client = FakeInputControllerClient()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            conversionEngine: PagedNativeConversionEngine()
        )

        XCTAssertTrue(coordinator.handleText("s", client: client))

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "-", keyCode: -1),
                client: client
            )
        )

        XCTAssertEqual(client.insertTextWrites.last?.text, "第一页一-")
    }

    func testCommaAndPeriodFallbackToChinesePunctuationAtNativePageBoundary() {
        let client = FakeInputControllerClient()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            conversionEngine: PagedNativeConversionEngine()
        )

        XCTAssertTrue(coordinator.handleText("s", client: client))
        XCTAssertTrue(coordinator.handle(stroke: InputKeyStroke(text: ",", keyCode: -1), client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "第一页一，")

        XCTAssertTrue(coordinator.handleText("s", client: client))
        XCTAssertTrue(coordinator.handle(stroke: InputKeyStroke(text: "=", keyCode: -1), client: client))
        XCTAssertTrue(coordinator.handle(stroke: InputKeyStroke(text: ".", keyCode: -1), client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "第二页一。")
    }

    func testIdleSlashShowsSymbolCandidatesAndSpaceCommitsDunhao() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("/", client: client))

        let viewModel = host.panelStates.last?.windowState.viewModel
        XCTAssertEqual(viewModel?.symbolCandidates.map(\.text), ["、", "/", "／", "÷"])
        XCTAssertEqual(host.panelStates.last?.windowState.selection, .symbolCandidate(0))
        XCTAssertTrue(client.insertTextWrites.isEmpty)

        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "、")
        XCTAssertEqual(host.candidatePanelFrames.last?.isVisible, false)
    }

    func testIdleSlashSymbolCandidateNumberTwoCommitsAsciiSlash() {
        let client = FakeInputControllerClient()
        let (coordinator, _, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("/", client: client))
        XCTAssertTrue(coordinator.handle(stroke: InputKeyStroke(text: "2", keyCode: 19), client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "/")
    }

    func testSymbolCandidateEscapeCancelsWithoutCommitting() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("/", client: client))
        XCTAssertTrue(coordinator.handle(stroke: InputKeyStroke(text: "\u{1B}", keyCode: 53), client: client))

        XCTAssertTrue(client.insertTextWrites.isEmpty)
        XCTAssertEqual(host.candidatePanelFrames.last?.isVisible, false)
    }

    func testOptionPeriodShowsTransientModeStatusRow() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: ".", keyCode: 47, modifiers: [.option]),
                client: client
            )
        )

        let windowState = host.panelStates.last?.windowState
        XCTAssertEqual(windowState?.viewModel.modeStatusText, "中 · 英文标点 · 半角")
        XCTAssertEqual(windowState?.viewModel.symbolCandidates, [])
        XCTAssertEqual(windowState?.isVisible, true)
    }

    private func makeCoordinator(
        client: FakeInputControllerClient,
        persistence: FakeUserSelectionHistoryPersistence = FakeUserSelectionHistoryPersistence(),
        provider: (any LLMProvider)? = nil,
        aiRecommendationProvider: (any AIRecommendationProviding)? = nil,
        aiRecommendationProviderAvailability: (any AIRecommendationProviderAvailabilitySnapshotting)? = nil,
        aiContextEventRecorder: (any AIContextEventRecording)? = nil,
        aiAcceptedLearning: (any AIAcceptedLearningRecording & AIAcceptedLearningSnapshotProviding)? = nil,
        aiAcceptedFeedback: (any AIAcceptedFeedbackRecording & AIAcceptedFeedbackSnapshotProviding)? = nil,
        aiRecommendationDispatchDebounceMilliseconds: Int = 0,
        aiDiagnosticSink: any AIRecommendationDiagnosticSink = OSLogAIRecommendationDiagnosticSink(),
        lexicalProfileStore: LexicalProfileStore = .inMemory(),
        lexicalProfileRefreshGate: LexicalProfileRefreshGate = LexicalProfileRefreshGate(),
        rimeUserDBTextProvider: (any RimeUserDBTextSnapshotProviding)? = nil,
        enablesAsyncSuggestionRefresh: Bool = false,
        lexiconRuntime: InputMethodLexiconRuntime = InputMethodLexiconRuntime(directories: []),
        inputModePreferences: InputModePreferences = .standard,
        runtimePreferences: InputMethodRuntimePreferences = .standard,
        runtimePreferenceStore: (any InputMethodRuntimePreferenceStore)? = nil,
        conversionEngine: (any KnowTypeConversionEngine)? = nil,
        conversionEngineFactory: (@Sendable (TraditionalInputEngine?) -> any KnowTypeConversionEngine)? = nil,
        screenProvider: any ScreenGeometryProviding = FixedInputControllerScreenProvider(),
        asyncSuggestionDelayNanoseconds: UInt64 = 0
    ) -> (
        InputControllerCoordinator,
        FakeInputControllerHost,
        FakeUserSelectionHistoryPersistence
    ) {
        let host = FakeInputControllerHost()
        host.currentClientValue = client
        let effectiveConversionEngine = conversionEngine
            ?? (conversionEngineFactory == nil ? FixtureNativeConversionEngine() : nil)
        let coordinator = InputControllerCoordinator(
            provider: provider,
            traditionalInputEngine: lexiconRuntime.makeEngine(),
            lexiconRuntimeSnapshot: lexiconRuntime.snapshot(),
            lexiconRuntime: lexiconRuntime,
            inputModePreferenceStore: FixedInputModePreferenceStore(preferences: inputModePreferences),
            runtimePreferenceStore: runtimePreferenceStore ?? FixedInputMethodRuntimePreferenceStore(preferences: runtimePreferences),
            initialRuntimePreferences: runtimePreferences,
            initialAppBundleID: client.bundleIdentifier,
            userSelectionHistoryPersistence: persistence,
            aiRecommendationProvider: aiRecommendationProvider,
            aiRecommendationProviderAvailability: aiRecommendationProviderAvailability,
            aiContextEventRecorder: aiContextEventRecorder,
            aiAcceptedLearning: aiAcceptedLearning,
            aiAcceptedFeedback: aiAcceptedFeedback,
            aiRecommendationDispatchDebounceMilliseconds: aiRecommendationDispatchDebounceMilliseconds,
            aiDiagnosticSink: aiDiagnosticSink,
            lexicalProfileStore: lexicalProfileStore,
            lexicalProfileRefreshGate: lexicalProfileRefreshGate,
            rimeUserDBTextProvider: rimeUserDBTextProvider,
            conversionEngine: effectiveConversionEngine,
            conversionEngineFactory: conversionEngineFactory,
            host: host,
            anchorResolver: CandidateAnchorResolver(
                screenProvider: screenProvider,
                accessibilityProvider: NoopAccessibilityAnchorProvider(),
                traceEnabled: false
            ),
            enablesAsyncSuggestionRefresh: enablesAsyncSuggestionRefresh,
            asyncSuggestionDelayNanoseconds: asyncSuggestionDelayNanoseconds
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
        _ = index
        let shortcutNumber = try visibleShortcutNumber(
            text: text,
            coordinator: coordinator,
            host: host,
            client: client
        )
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

    private func visibleShortcutNumber(
        text: String,
        coordinator: InputControllerCoordinator,
        host: FakeInputControllerHost,
        client: FakeInputControllerClient
    ) throws -> Int {
        for _ in 0..<20 {
            let windowState = try XCTUnwrap(host.panelStates.last?.windowState)
            let rendered = CandidatePanelRenderer(locale: .zhCN).render(
                windowState.viewModel,
                selected: windowState.selection,
                paging: windowState.paging
            )
            if let shortcut = rendered.rows.first(where: { $0.text == text })?.shortcutLabel,
               let number = Int(shortcut) {
                return number
            }
            XCTAssertTrue(
                coordinator.handle(
                    stroke: InputKeyStroke(text: "", keyCode: 121),
                    client: client
                )
            )
        }
        return try XCTUnwrap(nil as Int?)
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

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowTypeInputControllerCoordinatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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

    @MainActor
    private func waitForAIRecommendationRequest(
        _ provider: RecordingAIRecommendationProvider,
        timeout: TimeInterval = 3
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let requests = await provider.requests
            if !requests.isEmpty {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let requests = await provider.requests
        return !requests.isEmpty
    }

    @MainActor
    private func waitForStableAIRecommendationRequestCount(
        _ provider: RecordingAIRecommendationProvider,
        timeout: TimeInterval = 3,
        quietInterval: TimeInterval = 0.15
    ) async -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        var lastCount = -1
        var lastChange = Date()
        while Date() < deadline {
            let count = (await provider.requests).count
            if count != lastCount {
                lastCount = count
                lastChange = Date()
            } else if count > 0,
                      Date().timeIntervalSince(lastChange) >= quietInterval {
                return count
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return (await provider.requests).count
    }
}

private struct FixtureNativeConversionEngine: KnowTypeConversionEngine {
    var isNativeActive = true
    var activeSchemaID = "pinyin_simp"
    private var rawInput = ""
    private var currentSnapshot = ConversionEngineSnapshot(engineName: "native-test")

    init(activeSchemaID: String = "pinyin_simp") {
        self.activeSchemaID = activeSchemaID
    }

    var snapshot: ConversionEngineSnapshot {
        currentSnapshot
    }

    mutating func reset() {
        rawInput = ""
        currentSnapshot = makeSnapshot()
    }

    mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        switch key {
        case .text(let text):
            if InputSymbolTransformer.isSymbolInput(text) {
                currentSnapshot = makeSnapshot()
                return ConversionEngineResult(handled: false, snapshot: currentSnapshot)
            }
            rawInput += text
            currentSnapshot = makeSnapshot()
            return ConversionEngineResult(handled: true, snapshot: currentSnapshot)
        case .space, .commitComposition:
            let candidates = candidateTexts(for: rawInput)
            guard let commit = candidates.first else {
                currentSnapshot = makeSnapshot()
                return ConversionEngineResult(handled: false, snapshot: currentSnapshot)
            }
            rawInput = ""
            currentSnapshot = makeSnapshot()
            return ConversionEngineResult(handled: true, commitText: commit, snapshot: currentSnapshot)
        case .selectCandidateOnCurrentPage(let index), .selectCandidate(let index):
            let candidates = candidateTexts(for: rawInput)
            guard candidates.indices.contains(index) else {
                currentSnapshot = makeSnapshot()
                return ConversionEngineResult(handled: false, snapshot: currentSnapshot)
            }
            let commit = candidates[index]
            rawInput = ""
            currentSnapshot = makeSnapshot()
            return ConversionEngineResult(handled: true, commitText: commit, snapshot: currentSnapshot)
        case .deleteBackward:
            if !rawInput.isEmpty {
                rawInput.removeLast()
            }
            currentSnapshot = makeSnapshot()
            return ConversionEngineResult(handled: true, snapshot: currentSnapshot)
        case .highlightCandidateOnCurrentPage, .pageUp, .pageDown:
            return ConversionEngineResult(handled: true, snapshot: currentSnapshot)
        }
    }

    private func makeSnapshot() -> ConversionEngineSnapshot {
        let candidates = candidateTexts(for: rawInput).enumerated().map { index, text in
            ConversionEngineCandidate(
                text: text,
                index: index,
                confidence: 1 - Double(index) * 0.01,
                source: "native-test"
            )
        }
        return ConversionEngineSnapshot(
            rawInput: rawInput,
            preedit: rawInput,
            candidates: candidates,
            highlightedIndex: 0,
            pageSize: candidates.count,
            pageNumber: 0,
            isLastPage: true,
            engineName: "native-test"
        )
    }

    private func candidateTexts(for rawInput: String) -> [String] {
        guard !rawInput.isEmpty else {
            return []
        }
        switch rawInput {
        case "n":
            return ["你", "呢"]
        case "ni":
            return ["你", "尼"]
        case "wsm":
            return ["为什么", "为啥"]
        case "zhegeapi":
            return ["这个 API", "这个接口"]
        case "zz":
            return ["在这", "组织"]
        case "wojuedezhegefagnan":
            return ["我觉得这个方案", "我觉得这个方法"]
        default:
            return ["候选\(rawInput)", "备选\(rawInput)"]
        }
    }
}

private struct SpaceUpdatingNativeConversionEngine: KnowTypeConversionEngine {
    var isNativeActive = true
    private var rawInput = ""
    private var didHandleSpace = false

    var snapshot: ConversionEngineSnapshot {
        guard !rawInput.isEmpty else {
            return ConversionEngineSnapshot(engineName: "native-test")
        }
        return ConversionEngineSnapshot(
            rawInput: rawInput,
            preedit: rawInput,
            candidates: [
                ConversionEngineCandidate(
                    text: didHandleSpace ? "after-space" : "before-space",
                    index: 0,
                    source: "native-test"
                )
            ],
            highlightedIndex: 0,
            pageSize: 1,
            pageNumber: 0,
            isLastPage: true,
            engineName: "native-test"
        )
    }

    mutating func reset() {
        rawInput = ""
        didHandleSpace = false
    }

    mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        switch key {
        case .text(let text):
            rawInput += text
            didHandleSpace = false
        case .space:
            didHandleSpace = true
        case .deleteBackward:
            if !rawInput.isEmpty {
                rawInput.removeLast()
            }
        case .selectCandidateOnCurrentPage, .selectCandidate, .highlightCandidateOnCurrentPage, .pageUp, .pageDown, .commitComposition:
            break
        }
        return ConversionEngineResult(handled: true, snapshot: snapshot)
    }
}

private struct BypassUntilResetConversionEngine: KnowTypeConversionEngine {
    private var rawInput = ""
    private var bypassed = false

    var isNativeActive: Bool {
        !bypassed
    }

    var snapshot: ConversionEngineSnapshot {
        guard !rawInput.isEmpty else {
            return ConversionEngineSnapshot(engineName: bypassed ? "traditional-fallback" : "native-test")
        }
        return ConversionEngineSnapshot(
            rawInput: rawInput,
            preedit: rawInput,
            candidates: [
                ConversionEngineCandidate(
                    text: bypassed ? "fallback-\(rawInput)" : "native-\(rawInput)",
                    index: 0,
                    source: bypassed ? "traditional-fallback" : "native-test"
                )
            ],
            highlightedIndex: 0,
            pageSize: 1,
            pageNumber: 0,
            isLastPage: true,
            engineName: bypassed ? "traditional-fallback" : "native-test"
        )
    }

    mutating func reset() {
        rawInput = ""
        bypassed = false
    }

    mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        switch key {
        case .text(let text):
            if text.unicodeScalars.contains(where: { !$0.isASCII }) {
                bypassed = true
            }
            rawInput += text
        case .deleteBackward:
            if !rawInput.isEmpty {
                rawInput.removeLast()
            }
        case .space, .selectCandidateOnCurrentPage, .selectCandidate, .highlightCandidateOnCurrentPage, .pageUp, .pageDown, .commitComposition:
            break
        }
        return ConversionEngineResult(handled: true, snapshot: snapshot)
    }
}

private struct NativeHandledNoCommitConversionEngine: KnowTypeConversionEngine {
    var isNativeActive = true
    private var rawInput = ""
    private var currentSnapshot = ConversionEngineSnapshot(engineName: "native-test")

    var snapshot: ConversionEngineSnapshot {
        currentSnapshot
    }

    mutating func reset() {
        rawInput = ""
        currentSnapshot = ConversionEngineSnapshot(engineName: "native-test")
    }

    mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        switch key {
        case .text(let text):
            rawInput += text
            currentSnapshot = makeSnapshot()
            return ConversionEngineResult(handled: true, snapshot: currentSnapshot)
        case .space, .selectCandidateOnCurrentPage, .selectCandidate, .highlightCandidateOnCurrentPage, .commitComposition:
            currentSnapshot = makeSnapshot()
            return ConversionEngineResult(handled: true, snapshot: currentSnapshot)
        case .deleteBackward:
            if !rawInput.isEmpty {
                rawInput.removeLast()
            }
            currentSnapshot = makeSnapshot()
            return ConversionEngineResult(handled: true, snapshot: currentSnapshot)
        case .pageUp, .pageDown:
            return ConversionEngineResult(handled: true, snapshot: currentSnapshot)
        }
    }

    private func makeSnapshot() -> ConversionEngineSnapshot {
        return ConversionEngineSnapshot(
            rawInput: rawInput,
            preedit: rawInput,
            candidates: [
                ConversionEngineCandidate(text: "你", index: 0, source: "native-test"),
                ConversionEngineCandidate(text: "尼", index: 1, source: "native-test")
            ],
            highlightedIndex: 0,
            pageSize: 2,
            pageNumber: 0,
            isLastPage: true,
            engineName: "native-test"
        )
    }
}

private struct CommitCompositionUnhandledNativeConversionEngine: KnowTypeConversionEngine {
    var isNativeActive = true
    private var rawInput = ""

    var snapshot: ConversionEngineSnapshot {
        guard !rawInput.isEmpty else {
            return ConversionEngineSnapshot(engineName: "native-commit-unhandled")
        }
        return ConversionEngineSnapshot(
            rawInput: rawInput,
            preedit: rawInput,
            candidates: [ConversionEngineCandidate(text: "候选\(rawInput)", index: 0, source: "native-test")],
            highlightedIndex: 0,
            pageSize: 1,
            pageNumber: 0,
            isLastPage: true,
            engineName: "native-commit-unhandled"
        )
    }

    mutating func reset() {
        rawInput = ""
    }

    mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        switch key {
        case .text(let text):
            rawInput += text
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .commitComposition:
            return ConversionEngineResult(handled: false, snapshot: snapshot)
        case .deleteBackward:
            if !rawInput.isEmpty {
                rawInput.removeLast()
            }
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .space,
             .selectCandidateOnCurrentPage,
             .selectCandidate,
             .highlightCandidateOnCurrentPage,
             .pageUp,
             .pageDown:
            return ConversionEngineResult(handled: false, snapshot: snapshot)
        }
    }
}

private struct NativeEndedNoCommitConversionEngine: KnowTypeConversionEngine {
    var isNativeActive = true
    private var rawInput = ""
    private var currentSnapshot = ConversionEngineSnapshot(engineName: "native-ended-no-commit")

    var snapshot: ConversionEngineSnapshot {
        currentSnapshot
    }

    mutating func reset() {
        rawInput = ""
        currentSnapshot = ConversionEngineSnapshot(engineName: "native-ended-no-commit")
    }

    mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        switch key {
        case .text(let text):
            rawInput += text
            currentSnapshot = ConversionEngineSnapshot(
                rawInput: rawInput,
                preedit: rawInput,
                candidates: [ConversionEngineCandidate(text: "候选\(rawInput)", index: 0, source: "native-test")],
                highlightedIndex: 0,
                pageSize: 1,
                pageNumber: 0,
                isLastPage: true,
                engineName: "native-ended-no-commit"
            )
            return ConversionEngineResult(handled: true, snapshot: currentSnapshot)
        case .commitComposition, .space:
            rawInput = ""
            currentSnapshot = ConversionEngineSnapshot(engineName: "native-ended-no-commit")
            return ConversionEngineResult(handled: true, snapshot: currentSnapshot)
        case .deleteBackward:
            if !rawInput.isEmpty {
                rawInput.removeLast()
            }
            currentSnapshot = rawInput.isEmpty
                ? ConversionEngineSnapshot(engineName: "native-ended-no-commit")
                : ConversionEngineSnapshot(
                    rawInput: rawInput,
                    preedit: rawInput,
                    candidates: [ConversionEngineCandidate(text: "候选\(rawInput)", index: 0, source: "native-test")],
                    highlightedIndex: 0,
                    pageSize: 1,
                    pageNumber: 0,
                    isLastPage: true,
                    engineName: "native-ended-no-commit"
                )
            return ConversionEngineResult(handled: true, snapshot: currentSnapshot)
        case .selectCandidateOnCurrentPage,
             .selectCandidate,
             .highlightCandidateOnCurrentPage,
             .pageUp,
             .pageDown:
            return ConversionEngineResult(handled: false, snapshot: currentSnapshot)
        }
    }
}

private struct TransientEmptySnapshotConversionEngine: KnowTypeConversionEngine {
    var isNativeActive = true
    var snapshot = ConversionEngineSnapshot(engineName: "native-transient-empty")

    mutating func reset() {
        snapshot = ConversionEngineSnapshot(engineName: "native-transient-empty")
    }

    mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        switch key {
        case .text, .deleteBackward:
            snapshot = ConversionEngineSnapshot(engineName: "native-transient-empty")
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .space,
             .selectCandidateOnCurrentPage,
             .selectCandidate,
             .highlightCandidateOnCurrentPage,
             .pageUp,
             .pageDown,
             .commitComposition:
            return ConversionEngineResult(handled: false, snapshot: snapshot)
        }
    }
}

private final class NativeSelectionRecorder: @unchecked Sendable {
    var selectedIndices: [Int] = []
    var highlightedIndices: [Int] = []
    var spaceProcessCount = 0
}

private final class ConversionReplayRecorder: @unchecked Sendable {
    var processedTexts: [String] = []
}

private struct ReplayRecordingConversionEngine: KnowTypeConversionEngine {
    var isNativeActive = true
    let recorder: ConversionReplayRecorder
    private var rawInput = ""

    init(recorder: ConversionReplayRecorder) {
        self.recorder = recorder
    }

    var snapshot: ConversionEngineSnapshot {
        ConversionEngineSnapshot(
            rawInput: rawInput,
            preedit: rawInput,
            candidates: rawInput.isEmpty
                ? []
                : [ConversionEngineCandidate(text: "replayed", index: 0, source: "native-test")],
            highlightedIndex: 0,
            pageSize: 1,
            pageNumber: 0,
            isLastPage: true,
            engineName: "native-test"
        )
    }

    mutating func reset() {
        rawInput = ""
    }

    mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        switch key {
        case .text(let text):
            recorder.processedTexts.append(text)
            rawInput += text
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .space,
             .deleteBackward,
             .selectCandidateOnCurrentPage,
             .selectCandidate,
             .highlightCandidateOnCurrentPage,
             .pageUp,
             .pageDown,
             .commitComposition:
            return ConversionEngineResult(handled: false, snapshot: snapshot)
        }
    }
}

private struct RecordingNativeConversionEngine: KnowTypeConversionEngine {
    var isNativeActive = true
    let candidates: [String]
    let recorder: NativeSelectionRecorder
    let spaceCommit: String?
    let source: String
    let commitsSelection: Bool
    let handlesHighlight: Bool
    private var rawInput = ""
    private var highlightedIndex = 0
    private var currentSnapshot: ConversionEngineSnapshot

    init(
        candidates: [String],
        recorder: NativeSelectionRecorder,
        spaceCommit: String? = nil,
        source: String = "native-test",
        commitsSelection: Bool = true,
        handlesHighlight: Bool = true
    ) {
        self.candidates = candidates
        self.recorder = recorder
        self.spaceCommit = spaceCommit
        self.source = source
        self.commitsSelection = commitsSelection
        self.handlesHighlight = handlesHighlight
        currentSnapshot = Self.makeSnapshot(rawInput: "", candidates: candidates, source: source)
    }

    var snapshot: ConversionEngineSnapshot {
        currentSnapshot
    }

    mutating func reset() {
        rawInput = ""
        currentSnapshot = Self.makeSnapshot(rawInput: rawInput, candidates: candidates, source: source)
    }

    mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        switch key {
        case .text(let text):
            rawInput += text
            highlightedIndex = 0
            currentSnapshot = Self.makeSnapshot(
                rawInput: rawInput,
                candidates: candidates,
                source: source,
                highlightedIndex: highlightedIndex
            )
            return ConversionEngineResult(handled: true, snapshot: currentSnapshot)
        case .space, .commitComposition:
            recorder.spaceProcessCount += 1
            currentSnapshot = Self.makeSnapshot(
                rawInput: rawInput,
                candidates: candidates,
                source: source,
                highlightedIndex: highlightedIndex
            )
            guard let spaceCommit else {
                return ConversionEngineResult(handled: true, snapshot: currentSnapshot)
            }
            rawInput = ""
            highlightedIndex = 0
            currentSnapshot = Self.makeSnapshot(
                rawInput: rawInput,
                candidates: candidates,
                source: source,
                highlightedIndex: highlightedIndex
            )
            return ConversionEngineResult(handled: true, commitText: spaceCommit, snapshot: currentSnapshot)
        case .selectCandidateOnCurrentPage(let index), .selectCandidate(let index):
            recorder.selectedIndices.append(index)
            currentSnapshot = Self.makeSnapshot(
                rawInput: rawInput,
                candidates: candidates,
                source: source,
                highlightedIndex: highlightedIndex
            )
            guard commitsSelection,
                  candidates.indices.contains(index) else {
                return ConversionEngineResult(handled: false, snapshot: currentSnapshot)
            }
            let commit = candidates[index]
            rawInput = ""
            highlightedIndex = 0
            currentSnapshot = Self.makeSnapshot(
                rawInput: rawInput,
                candidates: candidates,
                source: source,
                highlightedIndex: highlightedIndex
            )
            return ConversionEngineResult(handled: true, commitText: commit, snapshot: currentSnapshot)
        case .highlightCandidateOnCurrentPage(let index):
            guard handlesHighlight,
                  candidates.indices.contains(index) else {
                return ConversionEngineResult(handled: false, snapshot: currentSnapshot)
            }
            recorder.highlightedIndices.append(index)
            highlightedIndex = index
            currentSnapshot = Self.makeSnapshot(
                rawInput: rawInput,
                candidates: candidates,
                source: source,
                highlightedIndex: highlightedIndex
            )
            return ConversionEngineResult(handled: true, snapshot: currentSnapshot)
        case .deleteBackward:
            if !rawInput.isEmpty {
                rawInput.removeLast()
            }
            highlightedIndex = 0
            currentSnapshot = Self.makeSnapshot(
                rawInput: rawInput,
                candidates: candidates,
                source: source,
                highlightedIndex: highlightedIndex
            )
            return ConversionEngineResult(handled: true, snapshot: currentSnapshot)
        case .pageUp, .pageDown:
            return ConversionEngineResult(handled: true, snapshot: currentSnapshot)
        }
    }

    private static func makeSnapshot(
        rawInput: String,
        candidates: [String],
        source: String,
        highlightedIndex: Int = 0
    ) -> ConversionEngineSnapshot {
        guard !rawInput.isEmpty else {
            return ConversionEngineSnapshot(engineName: "native-test")
        }
        return ConversionEngineSnapshot(
            rawInput: rawInput,
            preedit: rawInput,
            candidates: candidates.enumerated().map { index, text in
                ConversionEngineCandidate(text: text, index: index, source: source)
            },
            highlightedIndex: highlightedIndex,
            pageSize: max(candidates.count, 1),
            pageNumber: 0,
            isLastPage: true,
            engineName: "native-test"
        )
    }
}

private struct CandidateOnlyNativeConversionEngine: KnowTypeConversionEngine {
    var isNativeActive = true
    let candidates: [String]
    let recorder: NativeSelectionRecorder
    private var currentSnapshot: ConversionEngineSnapshot

    init(candidates: [String], recorder: NativeSelectionRecorder) {
        self.candidates = candidates
        self.recorder = recorder
        currentSnapshot = Self.makeSnapshot(candidates: candidates)
    }

    var snapshot: ConversionEngineSnapshot {
        currentSnapshot
    }

    mutating func reset() {
        currentSnapshot = Self.makeSnapshot(candidates: candidates)
    }

    mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        switch key {
        case .selectCandidateOnCurrentPage(let index), .selectCandidate(let index):
            recorder.selectedIndices.append(index)
            guard candidates.indices.contains(index) else {
                return ConversionEngineResult(handled: false, snapshot: currentSnapshot)
            }
            let commit = candidates[index]
            currentSnapshot = ConversionEngineSnapshot(engineName: "candidate-only-test")
            return ConversionEngineResult(handled: true, commitText: commit, snapshot: currentSnapshot)
        default:
            return ConversionEngineResult(handled: false, snapshot: currentSnapshot)
        }
    }

    private static func makeSnapshot(candidates: [String]) -> ConversionEngineSnapshot {
        ConversionEngineSnapshot(
            rawInput: "",
            preedit: "",
            candidates: candidates.enumerated().map { index, text in
                ConversionEngineCandidate(text: text, index: index, source: "candidate-only-test")
            },
            highlightedIndex: 0,
            pageSize: max(candidates.count, 1),
            pageNumber: 0,
            isLastPage: true,
            engineName: "candidate-only-test"
        )
    }
}

private struct PagedNativeConversionEngine: KnowTypeConversionEngine {
    var isNativeActive = true
    private var rawInput = ""
    private var currentPage = 0
    private var highlightedIndex = 0
    private let pages = [
        ["第一页一", "第一页二"],
        ["第二页一", "第二页二"]
    ]

    var snapshot: ConversionEngineSnapshot {
        makeSnapshot()
    }

    mutating func reset() {
        rawInput = ""
        currentPage = 0
        highlightedIndex = 0
    }

    mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        switch key {
        case .text(let text):
            if InputSymbolTransformer.isSymbolInput(text) {
                return ConversionEngineResult(handled: false, snapshot: snapshot)
            }
            rawInput += text
            currentPage = 0
            highlightedIndex = 0
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .pageDown:
            guard currentPage < pages.count - 1 else {
                return ConversionEngineResult(handled: false, snapshot: snapshot)
            }
            currentPage += 1
            highlightedIndex = 0
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .pageUp:
            guard currentPage > 0 else {
                return ConversionEngineResult(handled: false, snapshot: snapshot)
            }
            currentPage -= 1
            highlightedIndex = 0
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .highlightCandidateOnCurrentPage(let index):
            guard pages[currentPage].indices.contains(index) else {
                return ConversionEngineResult(handled: false, snapshot: snapshot)
            }
            highlightedIndex = index
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .space, .commitComposition:
            guard pages[currentPage].indices.contains(highlightedIndex) else {
                return ConversionEngineResult(handled: false, snapshot: snapshot)
            }
            let candidate = pages[currentPage][highlightedIndex]
            reset()
            return ConversionEngineResult(handled: true, commitText: candidate, snapshot: snapshot)
        case .selectCandidateOnCurrentPage(let index), .selectCandidate(let index):
            guard pages[currentPage].indices.contains(index) else {
                return ConversionEngineResult(handled: false, snapshot: snapshot)
            }
            let candidate = pages[currentPage][index]
            reset()
            return ConversionEngineResult(handled: true, commitText: candidate, snapshot: snapshot)
        case .deleteBackward:
            if !rawInput.isEmpty {
                rawInput.removeLast()
            }
            if rawInput.isEmpty {
                currentPage = 0
            }
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        }
    }

    private func makeSnapshot() -> ConversionEngineSnapshot {
        guard !rawInput.isEmpty else {
            return ConversionEngineSnapshot(engineName: "native-test")
        }
        return ConversionEngineSnapshot(
            rawInput: rawInput,
            preedit: rawInput,
            candidates: pages[currentPage].enumerated().map { index, text in
                ConversionEngineCandidate(text: text, index: index, source: "native-test")
            },
            highlightedIndex: highlightedIndex,
            pageSize: pages[currentPage].count,
            pageNumber: currentPage,
            isLastPage: currentPage == pages.count - 1,
            engineName: "native-test"
        )
    }
}

private struct PartialCommitNativeConversionEngine: KnowTypeConversionEngine {
    var isNativeActive = true
    private var rawInput = ""
    private var stage = 0

    var snapshot: ConversionEngineSnapshot {
        makeSnapshot()
    }

    mutating func reset() {
        rawInput = ""
        stage = 0
    }

    mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        switch key {
        case .text(let text):
            rawInput += text
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .space:
            if stage == 0 {
                stage = 1
                rawInput = "ceshi"
                return ConversionEngineResult(
                    handled: true,
                    commitText: "我想",
                    snapshot: snapshot
                )
            }
            reset()
            return ConversionEngineResult(
                handled: true,
                commitText: "测试",
                snapshot: snapshot
            )
        case .commitComposition:
            reset()
            return ConversionEngineResult(
                handled: true,
                commitText: "我想测试",
                snapshot: snapshot
            )
        case .deleteBackward:
            if !rawInput.isEmpty {
                rawInput.removeLast()
            }
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .selectCandidateOnCurrentPage, .selectCandidate, .highlightCandidateOnCurrentPage, .pageUp, .pageDown:
            return ConversionEngineResult(handled: false, snapshot: snapshot)
        }
    }

    private func makeSnapshot() -> ConversionEngineSnapshot {
        guard !rawInput.isEmpty else {
            return ConversionEngineSnapshot(engineName: "native-partial")
        }
        let preedit = stage == 1 ? "我想\(rawInput)" : rawInput
        let candidates = stage == 1
            ? [ConversionEngineCandidate(text: "测试", index: 0, source: "native-partial")]
            : [ConversionEngineCandidate(text: "我想测试", index: 0, source: "native-partial")]
        return ConversionEngineSnapshot(
            rawInput: rawInput,
            preedit: preedit,
            candidates: candidates,
            highlightedIndex: 0,
            pageSize: candidates.count,
            pageNumber: 0,
            isLastPage: true,
            engineName: "native-partial"
        )
    }
}

private struct SymbolRecordingNativeConversionEngine: KnowTypeConversionEngine {
    var isNativeActive = true
    let recorder: ConversionReplayRecorder
    private var rawInput = ""

    init(recorder: ConversionReplayRecorder) {
        self.recorder = recorder
    }

    var snapshot: ConversionEngineSnapshot {
        guard !rawInput.isEmpty else {
            return ConversionEngineSnapshot(engineName: "native-symbol")
        }
        return ConversionEngineSnapshot(
            rawInput: rawInput,
            preedit: rawInput,
            candidates: [ConversionEngineCandidate(text: "候选\(rawInput)", index: 0, source: "native-symbol")],
            highlightedIndex: 0,
            pageSize: 1,
            pageNumber: 0,
            isLastPage: true,
            engineName: "native-symbol"
        )
    }

    mutating func reset() {
        rawInput = ""
    }

    mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        switch key {
        case .text(let text):
            recorder.processedTexts.append(text)
            rawInput += text
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .deleteBackward:
            if !rawInput.isEmpty {
                rawInput.removeLast()
            }
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .space,
             .selectCandidateOnCurrentPage,
             .selectCandidate,
             .highlightCandidateOnCurrentPage,
             .pageUp,
             .pageDown,
             .commitComposition:
            return ConversionEngineResult(handled: false, snapshot: snapshot)
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

private struct FixedInputMethodRuntimePreferenceStore: InputMethodRuntimePreferenceStore {
    var preferences = InputMethodRuntimePreferences.standard

    func loadPreferences() -> InputMethodRuntimePreferences {
        preferences
    }

    func savePreferences(_ preferences: InputMethodRuntimePreferences) throws {}
}

private final class MutableInputMethodRuntimePreferenceStore: InputMethodRuntimePreferenceStore, @unchecked Sendable {
    var preferences: InputMethodRuntimePreferences

    init(preferences: InputMethodRuntimePreferences) {
        self.preferences = preferences
    }

    func loadPreferences() -> InputMethodRuntimePreferences {
        preferences
    }

    func savePreferences(_ preferences: InputMethodRuntimePreferences) throws {
        self.preferences = preferences
    }
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

private actor CorrectionFallbackProvider: LLMProvider {
    nonisolated let providerName = "cloud-correction"
    private var recordedRequests: [LLMRequest] = []

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        recordedRequests.append(request)
        guard request.task == .correction else {
            return LLMResponse(candidates: [])
        }
        return LLMResponse(candidates: [
            LLMCandidate(text: "云端纠错", confidence: 0.95)
        ])
    }

    var requests: [LLMRequest] {
        recordedRequests
    }
}

private actor RecordingAIRecommendationProvider: AIRecommendationProviding {
    private let continuation: String
    private var recordedRequests: [AIRecommendationRequest] = []

    init(continuation: String = "继续推进") {
        self.continuation = continuation
    }

    func recommendation(for request: AIRecommendationRequest) async -> AIRecommendationState {
        recordedRequests.append(request)
        let displayText = request.lockedPrefix.map { $0 + continuation } ?? continuation
        let candidate = AIRecommendationCandidate(
            prefixText: request.lockedPrefix ?? "",
            continuationText: request.lockedPrefix == nil ? nil : continuation,
            displayText: displayText,
            confidence: 0.91,
            provider: "ai-test",
            contextVersion: "test"
        )
        return .ready(candidate)
    }

    var requests: [AIRecommendationRequest] {
        recordedRequests
    }
}

private final class RecommendationReturnSignal: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var didSignal = false

    func signal() {
        lock.lock()
        didSignal = true
        lock.unlock()
        semaphore.signal()
    }

    func wait(timeout: DispatchTime) -> Bool {
        semaphore.wait(timeout: timeout) == .success
    }

    var isSignaled: Bool {
        lock.lock()
        let value = didSignal
        lock.unlock()
        return value
    }
}

private actor SignaledAIRecommendationProvider: AIRecommendationProviding {
    private let returnSignal: RecommendationReturnSignal

    init(returnSignal: RecommendationReturnSignal) {
        self.returnSignal = returnSignal
    }

    func recommendation(for request: AIRecommendationRequest) async -> AIRecommendationState {
        let displayText = request.lockedPrefix.map { $0 + "继续推进" } ?? "继续推进"
        let candidate = AIRecommendationCandidate(
            prefixText: request.lockedPrefix ?? "",
            continuationText: request.lockedPrefix == nil ? nil : "继续推进",
            displayText: displayText,
            confidence: 0.91,
            provider: "ai-test",
            contextVersion: "test"
        )
        returnSignal.signal()
        try? await Task.sleep(nanoseconds: 200_000_000)
        return .ready(candidate)
    }
}

private actor PendingAIRecommendationProvider: AIRecommendationProviding {
    private var recordedRequests: [AIRecommendationRequest] = []

    func recommendation(for request: AIRecommendationRequest) async -> AIRecommendationState {
        recordedRequests.append(request)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        return .unavailable(reason: "timeout")
    }

    var requests: [AIRecommendationRequest] {
        recordedRequests
    }
}

private actor UnavailableAIRecommendationProvider: AIRecommendationProviding {
    func recommendation(for request: AIRecommendationRequest) async -> AIRecommendationState {
        .unavailable(reason: "AI 未配置")
    }
}

private actor DelayedAIRecommendationProvider: AIRecommendationProviding {
    private let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func recommendation(for request: AIRecommendationRequest) async -> AIRecommendationState {
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        return .unavailable(reason: "delayed")
    }
}

private final class RecordingDiagnosticSink: AIRecommendationDiagnosticSink, @unchecked Sendable {
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

final class InputControllerCoordinatorRefactorRegressionTests: XCTestCase {
    func testInlineHostCompositionKeepsMarkedPanelCommitAndResetOrder() throws {
        let client = FakeInputControllerClient()
        client.bundleIdentifier = "com.apple.TextEdit"
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("i", client: client))

        let windowState = try XCTUnwrap(host.panelStates.last?.windowState)
        let firstCandidate = try XCTUnwrap(windowState.viewModel.prefixCandidates.first?.text)
        XCTAssertEqual(windowState.viewModel.rawInput, "ni")
        XCTAssertNil(windowState.viewModel.preeditDisplayText)
        XCTAssertEqual(client.markedTextWrites.map(\.text), ["n", "ni"])
        XCTAssertTrue(client.markedTextWrites.allSatisfy(\.isAttributed))
        XCTAssertEqual(client.insertTextWrites.count, 0)
        XCTAssertEqual(coordinator.composedString() as? String, "ni")

        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(Array(client.writeEventKinds.suffix(2)), ["markedText", "insertText"])
        XCTAssertEqual(client.markedTextWrites.last?.text, "")
        XCTAssertEqual(client.insertTextWrites.last?.text, firstCandidate)
        XCTAssertEqual(host.hideCandidatePanelCount, 1)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testTerminalHostKeepsIdlePassthroughAndActivePlaceholderCommitPath() throws {
        let client = FakeInputControllerClient()
        client.bundleIdentifier = "com.apple.Terminal"
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertFalse(coordinator.handleText("a", client: client))
        XCTAssertFalse(coordinator.handleText("1", client: client))
        XCTAssertFalse(coordinator.handleText(" ", client: client))
        XCTAssertFalse(coordinator.handleText(".", client: client))
        XCTAssertTrue(client.markedTextWrites.isEmpty)
        XCTAssertTrue(client.insertTextWrites.isEmpty)
        XCTAssertTrue(host.panelStates.isEmpty)

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "/", keyCode: 44, modifiers: [.option]),
                client: client
            )
        )
        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertTrue(coordinator.handleText("i", client: client))

        let windowState = try XCTUnwrap(host.panelStates.last?.windowState)
        let firstCandidate = try XCTUnwrap(windowState.viewModel.prefixCandidates.first?.text)
        XCTAssertEqual(windowState.viewModel.preeditDisplayText, "ni")
        XCTAssertEqual(Set(client.markedTextWrites.map(\.text)), ["\u{3000}"])
        XCTAssertTrue(client.markedTextWrites.allSatisfy(\.isAttributed))

        XCTAssertTrue(coordinator.handleText(" ", client: client))

        XCTAssertEqual(Array(client.writeEventKinds.suffix(2)), ["markedText", "insertText"])
        XCTAssertEqual(client.markedTextWrites.last?.text, "")
        XCTAssertEqual(client.insertTextWrites.last?.text, firstCandidate)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    @MainActor
    func testDeactivateLifecycleCommitsRawUsingPreResetSnapshotAndResetsNativeState() async {
        let client = FakeInputControllerClient()
        let contextRecorder = RecordingAIContextEventRecorder()
        let conversionRecorder = RefactorRegressionConversionRecorder()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: RecordingContinuationProvider(),
            aiContextEventRecorder: contextRecorder,
            conversionEngine: ResetRecordingNativeConversionEngine(recorder: conversionRecorder)
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))

        coordinator.deactivateServer(client: client)

        XCTAssertEqual(host.hideCandidatePanelCount, 1)
        XCTAssertEqual(client.markedTextWrites.last?.text, "")
        XCTAssertEqual(client.insertTextWrites.last?.text, "n")
        XCTAssertEqual(conversionRecorder.resetCount, 1)
        XCTAssertEqual(coordinator.composedString() as? String, "")

        let recorded = await waitUntil {
            await contextRecorder.events.contains {
                $0.rawInput == "n"
                    && $0.committedText == "n"
                    && $0.commitKind == .raw
                    && $0.deleteCountBeforeCommit == 0
            }
        }
        XCTAssertTrue(recorded)
    }

    func testCloseLifecycleClearsOwnedMarkedTextWithoutCommittingRawText() {
        let client = FakeInputControllerClient()
        let conversionRecorder = RefactorRegressionConversionRecorder()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: ResetRecordingNativeConversionEngine(recorder: conversionRecorder)
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))

        coordinator.inputControllerWillClose()

        XCTAssertEqual(host.hideCandidatePanelCount, 1)
        XCTAssertEqual(client.markedTextWrites.last?.text, "")
        XCTAssertTrue(client.insertTextWrites.isEmpty)
        XCTAssertEqual(conversionRecorder.resetCount, 1)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testNativeEndedLifecycleClearsOwnedMarkedTextWithoutPanelRevival() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: NativeEndedNoCommitConversionEngine()
        )

        XCTAssertTrue(coordinator.handleText("n", client: client))
        let panelUpdateCountBeforeCommit = host.panelStates.count

        coordinator.commitComposition(client: client)
        host.runScheduledOperations()

        XCTAssertEqual(client.insertTextWrites.count, 0)
        XCTAssertEqual(client.markedTextWrites.last?.text, "")
        XCTAssertEqual(host.hideCandidatePanelCount, 1)
        XCTAssertEqual(host.panelStates.count, panelUpdateCountBeforeCommit)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    func testDelayedReanchorDoesNotRevivePanelAfterCompositionCommit() throws {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText("n", client: client))
        XCTAssertFalse(host.scheduledOperations.isEmpty)
        let firstCandidate = try XCTUnwrap(host.panelStates.last?.windowState.viewModel.prefixCandidates.first?.text)

        XCTAssertTrue(coordinator.handleText(" ", client: client))
        let panelUpdateCountAfterCommit = host.panelStates.count
        let hideCountAfterCommit = host.hideCandidatePanelCount

        host.runScheduledOperations()

        XCTAssertEqual(client.insertTextWrites.last?.text, firstCandidate)
        XCTAssertEqual(host.panelStates.count, panelUpdateCountAfterCommit)
        XCTAssertEqual(host.hideCandidatePanelCount, hideCountAfterCommit)
        XCTAssertEqual(coordinator.composedString() as? String, "")
    }

    private func makeCoordinator(
        client: FakeInputControllerClient,
        provider: (any LLMProvider)? = nil,
        aiContextEventRecorder: (any AIContextEventRecording)? = nil,
        inputModePreferences: InputModePreferences = .standard,
        runtimePreferences: InputMethodRuntimePreferences = .standard,
        conversionEngine: (any KnowTypeConversionEngine)? = nil,
        enablesAsyncSuggestionRefresh: Bool = false
    ) -> (
        InputControllerCoordinator,
        FakeInputControllerHost,
        FakeUserSelectionHistoryPersistence
    ) {
        let host = FakeInputControllerHost()
        host.currentClientValue = client
        let persistence = FakeUserSelectionHistoryPersistence()
        let coordinator = InputControllerCoordinator(
            provider: provider,
            traditionalInputEngine: nil,
            inputModePreferenceStore: FixedInputModePreferenceStore(preferences: inputModePreferences),
            runtimePreferenceStore: FixedInputMethodRuntimePreferenceStore(preferences: runtimePreferences),
            initialRuntimePreferences: runtimePreferences,
            initialAppBundleID: client.bundleIdentifier,
            userSelectionHistoryPersistence: persistence,
            aiContextEventRecorder: aiContextEventRecorder,
            conversionEngine: conversionEngine ?? FixtureNativeConversionEngine(),
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

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @escaping () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return await condition()
    }
}

private final class RefactorRegressionConversionRecorder: @unchecked Sendable {
    var resetCount = 0
}

private struct ResetRecordingNativeConversionEngine: KnowTypeConversionEngine {
    var isNativeActive = true
    let recorder: RefactorRegressionConversionRecorder
    private var rawInput = ""

    var activeSchemaID = "pinyin_simp"

    init(recorder: RefactorRegressionConversionRecorder) {
        self.recorder = recorder
    }

    var snapshot: ConversionEngineSnapshot {
        guard !rawInput.isEmpty else {
            return ConversionEngineSnapshot(engineName: "native-reset-recording")
        }
        return ConversionEngineSnapshot(
            rawInput: rawInput,
            preedit: rawInput,
            candidates: [ConversionEngineCandidate(text: "候选\(rawInput)", index: 0, source: "native-reset-recording")],
            highlightedIndex: 0,
            pageSize: 1,
            pageNumber: 0,
            isLastPage: true,
            engineName: "native-reset-recording"
        )
    }

    mutating func reset() {
        recorder.resetCount += 1
        rawInput = ""
    }

    mutating func process(_ key: ConversionEngineKey) -> ConversionEngineResult {
        switch key {
        case .text(let text):
            rawInput += text
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .deleteBackward:
            if !rawInput.isEmpty {
                rawInput.removeLast()
            }
            return ConversionEngineResult(handled: true, snapshot: snapshot)
        case .space,
             .selectCandidateOnCurrentPage,
             .selectCandidate,
             .highlightCandidateOnCurrentPage,
             .pageUp,
             .pageDown,
             .commitComposition:
            return ConversionEngineResult(handled: false, snapshot: snapshot)
        }
    }
}

private actor RecordingAIContextEventRecorder: AIContextEventRecording {
    private var recordedEvents: [AITypingEvent] = []

    func record(_ event: AITypingEvent) async {
        recordedEvents.append(event)
    }

    var events: [AITypingEvent] {
        recordedEvents
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
    private(set) var candidatePanelFrames: [CandidatePanelFrame] = []
    private(set) var hideCandidatePanelCount = 0
    private(set) var scheduledOperations: [@Sendable () -> Void] = []
    private(set) var postInsertVerificationOperations: [@Sendable () -> Void] = []

    var currentClient: InputControllerClient? {
        currentClientValue
    }

    func updateComposition() {
        updateCompositionCount += 1
    }

    func applyCandidatePanelFrame(_ frame: CandidatePanelFrame, locale _: KnowTypeLocale) {
        candidatePanelFrames.append(frame)
        if frame.isVisible || frame.visibilityReason == .layoutImpossible {
            panelStates.append(frame.panelModel)
        }
        if !frame.isVisible {
            hideCandidatePanelCount += 1
        }
    }

    func scheduleDelayedReanchor(_ operation: @escaping @Sendable () -> Void) {
        scheduledOperations.append(operation)
    }

    func schedulePostInsertCaretVerification(_ operation: @escaping @Sendable () -> Void) {
        postInsertVerificationOperations.append(operation)
    }

    func runScheduledOperations() {
        let operations = scheduledOperations
        scheduledOperations.removeAll()
        operations.forEach { $0() }
    }

    func runPostInsertVerificationOperations() {
        let operations = postInsertVerificationOperations
        postInsertVerificationOperations.removeAll()
        operations.forEach { $0() }
    }
}

private final class FakeInputControllerClient: InputControllerClient, @unchecked Sendable {
    struct MarkedTextWrite: Equatable {
        var text: String
        var isAttributed: Bool
        var attributeKeyNames: Set<String>
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
    private(set) var writeEventKinds: [String] = []

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
        _ text: InputClientMarkedText,
        selectionRange: NSRange,
        replacementRange: NSRange
    ) {
        writeEventKinds.append("markedText")
        markedTextWrites.append(
            MarkedTextWrite(
                text: text.string,
                isAttributed: text.isAttributed,
                attributeKeyNames: text.attributeKeyNames,
                selectionRange: selectionRange,
                replacementRange: replacementRange
            )
        )
        if text.string.isEmpty {
            markedRangeValue = nil
        } else {
            let location = replacementRange.location == NSNotFound
                ? selectedRangeValue.location
                : replacementRange.location
            markedRangeValue = NSRange(location: location, length: (text.string as NSString).length)
        }
    }

    func insertText(_ text: String, replacementRange: NSRange) {
        writeEventKinds.append("insertText")
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

private actor CountingRimeUserDBTextSnapshotProvider: RimeUserDBTextSnapshotProviding {
    private var count = 0
    private var schemaIDs: [String] = []

    func userDBTextSnapshot(schemaID: String) async throws -> RimeUserDBTextSnapshot {
        count += 1
        schemaIDs.append(schemaID)
        return RimeUserDBTextSnapshot(
            schemaID: schemaID,
            fileURL: URL(fileURLWithPath: "/tmp/\(schemaID).userdb.txt"),
            content: "长期高频\tchang qi gao pin\t5\n"
        )
    }

    var requestCount: Int {
        count
    }

    var requestedSchemaIDs: [String] {
        schemaIDs
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
        let attributed = string as? NSAttributedString
        let plain = string as? String
        markedTextWrites.append(
            FakeInputControllerClient.MarkedTextWrite(
                text: attributed?.string ?? plain ?? "",
                isAttributed: attributed != nil,
                attributeKeyNames: Self.attributeKeyNames(in: attributed),
                selectionRange: selectionRange,
                replacementRange: replacementRange
            )
        )
    }

    private static func attributeKeyNames(in text: NSAttributedString?) -> Set<String> {
        guard let text,
              text.length > 0 else {
            return []
        }
        var names: Set<String> = []
        text.enumerateAttributes(
            in: NSRange(location: 0, length: text.length),
            options: []
        ) { attributes, _, _ in
            attributes.keys.forEach { names.insert($0.rawValue) }
        }
        return names
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
