import CoreGraphics
import XCTest
import KnowTypeAI
import KnowTypeCore
@testable import KnowTypeInputMethod

final class InputCandidatePanelPublicationRuntimeTests: XCTestCase {
    func testPublishVisiblePanelPreservesLayoutPlacementAIAndPreedit() {
        let host = RecordingCandidatePanelHost()
        let runtime = InputCandidatePanelPublicationRuntime(
            host: host,
            taskSupervisor: InputTaskSupervisor()
        )

        let result = runtime.publishImmediately(
            snapshot: snapshot(rawInput: "ni", suggestion: suggestion()),
            request: {
                request(
                    rawInput: "ni",
                    suggestion: suggestion(),
                    anchorResult: CandidateAnchorResult(
                        rect: CGRect(x: 40, y: 500, width: 0, height: 18),
                        source: .firstRectMarkedEnd,
                        isFresh: true
                    ),
                    placementPreference: .preferVisualAbove,
                    preeditDisplayText: "ni",
                    aiRecommendation: .pending(requestID: UUID()),
                    savedPageSize: 9,
                    effectivePageSize: 6,
                    layoutMode: .verticalPreferred
                )
            },
            locale: .zhCN
        )

        let state = result.state.windowState
        XCTAssertTrue(result.isVisible)
        XCTAssertEqual(result.visibilityReason, .compositionActive)
        XCTAssertEqual(state.anchorRect, CGRect(x: 40, y: 500, width: 0, height: 18))
        XCTAssertEqual(state.anchorSource, .firstRectMarkedEnd)
        XCTAssertEqual(state.paging.pageSize, 6)
        XCTAssertEqual(state.layoutMode, .verticalPreferred)
        XCTAssertEqual(state.placementPreference, .preferVisualAbove)
        XCTAssertEqual(state.viewModel.preeditDisplayText, "ni")
        XCTAssertEqual(state.viewModel.aiRecommendation.displayText, "AI 推荐中...")
        XCTAssertEqual(host.panelStates.last, result.state)
        XCTAssertEqual(host.hideCount, 0)
    }

    func testEmptyRawHidesAndReportsRawEmpty() {
        let host = RecordingCandidatePanelHost()
        let supervisor = InputTaskSupervisor()
        let runtime = InputCandidatePanelPublicationRuntime(host: host, taskSupervisor: supervisor)

        let result = runtime.publishImmediately(
            snapshot: snapshot(rawInput: "", suggestion: nil),
            request: { request(rawInput: "", suggestion: nil) },
            locale: .zhCN
        )

        XCTAssertFalse(result.isVisible)
        XCTAssertTrue(result.didHide)
        XCTAssertEqual(result.visibilityReason, .rawEmpty)
        XCTAssertEqual(result.state, CandidatePanelState())
        XCTAssertEqual(host.hideCount, 1)
        XCTAssertEqual(supervisor.cancellationCount(for: .panelRender), 0)
    }

    func testStaleSuggestionHidesAndReportsStaleUpdate() {
        let host = RecordingCandidatePanelHost()
        let runtime = InputCandidatePanelPublicationRuntime(
            host: host,
            taskSupervisor: InputTaskSupervisor()
        )

        let result = runtime.publishImmediately(
            snapshot: snapshot(
                rawInput: "ni",
                suggestion: suggestion(),
                lastSuggestionRawInput: "n"
            ),
            request: { request(rawInput: "ni", suggestion: suggestion()) },
            locale: .zhCN
        )

        XCTAssertFalse(result.isVisible)
        XCTAssertTrue(result.didHide)
        XCTAssertEqual(result.visibilityReason, .staleUpdate)
        XCTAssertEqual(host.hideCount, 1)
    }

    func testAnchorNonePublishesUndisplayablePanelWithoutResetHidePath() {
        let host = RecordingCandidatePanelHost()
        let runtime = InputCandidatePanelPublicationRuntime(
            host: host,
            taskSupervisor: InputTaskSupervisor()
        )

        let result = runtime.publishImmediately(
            snapshot: snapshot(rawInput: "ni", suggestion: suggestion()),
            request: {
                request(
                    rawInput: "ni",
                    suggestion: suggestion(),
                    anchorResult: .none
                )
            },
            locale: .zhCN
        )

        XCTAssertFalse(result.isVisible)
        XCTAssertFalse(result.didHide)
        XCTAssertEqual(result.visibilityReason, .layoutImpossible)
        XCTAssertEqual(result.state.windowState.viewModel.rawInput, "ni")
        XCTAssertEqual(result.state.windowState.viewModel.prefixCandidates.count, 2)
        XCTAssertEqual(host.panelStates.last, result.state)
        XCTAssertEqual(host.hideCount, 1)
    }

