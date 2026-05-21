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
        let firstCandidate = host.panelStates.last?.windowState.viewModel.prefixCandidates.first?.text
        XCTAssertNotNil(firstCandidate)
        client.markedRangeValue = NSRange(location: 7, length: 1)

        let handled = coordinator.handleText(" ", client: client)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertTextWrites.count, 1)
        XCTAssertEqual(client.insertTextWrites[0].text, firstCandidate)
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

        for character in "ni" {
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

        for character in "ni" {
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

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\t", keyCode: 48),
                client: client
            )
        )

        XCTAssertEqual(client.insertTextWrites.last?.text, "\(prefix)\(continuation)")
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

        for character in "ni" {
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
        XCTAssertEqual(coordinator.composedString() as? String, "ni")
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

    func testCodeAppDefaultsToChinesePunctuation() {
        let client = FakeInputControllerClient()
        client.bundleIdentifier = "com.openai.codex"
        let (coordinator, _, _) = makeCoordinator(client: client)

        XCTAssertTrue(coordinator.handleText(".", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, "。")
    }

    func testCodeAppPunctuationPreferenceCanOverrideDefaultToEnglish() {
        let client = FakeInputControllerClient()
        client.bundleIdentifier = "com.openai.codex"
        let preferences = InputModePreferences(
            codeAppState: InputModeState(punctuationMode: .english, symbolWidth: .halfWidth)
        )
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            inputModePreferences: preferences
        )

        XCTAssertTrue(coordinator.handleText(".", client: client))

        XCTAssertEqual(client.insertTextWrites.last?.text, ".")
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
        XCTAssertTrue(requests.contains { $0.traditionalCandidate.text == "你是谁" })

        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\t", keyCode: 48),
                client: client
            )
        )
        XCTAssertEqual(client.insertTextWrites.last?.text, "你是谁继续推进")
    }

    @MainActor
    func testAIRecommendationRequestCarriesLexicalProfile() async throws {
        let client = FakeInputControllerClient()
        let provider = RecordingContinuationProvider()
        let aiProvider = RecordingAIRecommendationProvider()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            provider: provider,
            aiRecommendationProvider: aiProvider,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "ni" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        let hasAIRecommendation = await waitUntilOnMainActor {
            host.panelStates.last?.windowState.viewModel.aiRecommendation.displayText == "你继续推进"
        }
        XCTAssertTrue(hasAIRecommendation)
        let requests = await aiProvider.requests
        let request = try XCTUnwrap(requests.last)

        XCTAssertTrue(request.lexicalContext?.markdown.contains("你") == true)
        XCTAssertTrue(request.lexicalContext?.sourceSummary.contains { $0.hasPrefix("rime-candidates: ") } == true)
    }

    @MainActor
    func testProtectedAppInputDoesNotReachAIRecommendationOrLaterLexicalProfile() async throws {
        let client = FakeInputControllerClient()
        client.bundleIdentifier = "com.apple.Terminal"
        let provider = RecordingContinuationProvider()
        let aiProvider = RecordingAIRecommendationProvider()
        let (coordinator, _, _) = makeCoordinator(
            client: client,
            provider: provider,
            aiRecommendationProvider: aiProvider,
            enablesAsyncSuggestionRefresh: true
        )

        for character in "secretphrase" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "\r", keyCode: 36),
                client: client
            )
        )
        try? await Task.sleep(nanoseconds: 100_000_000)
        let protectedRequests = await aiProvider.requests
        XCTAssertTrue(protectedRequests.isEmpty)

        for character in "wojuedezhegefagnan" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }
        XCTAssertTrue(coordinator.handleText(" ", client: client))
        try? await Task.sleep(nanoseconds: 100_000_000)
        let requestsAfterProtectedSelection = await aiProvider.requests
        XCTAssertTrue(requestsAfterProtectedSelection.isEmpty)

        client.bundleIdentifier = "com.example.host"
        for character in "ni" {
            XCTAssertTrue(coordinator.handleText(String(character), client: client))
        }

        var unprotectedRequest: AIRecommendationRequest?
        for _ in 0..<60 {
            let requests = await aiProvider.requests
            unprotectedRequest = requests.last { $0.rawInput == "ni" }
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
        XCTAssertEqual(client.markedTextWrites.last?.replacementRange, NSRange(location: 12, length: 1))
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
        XCTAssertEqual(host.panelStates.last?.windowState.isVisible, false)

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

    func testNativeNumberSelectionWorksWhenPanelIsHidden() {
        let client = FakeInputControllerClient()
        let (coordinator, host, _) = makeCoordinator(
            client: client,
            conversionEngine: PagedNativeConversionEngine(),
            screenProvider: FixedInputControllerScreenProvider(screens: [])
        )

        XCTAssertTrue(coordinator.handleText("s", client: client))
        XCTAssertEqual(host.panelStates.last?.windowState.isVisible, false)
        XCTAssertTrue(
            coordinator.handle(
                stroke: InputKeyStroke(text: "2", keyCode: keyCode(forNumber: 2)),
                client: client
            )
        )

        XCTAssertEqual(client.insertTextWrites.last?.text, "第一页二")
        XCTAssertEqual(coordinator.composedString() as? String, "")
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

        XCTAssertTrue(coordinator.handleText("n", client: client))
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

        XCTAssertEqual(client.insertTextWrites.last?.text, "第一页一－")
    }

    private func makeCoordinator(
        client: FakeInputControllerClient,
        persistence: FakeUserSelectionHistoryPersistence = FakeUserSelectionHistoryPersistence(),
        provider: (any LLMProvider)? = nil,
        aiRecommendationProvider: (any AIRecommendationProviding)? = nil,
        aiContextEventRecorder: (any AIContextEventRecording)? = nil,
        enablesAsyncSuggestionRefresh: Bool = false,
        lexiconRuntime: InputMethodLexiconRuntime = InputMethodLexiconRuntime(directories: []),
        inputModePreferences: InputModePreferences = .standard,
        runtimePreferences: InputMethodRuntimePreferences = .standard,
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
            runtimePreferenceStore: FixedInputMethodRuntimePreferenceStore(preferences: runtimePreferences),
            initialRuntimePreferences: runtimePreferences,
            initialAppBundleID: client.bundleIdentifier,
            userSelectionHistoryPersistence: persistence,
            aiRecommendationProvider: aiRecommendationProvider,
            aiContextEventRecorder: aiContextEventRecorder,
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
}

private struct FixtureNativeConversionEngine: KnowTypeConversionEngine {
    var isNativeActive = true
    private var rawInput = ""
    private var currentSnapshot = ConversionEngineSnapshot(engineName: "native-test")

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
        ConversionEngineSnapshot(
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
    private var rawInput = ""
    private var highlightedIndex = 0
    private var currentSnapshot: ConversionEngineSnapshot

    init(
        candidates: [String],
        recorder: NativeSelectionRecorder,
        spaceCommit: String? = nil,
        source: String = "native-test",
        commitsSelection: Bool = true
    ) {
        self.candidates = candidates
        self.recorder = recorder
        self.spaceCommit = spaceCommit
        self.source = source
        self.commitsSelection = commitsSelection
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
            guard candidates.indices.contains(index) else {
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
        ConversionEngineSnapshot(
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
        let candidate = AIRecommendationCandidate(
            prefixText: request.traditionalCandidate.text,
            continuationText: continuation,
            displayText: request.traditionalCandidate.text + continuation,
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