    @MainActor
    func testAsyncPublishAppliesOnlyLatestMatchingSnapshot() async {
        let host = RecordingCandidatePanelHost()
        let runtime = InputCandidatePanelPublicationRuntime(
            host: host,
            taskSupervisor: InputTaskSupervisor()
        )
        let current = TestBox(snapshot(rawInput: "n", suggestion: nil, rawRevision: 1))
        var appliedResults: [InputCandidatePanelPublicationResult] = []
        let applied = expectation(description: "latest panel publication applies")

        _ = runtime.publish(
            snapshot: current.value,
            enablesAsyncRefresh: true,
            request: {
                request(rawInput: "n", suggestion: nil)
            },
            currentSnapshot: {
                current.value
            },
            locale: .zhCN,
            onPublication: { result in
                appliedResults.append(result)
            }
        )
        current.value = snapshot(rawInput: "ni", suggestion: suggestion(), rawRevision: 2)
        _ = runtime.publish(
            snapshot: current.value,
            enablesAsyncRefresh: true,
            request: {
                request(rawInput: "ni", suggestion: suggestion())
            },
            currentSnapshot: {
                current.value
            },
            locale: .zhCN,
            onPublication: { result in
                appliedResults.append(result)
                applied.fulfill()
            }
        )

        await fulfillment(of: [applied], timeout: 1.0)

        XCTAssertEqual(appliedResults.count, 1)
        XCTAssertEqual(appliedResults.last?.state.windowState.viewModel.rawInput, "ni")
        XCTAssertEqual(host.panelStates.count, 1)
        XCTAssertEqual(host.panelStates.last?.windowState.viewModel.rawInput, "ni")
    }

    func testHideCancelsPendingPublicationAndDelayedReanchor() async {
        let host = RecordingCandidatePanelHost()
        let supervisor = InputTaskSupervisor()
        let runtime = InputCandidatePanelPublicationRuntime(host: host, taskSupervisor: supervisor)
        let reanchorCount = TestCounter()

        _ = runtime.publish(
            snapshot: snapshot(rawInput: "n", suggestion: nil, rawRevision: 1),
            enablesAsyncRefresh: true,
            request: {
                request(rawInput: "n", suggestion: nil)
            },
            currentSnapshot: {
                snapshot(rawInput: "n", suggestion: nil, rawRevision: 1)
            },
            locale: .zhCN,
            onPublication: { _ in }
        )
        runtime.scheduleDelayedReanchor(
            rawInput: "n",
            compositionID: 1,
            currentSnapshot: {
                InputCandidatePanelReanchorSnapshot(
                    rawInput: "n",
                    compositionID: 1,
                    hasActiveComposition: true
                )
            },
            publish: {
                reanchorCount.increment()
            }
        )

        let result = runtime.hide(reason: .escape, compositionID: 1, rawRevision: 1, rawLength: 1)
        host.runScheduledOperations()
        await Task.yield()

        XCTAssertFalse(result.isVisible)
        XCTAssertTrue(result.didHide)
        XCTAssertEqual(host.hideCount, 1)
        XCTAssertEqual(host.panelStates.count, 0)
        XCTAssertEqual(reanchorCount.value, 0)
        XCTAssertGreaterThanOrEqual(supervisor.cancellationCount(for: .panelRender), 1)
    }

    func testDelayedReanchorPublishesOnlyForMatchingActiveComposition() {
        let host = RecordingCandidatePanelHost()
        let runtime = InputCandidatePanelPublicationRuntime(
            host: host,
            taskSupervisor: InputTaskSupervisor()
        )
        let current = TestBox(InputCandidatePanelReanchorSnapshot(
            rawInput: "n",
            compositionID: 1,
            hasActiveComposition: true
        ))
        let publishCount = TestCounter()

        runtime.scheduleDelayedReanchor(
            rawInput: "n",
            compositionID: 1,
            currentSnapshot: { current.value },
            publish: { publishCount.increment() }
        )
        current.value = InputCandidatePanelReanchorSnapshot(
            rawInput: "ni",
            compositionID: 1,
            hasActiveComposition: true
        )
        runtime.scheduleDelayedReanchor(
            rawInput: "ni",
            compositionID: 1,
            currentSnapshot: { current.value },
            publish: { publishCount.increment() }
        )
        host.runScheduledOperations()

        XCTAssertEqual(publishCount.value, 1)
    }

    func testSelectionHelpersUseVisibleRowsAndPaging() {
        let host = RecordingCandidatePanelHost()
        let runtime = InputCandidatePanelPublicationRuntime(
            host: host,
            taskSupervisor: InputTaskSupervisor()
        )
        _ = runtime.publishImmediately(
            snapshot: snapshot(rawInput: "candidate", suggestion: multiPageSuggestion(count: 12)),
            request: {
                request(
                    rawInput: "candidate",
                    suggestion: multiPageSuggestion(count: 12),
                    effectivePageSize: 6
                )
            },
            locale: .zhCN
        )

        let moved = runtime.moveLocalSelection(.pageDown)
        let selected = runtime.selectVisiblePrefixCandidate(shortcutNumber: 2)
        let invisible = runtime.selectVisibleRow(.prefixCandidate(0))

        XCTAssertEqual(moved?.state.windowState.selection, .prefixCandidate(6))
        XCTAssertEqual(selected?.state.windowState.selection, .prefixCandidate(7))
        XCTAssertNil(invisible)
    }
}

private func snapshot(
    rawInput: String,
    suggestion: SuggestionResponse?,
    rawRevision: Int = 1,
    lastSuggestionRawInput: String? = nil,
    nativeIsActive: Bool = false,
    nativeHasActiveInput: Bool = false
) -> InputCandidatePanelPublicationSnapshot {
    InputCandidatePanelPublicationSnapshot(
        rawInput: rawInput,
        compositionID: 1,
        rawRevision: rawRevision,
        suggestion: suggestion,
        lastSuggestionRawInput: lastSuggestionRawInput ?? (suggestion == nil ? nil : rawInput),
        nativeIsActive: nativeIsActive,
        nativeHasActiveInput: nativeHasActiveInput
    )
}

private func request(
    rawInput: String,
    suggestion: SuggestionResponse?,
    anchorResult: CandidateAnchorResult = CandidateAnchorResult(
        rect: CGRect(x: 20, y: 400, width: 0, height: 18),
        source: .firstRectMarkedEnd,
        isFresh: true
    ),
    placementPreference: CandidatePanelPlacementPreference = .automatic,
    preeditDisplayText: String? = nil,
    aiRecommendation: AIRecommendationState = .idle,
    savedPageSize: Int = CandidatePanelPagingState.defaultPageSize,
    effectivePageSize: Int = CandidatePanelPagingState.defaultPageSize,
    layoutMode: CandidatePanelLayoutMode = .adaptive,
    preferredSelection: CandidatePanelSelection? = nil
) -> InputCandidatePanelPublicationRequest {
    InputCandidatePanelPublicationRequest(
        snapshot: snapshot(rawInput: rawInput, suggestion: suggestion),
        anchorResult: anchorResult,
        placementPreference: placementPreference,
        preeditDisplayText: preeditDisplayText,
        aiRecommendation: aiRecommendation,
        savedPageSize: savedPageSize,
        effectivePageSize: effectivePageSize,
        layoutMode: layoutMode,
        preferredSelection: preferredSelection
    )
}

private func suggestion() -> SuggestionResponse {
    SuggestionResponse(
        prefixCandidates: [
            CorrectionCandidate(
                text: "你",
                source: "local",
                confidence: 1.0,
                correctionLevel: .contextual
            ),
            CorrectionCandidate(
                text: "呢",
                source: "local",
                confidence: 0.8,
                correctionLevel: .contextual
            )
        ],
        lockedPrefix: LockedPrefix(text: "你", rawInput: "ni", candidateID: "local"),
        continuationCandidates: [
            ContinuationCandidate(
                text: "好",
                lengthLevel: .medium,
                confidence: 0.9,
                provider: "test"
            )
        ],
        latencyMs: 1
    )
}

private func multiPageSuggestion(count: Int) -> SuggestionResponse {
    SuggestionResponse(
        prefixCandidates: (0..<count).map { index in
            CorrectionCandidate(
                text: "候选\(index + 1)",
                source: "local",
                confidence: 1.0,
                correctionLevel: .contextual
            )
        },
        lockedPrefix: nil,
        continuationCandidates: [],
        latencyMs: 1
    )
}

private final class RecordingCandidatePanelHost: InputControllerHost {
    var currentClient: InputControllerClient?
    private(set) var panelStates: [CandidatePanelState] = []
    private(set) var hideCount = 0
    private var scheduledOperations: [@Sendable () -> Void] = []

    func updateComposition() {}

    func updateCandidatePanel(state: CandidatePanelState, locale _: KnowTypeLocale) {
        panelStates.append(state)
    }

    func hideCandidatePanel() {
        hideCount += 1
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

private final class TestBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        self.storedValue = value
    }

    var value: Value {
        get {
            lock.lock()
            let value = storedValue
            lock.unlock()
            return value
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }
}

private final class TestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        let value = count
        lock.unlock()
        return value
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
