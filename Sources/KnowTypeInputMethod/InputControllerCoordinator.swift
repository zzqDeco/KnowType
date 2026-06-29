import CoreGraphics
import Foundation
import KnowTypeAI
import KnowTypeCore
import KnowTypeProviders

final class InputControllerCoordinator: @unchecked Sendable {
    private let provider: (any LLMProvider)?
    private var sessionController: InputSessionController
    private let hasEagerProvider: Bool
    private let canRequestAIRecommendations: Bool
    private var conversionEngine: any KnowTypeConversionEngine
    private let keyMapper = InputKeyCommandMapper()
    private let symbolTransformer = InputSymbolTransformer()
    private let candidateListBuilder = InputCandidateListBuilder()
    private let anchorResolver: CandidateAnchorResolver
    private weak var host: InputControllerHost?
    private let candidatePanelPresenter: CandidatePanelPresenter
    private let inputEventBus = InputEventBus()
    private var rawBuffer = ""
    private var compositionBuffer = CompositionBuffer()
    private var compositionID = 0
    private var rawRevision = 0
    private var lastSuggestion: SuggestionResponse?
    private var lastSuggestionRawInput: String?
    private var locale: KnowTypeLocale = .mixed
    private let inputModePreferenceStore: any InputModePreferenceStore
    private var inputModeRuntime: InputModePreferenceRuntime
    private let runtimePreferenceStore: any InputMethodRuntimePreferenceStore
    private var runtimePreferences: InputMethodRuntimePreferences
    private var suggestionTask: Task<Void, Never>?
    private var displayedNativeCandidates: [InputCandidateSelection] = []
    private var selectedNativeCandidate: InputCandidateSelection?
    private var candidatePanelState = CandidatePanelState()
    private let userSelectionHistoryPersistence: (any InputControllerUserSelectionHistoryPersisting)?
    private var userSelectionHistory: [String]
    private let enablesAsyncSuggestionRefresh: Bool
    private let asyncSuggestionDelayNanoseconds: UInt64
    private var suggestionGeneration = 0
    private var panelUpdateGeneration = 0
    private var panelUpdateTask: Task<Void, Never>?
    private var delayedReanchorGeneration = 0
    private let aiRecommendationProvider: (any AIRecommendationProviding)?
    private let aiRecommendationProviderAvailability: (any AIRecommendationProviderAvailabilitySnapshotting)?
    private let aiContextEventRecorder: (any AIContextEventRecording)?
    private let aiAcceptedLearningRecorder: (any AIAcceptedLearningRecording)?
    private let aiAcceptedFeedbackProvider: (any AIAcceptedFeedbackSnapshotProviding)?
    private let aiAcceptedFeedbackTracker: AIAcceptedFeedbackTracker
    private let aiDiagnosticSink: any AIRecommendationDiagnosticSink
    private var aiRecommendationTask: Task<Void, Never>?
    private var aiRecommendationState: AIRecommendationState = .idle
    private var activeAIRecommendationRequestID: UUID?
    private var aiRecommendationGeneration = 0
    private var deleteCountBeforeCommit = 0
    private var recentLexicalCommits: [String] = []
    private var recentLexicalSelections: [String] = []
    private let lexicalProfileRuntime: LexicalProfileRuntime
    private let inputClientCompositionWriter: InputClientCompositionWriter
    private let taskSupervisor = InputTaskSupervisor()
    private let latencyTracer = InputLatencyTracer()
    private var lastInputModePreferenceReload = Date.distantPast
    private var lastRuntimePreferenceReload = Date.distantPast
    private let startupDebugStartedAt = Date()
    private var didTraceFirstCompositionBegin = false
    private var didTraceFirstCandidatePanelMaterialization = false

    init(
        provider: (any LLMProvider)?,
        traditionalInputEngine: TraditionalInputEngine? = nil,
        lexiconRuntimeSnapshot _: InputMethodLexiconRuntimeSnapshot = InputMethodLexiconRuntimeSnapshot(
            directories: [],
            scheme: .fullPinyin
        ),
        lexiconRuntime _: InputMethodLexiconRuntime = InputMethodLexiconRuntime(directories: []),
        inputModePreferenceStore: any InputModePreferenceStore,
        runtimePreferenceStore: any InputMethodRuntimePreferenceStore = UserDefaultsInputMethodRuntimePreferenceStore.defaultStore(),
        initialRuntimePreferences: InputMethodRuntimePreferences? = nil,
        initialAppBundleID: String?,
        userSelectionHistoryPersistence: (any InputControllerUserSelectionHistoryPersisting)?,
        aiRecommendationProvider: (any AIRecommendationProviding)? = nil,
        aiRecommendationProviderAvailability: (any AIRecommendationProviderAvailabilitySnapshotting)? = nil,
        aiContextEventRecorder: (any AIContextEventRecording)? = nil,
        aiAcceptedLearning: (any AIAcceptedLearningRecording & AIAcceptedLearningSnapshotProviding)? = nil,
        aiAcceptedFeedback: (any AIAcceptedFeedbackRecording & AIAcceptedFeedbackSnapshotProviding)? = nil,
        aiDiagnosticSink: any AIRecommendationDiagnosticSink = OSLogAIRecommendationDiagnosticSink(),
        lexicalProfileStore: LexicalProfileStore = .inMemory(),
        lexicalProfileRefreshGate: LexicalProfileRefreshGate = LexicalProfileRefreshGate(),
        rimeUserDBTextProvider: (any RimeUserDBTextSnapshotProviding)? = nil,
        conversionEngine: (any KnowTypeConversionEngine)? = nil,
        conversionEngineFactory: (@Sendable (TraditionalInputEngine?) -> any KnowTypeConversionEngine)? = nil,
        clientCompatibilityPolicy: InputClientCompatibilityPolicy = InputClientCompatibilityPolicy(),
        inputClientWriter: InputClientWriteCoordinator = InputClientWriteCoordinator(),
        host: InputControllerHost,
        anchorResolver: CandidateAnchorResolver,
        enablesAsyncSuggestionRefresh: Bool = true,
        asyncSuggestionDelayNanoseconds: UInt64 = 0
    ) {
        let inputModePreferences = inputModePreferenceStore.loadPreferences()
        let runtimePreferences = initialRuntimePreferences ?? runtimePreferenceStore.loadPreferences()
        self.provider = provider
        self.hasEagerProvider = provider != nil
        self.canRequestAIRecommendations = provider != nil || aiRecommendationProvider != nil
        if let conversionEngine {
            self.conversionEngine = conversionEngine
        } else if let conversionEngineFactory {
            self.conversionEngine = conversionEngineFactory(traditionalInputEngine)
        } else {
            self.conversionEngine = RimeConversionEngine()
        }
        self.sessionController = Self.polishOnlySessionController()
        self.inputModePreferenceStore = inputModePreferenceStore
        self.runtimePreferenceStore = runtimePreferenceStore
        self.runtimePreferences = runtimePreferences
        self.inputModeRuntime = InputModePreferenceRuntime(
            preferences: inputModePreferences,
            appBundleID: initialAppBundleID
        )
        self.userSelectionHistoryPersistence = userSelectionHistoryPersistence
        self.userSelectionHistory = userSelectionHistoryPersistence?
            .loadHistory(maxEntries: Self.maxUserSelectionHistory) ?? []
        self.aiRecommendationProvider = aiRecommendationProvider
        self.aiRecommendationProviderAvailability = aiRecommendationProviderAvailability
        self.aiContextEventRecorder = aiContextEventRecorder
        self.aiAcceptedLearningRecorder = aiAcceptedLearning
        self.aiAcceptedFeedbackProvider = aiAcceptedFeedback
        self.aiAcceptedFeedbackTracker = AIAcceptedFeedbackTracker(
            recorder: aiAcceptedFeedback,
            diagnosticSink: aiDiagnosticSink
        )
        self.aiDiagnosticSink = aiDiagnosticSink
        self.lexicalProfileRuntime = LexicalProfileRuntime(
            store: lexicalProfileStore,
            rimeMaintenanceService: rimeUserDBTextProvider,
            acceptedLearningProvider: aiAcceptedLearning,
            diagnosticSink: aiDiagnosticSink,
            refreshGate: lexicalProfileRefreshGate
        )
        self.inputClientCompositionWriter = InputClientCompositionWriter(
            compatibilityPolicy: clientCompatibilityPolicy,
            writeCoordinator: inputClientWriter
        )
        self.host = host
        self.candidatePanelPresenter = CandidatePanelPresenter(host: host)
        self.anchorResolver = anchorResolver
        self.enablesAsyncSuggestionRefresh = enablesAsyncSuggestionRefresh
        self.asyncSuggestionDelayNanoseconds = asyncSuggestionDelayNanoseconds
    }

    private static func polishOnlySessionController() -> InputSessionController {
        InputSessionController { _ in
            SuggestionResponse(
                prefixCandidates: [],
                lockedPrefix: nil,
                continuationCandidates: [],
                latencyMs: 0
            )
        }
    }

    func handleText(_ string: String?, client: InputControllerClient?) -> Bool {
        let stroke = InputKeyStroke(
            text: string ?? "",
            keyCode: Self.textOnlyKeyCode
        )
        return handle(stroke: stroke, client: client)
    }

    func handle(stroke: InputKeyStroke, client: InputControllerClient?) -> Bool {
        return latencyTracer.trace("handle-key") {
            handle(intent: keyMapper.intent(for: stroke), client: client)
        }
    }

    func composedString() -> Any {
        nativeMarkedText() ?? compositionBuffer.displayText
    }

    func originalString() -> NSAttributedString {
        NSAttributedString(string: rawBuffer)
    }

    func candidates() -> [Any] {
        let selections = candidateListBuilder.candidateSelections(
            rawInput: rawBuffer,
            suggestion: lastSuggestion
        )
        displayedNativeCandidates = selections
        return selections.map(\.text)
    }

    func candidateSelectionChanged(_ text: String?) {
        selectNativeCandidate(matching: text)
        if let selectedNativeCandidate {
            _ = highlightNativeSelectionIfNeeded(selectedNativeCandidate, client: host?.currentClient)
        }
    }

    func candidateSelected(_ text: String?, client: InputControllerClient?) {
        selectNativeCandidate(matching: text)
        if let selectedNativeCandidate,
           commitNativeSelectionIfNeeded(selectedNativeCandidate, client: client) {
            return
        }
        commit(action: .space, client: client)
    }

    func hoverCandidatePanelSelection(_ selection: CandidatePanelSelection) {
        guard candidatePanelState.selectVisibleRow(selection) else {
            return
        }
        selectedNativeCandidate = inputCandidateSelection(
            for: selection,
            in: candidatePanelState.windowState.viewModel
        )
        if let selectedNativeCandidate,
           highlightNativeSelectionIfNeeded(selectedNativeCandidate, client: host?.currentClient) {
            return
        }
        candidatePanelPresenter.apply(currentCandidatePanelFrame(reason: .compositionActive), locale: locale)
    }

    func commitCandidatePanelSelection(_ selection: CandidatePanelSelection, client: InputControllerClient?) {
        guard candidatePanelState.selectVisibleRow(selection),
              let inputSelection = inputCandidateSelection(
                  for: selection,
                  in: candidatePanelState.windowState.viewModel
              ) else {
            return
        }
        selectedNativeCandidate = inputSelection
        if commitNativeSelectionIfNeeded(inputSelection, client: client) {
            return
        }
        let result = resultForNumberSelection(inputSelection, client: client)
        learnSelectedPrefix(action: .space, result: result, client: client)
        _ = applyCommitResult(
            result,
            client: client,
            acceptedAIRecommendation: acceptedAIRecommendationCandidate(for: .space, result: result)
        )
    }

    @discardableResult
    func scrollCandidatePanel(_ navigation: InputCandidateNavigation) -> Bool {
        switch navigation {
        case .pageDown, .pageUp:
            return moveCandidateSelection(navigation)
        case .down, .up, .left, .right:
            return false
        }
    }

    func commitComposition(client: InputControllerClient?) {
        let client = effectiveClient(client)
        if conversionEngine.isNativeActive,
           conversionEngine.snapshot.hasComposition {
            let result = conversionEngine.process(.commitComposition)
            if handleNativeConversionResult(result, client: client) {
                return
            }
        }
        let text = compositionBuffer.hasResolvedSegments ? compositionBuffer.commitText : rawBuffer
        guard !text.isEmpty else {
            _ = finishCompositionLifecycle(reason: .commit, client: client, commitPolicy: .none)
            return
        }
        _ = applyCommitResult(.commit(text), client: client)
    }

    func hidePalettes() {
        hideCandidatePanel(reason: .escape)
    }

    func deactivateServer(client: InputControllerClient?) {
        flushUserSelectionHistory()
        aiAcceptedFeedbackTracker.cancel(reason: "deactivate")
        _ = finishCompositionLifecycle(reason: .deactivate, client: client, commitPolicy: .commitRawIfNeeded)
    }

    func inputControllerWillClose() {
        flushUserSelectionHistory()
        cancelActiveAIRecommendationForDiagnostics(
            compositionID: compositionID,
            rawLength: rawBuffer.count,
            reason: "input_controller_will_close"
        )
        aiRecommendationGeneration += 1
        aiRecommendationTask?.cancel()
        aiRecommendationTask = nil
        aiAcceptedFeedbackTracker.cancel(reason: "input_controller_will_close")
        lexicalProfileRuntime.cancelRefresh()
        panelUpdateTask?.cancel()
        taskSupervisor.cancelAll()
        _ = finishCompositionLifecycle(reason: .close, client: nil, commitPolicy: .none)
    }

    func reloadRuntimePreferencesForExternalChange() {
        lastRuntimePreferenceReload = .distantPast
        guard reloadRuntimePreferencesIfNeeded() else {
            return
        }
        let client = host?.currentClient
        publishLocalSuggestionSynchronously(client: client)
        updateCandidatePanelImmediately(suggestion: lastSuggestion, client: client)
    }

    private func handle(intent: InputKeyIntent, client: InputControllerClient?) -> Bool {
        let client = client ?? (hasActiveTextComposition() ? host?.currentClient : nil)
        switch intent {
        case .append(let text):
            if !hasActiveTextComposition() {
                reloadInputModeDefaultsIfNeeded(client: client)
                if shouldPassThroughIdleText(text, client: client, reason: "idle_append") {
                    return false
                }
                if Self.isDirectPassthroughDigitText(text) {
                    return insertDirectPassthroughText(text, client: client)
                }
            }
            return appendComposition(text, client: client)
        case .symbol(let text):
            if conversionEngine.isNativeActive,
               !rawBuffer.isEmpty {
                let result = conversionEngine.process(.text(text))
                if result.handled {
                    return handleNativeConversionResult(result, client: client)
                }
                if handleNativePagingSymbol(text, client: client) {
                    return true
                }
            }
            if rawBuffer.isEmpty {
                reloadInputModeDefaultsIfNeeded(client: client)
                if shouldPassThroughIdleText(text, client: client, reason: "idle_symbol") {
                    return false
                }
            }
            guard let symbol = symbolTransformer.text(for: text, state: inputModeRuntime.state) else {
                return appendComposition(text, client: client)
            }
            return commitSymbol(symbol, client: client)
        case .deleteBackward:
            guard !rawBuffer.isEmpty else {
                _ = aiAcceptedFeedbackTracker.observeDeleteBackward(client: client)
                recordExternalDelete(client: client)
                return false
            }
            deleteCountBeforeCommit += 1
            if !compositionBuffer.undoLastResolvedSegment() {
                rawBuffer.removeLast()
                _ = conversionEngine.process(.deleteBackward)
                rawRevision += 1
                compositionBuffer.updateRawInput(rawBuffer)
                if rawBuffer.isEmpty {
                    deleteCountBeforeCommit = 0
                    conversionEngine.reset()
                    resetAnchorState()
                }
            }
            invalidateSuggestion()
            publishLocalSuggestion(client: client)
            refreshSuggestion(client: client)
            return true
        case .action(let action):
            if action == .toggleSymbolMode {
                inputModeRuntime.togglePunctuationMode()
                return true
            }
            if action == .toggleTextMode {
                inputModeRuntime.toggleTextMode()
                return true
            }
            if action == .space,
               !hasActiveTextComposition() {
                reloadInputModeDefaultsIfNeeded(client: client)
                if shouldPassThroughIdleText(" ", client: client, reason: "idle_space") {
                    return false
                }
            }
            return commit(action: action, client: client)
        case .cancelComposition:
            guard !rawBuffer.isEmpty else {
                return false
            }
            resetComposition(client: client)
            refreshComposition(client: client)
            return true
        case .selectCandidate(let number):
            guard hasActiveTextComposition() else {
                reloadInputModeDefaultsIfNeeded(client: client)
                if shouldPassThroughIdleText(String(number), client: client, reason: "idle_digit") {
                    return false
                }
                return insertDirectPassthroughText(String(number), client: client)
            }
            if conversionEngine.isNativeActive,
               conversionEngine.snapshot.hasComposition,
               number > 0 {
                return selectNativeCandidateOnCurrentPage(number - 1, client: client)
            }
            if candidatePanelState.windowState.isVisible {
                if number == 0,
                   let result = InputSessionCommitPolicy.resultForCandidateNumber(
                       number,
                       rawInput: rawBuffer,
                       suggestion: lastSuggestion,
                       suggestionRawInput: lastSuggestionRawInput
                   ) {
                    return applyCommitResult(result, client: client)
                }
                if number == 0,
                   candidatePanelState.windowState.selection == .rawInput,
                   !rawBuffer.isEmpty {
                    return applyCommitResult(.commit(rawBuffer), client: client)
                }
                if let visibleSelection = candidatePanelState.selectVisiblePrefixCandidate(shortcutNumber: number),
                   let inputSelection = inputCandidateSelection(
                       for: visibleSelection,
                       in: candidatePanelState.windowState.viewModel
                   ) {
                    selectedNativeCandidate = inputSelection
                    if commitNativeSelectionIfNeeded(inputSelection, client: client) {
                        return true
                    }
                    let result = resultForNumberSelection(inputSelection, client: client)
                    learnSelectedPrefix(action: .space, result: result, client: client)
                    return applyCommitResult(
                        result,
                        client: client,
                        acceptedAIRecommendation: acceptedAIRecommendationCandidate(for: .space, result: result)
                    )
                }
                return appendComposition(String(number), client: client)
            }
            return appendComposition(String(number), client: client)
        case .moveCandidateSelection(let navigation):
            return moveCandidateSelection(navigation)
        case .modifierFlagsChanged:
            return false
        case .ignored:
            return false
        }
    }

    private func appendComposition(_ text: String, client: InputControllerClient?) -> Bool {
        beginCompositionIfNeeded(client: client)
        rawBuffer.append(text)
        _ = conversionEngine.process(.text(text))
        rawRevision += 1
        compositionBuffer.updateRawInput(rawBuffer)
        aiRecommendationState = .idle
        invalidateSuggestion()
        publishLocalSuggestion(client: client)
        refreshSuggestion(client: client)
        return true
    }

    private func commitSymbol(_ symbol: String, client: InputControllerClient?) -> Bool {
        guard !rawBuffer.isEmpty else {
            insert(symbol, client: client)
            return true
        }

        if compositionBuffer.hasResolvedSegments,
           !compositionBuffer.isFullyResolved {
            return applyCommitResult(
                .commit(compositionBuffer.commitText + symbol),
                client: client
            )
        }

        let baseResult = commitResult(for: .space, client: client)
        if case .noAction = baseResult,
           compositionBuffer.hasResolvedSegments {
            return applyCommitResult(
                .commit(compositionBuffer.commitText + symbol),
                client: client
            )
        }
        return applyCommitResult(
            InputSymbolCommitPolicy.result(
                symbol: symbol,
                rawInput: rawBuffer,
                baseCommitResult: baseResult
            ),
            client: client
        )
    }

    private func refreshSuggestion(client: InputControllerClient?) {
        suggestionTask?.cancel()
        taskSupervisor.cancel(.localCandidates)
        guard enablesAsyncSuggestionRefresh else {
            return
        }
        let rawInput = rawBuffer
        guard SuggestionRefreshPolicy.shouldRefresh(rawInput: rawInput) else {
            return
        }
        guard !compositionBuffer.isFullyResolved else {
            return
        }
        // Rime already produced the synchronous candidate state. The retired
        // local converter must not run as a delayed second pass over the same
        // keystroke.
    }

    private func refreshResolvedCompositionContinuations(client: InputControllerClient?) {
        guard enablesAsyncSuggestionRefresh,
              compositionBuffer.isFullyResolved else {
            return
        }
        suggestionTask?.cancel()
        let rawInput = rawBuffer
        let lockedPrefixText = compositionBuffer.commitText
        let lockedPrefix = LockedPrefix(
            text: lockedPrefixText,
            rawInput: rawInput,
            candidateID: "composition-buffer"
        )
        let continuations = resolvedCompositionFallbackContinuations(
            lockedPrefixText: lockedPrefixText,
            rawInput: rawInput,
            client: client
        )
        let suggestion = resolvedCompositionSuggestion(
            lockedPrefix: lockedPrefix,
            continuations: continuations,
            fallbackLatency: lastSuggestion?.latencyMs ?? 0
        )
        lastSuggestion = suggestion
        lastSuggestionRawInput = rawInput
        refreshComposition(client: client)
        updateCandidatePanel(suggestion: suggestion, client: client)
        scheduleAIRecommendation(for: suggestion, client: client)
    }

    private func resolvedCompositionSuggestion(
        lockedPrefix: LockedPrefix,
        continuations: [ContinuationCandidate],
        fallbackLatency: Int
    ) -> SuggestionResponse {
        let prefixCandidates = lastSuggestion?.prefixCandidates.isEmpty == false
            ? lastSuggestion?.prefixCandidates ?? []
            : [resolvedCompositionCandidate()]
        return SuggestionResponse(
            prefixCandidates: prefixCandidates,
            lockedPrefix: lockedPrefix,
            continuationCandidates: continuations,
            latencyMs: fallbackLatency
        )
    }

    func resolvedCompositionFallbackContinuations(
        lockedPrefixText: String,
        rawInput: String,
        client: InputControllerClient?
    ) -> [ContinuationCandidate] {
        guard !hasKnownProvider,
              runtimePreferences.localContinuationEnabledWhenNoProvider,
              !TextProtection.requiresNoCorrection(lockedPrefixText, appBundleID: appBundleIdentifier(client: client)),
              !TextProtection.requiresNoCorrection(rawInput, appBundleID: appBundleIdentifier(client: client)) else {
            return []
        }
        return PrefixContinuationEngine().fallbackContinuations(
            for: lockedPrefixText,
            lengthLevel: runtimePreferences.continuationLengthLevel,
            maxCandidates: runtimePreferences.maxContinuationCandidates
        )
    }

    private func resultForNumberSelection(
        _ selection: InputCandidateSelection,
        client: InputControllerClient?
    ) -> InputCommitResult {
        switch selection.kind {
        case .segmentCandidate(let index):
            return applySegmentCandidate(at: index, commitIfFullyResolved: false, client: client)
        case .aiRecommendation:
            return aiRecommendationCommitResult()
        case .rawInput:
            return rawBuffer.isEmpty ? .noAction : .commit(rawBuffer)
        case .prefixCandidate, .fullCandidate, .continuationCandidate:
            if conversionEngine.isNativeActive,
               isNativeSelectablePrefixOrFull(selection) {
                guard let nativeIndex = nativeCandidateIndex(for: selection) else {
                    return .noAction
                }
                let conversionResult = conversionEngine.process(.selectCandidateOnCurrentPage(nativeIndex))
                if let commitText = conversionResult.commitText,
                   !commitText.isEmpty {
                    return .commit(commitText)
                }
                if conversionResult.handled {
                    publishLocalSuggestion(client: client)
                    return .noAction
                }
                return .noAction
            }
            guard let selectedCandidate = sessionSelection(from: selection) else {
                return .noAction
            }
            return InputSessionCommitPolicy.result(
                for: .space,
                rawInput: rawBuffer,
                suggestion: lastSuggestion,
                suggestionRawInput: lastSuggestionRawInput,
                selectedCandidate: selectedCandidate,
                appBundleID: appBundleIdentifier(client: client),
                locale: locale,
                allowsSynchronousFallback: false
            )
        }
    }

    private func selectNativeCandidateOnCurrentPage(_ index: Int, client: InputControllerClient?) -> Bool {
        let snapshot = conversionEngine.snapshot
        guard snapshot.candidates.indices.contains(index) else {
            return true
        }
        let result = conversionEngine.process(.selectCandidateOnCurrentPage(index))
        learnNativeCommitIfFinal(result, client: client)
        _ = handleNativeConversionResult(result, client: client)
        return true
    }

    private func commitNativeSelectionIfNeeded(
        _ selection: InputCandidateSelection,
        client: InputControllerClient?
    ) -> Bool {
        guard conversionEngine.isNativeActive,
              isNativeSelectablePrefixOrFull(selection),
              let nativeIndex = nativeCandidateIndex(for: selection) else {
            return false
        }
        let result = conversionEngine.process(.selectCandidateOnCurrentPage(nativeIndex))
        learnNativeCommitIfFinal(result, client: client)
        return handleNativeConversionResult(result, client: client)
    }

    private func highlightNativeSelectionIfNeeded(
        _ selection: InputCandidateSelection,
        client: InputControllerClient?
    ) -> Bool {
        guard conversionEngine.isNativeActive,
              isNativeSelectablePrefixOrFull(selection),
              let nativeIndex = nativeCandidateIndex(for: selection),
              nativeIndex != conversionEngine.snapshot.highlightedIndex else {
            return false
        }
        let result = conversionEngine.process(.highlightCandidateOnCurrentPage(nativeIndex))
        guard result.handled else {
            return false
        }
        refreshNativeHighlightPresentation(client: client)
        return true
    }

    private func nativeCandidateIndex(for selection: InputCandidateSelection) -> Int? {
        let snapshot = conversionEngine.snapshot
        guard !selection.text.isEmpty else {
            return nil
        }
        if let nativeCandidateIndex = selection.nativeCandidateIndex,
           snapshot.candidates.contains(where: { candidate in
               candidate.index == nativeCandidateIndex && candidate.text == selection.text
           }) {
            return nativeCandidateIndex
        }
        let textMatches = snapshot.candidates.filter { candidate in
            candidate.text == selection.text
        }
        guard textMatches.count == 1 else {
            return nil
        }
        return textMatches[0].index
    }

    private func isNativeSelectablePrefixOrFull(_ selection: InputCandidateSelection) -> Bool {
        switch selection.kind {
        case .prefixCandidate, .fullCandidate:
            return true
        case .rawInput, .segmentCandidate, .continuationCandidate, .aiRecommendation:
            return false
        }
    }

    private func shouldSelectNativeCandidateBeforeSpace(_ selection: InputCandidateSelection) -> Bool {
        guard isNativeSelectablePrefixOrFull(selection),
              let nativeIndex = nativeCandidateIndex(for: selection) else {
            return false
        }
        let snapshot = conversionEngine.snapshot
        return nativeIndex != snapshot.highlightedIndex
    }

    private func aiRecommendationCommitResult() -> InputCommitResult {
        guard case .ready(let candidate) = aiRecommendationState else {
            return .noAction
        }
        return candidate.displayText.isEmpty ? .noAction : .commit(candidate.displayText)
    }

    private func appBundleIdentifier(client: InputControllerClient?) -> String? {
        client?.bundleIdentifier
    }

    private func effectiveClient(_ client: InputControllerClient?) -> InputControllerClient? {
        client ?? host?.currentClient
    }

    private func writeState(hasActiveComposition: Bool? = nil) -> InputClientCompositionWriteState {
        InputClientCompositionWriteState(
            compositionID: compositionID,
            rawLength: rawBuffer.count,
            inputModeState: inputModeRuntime.state,
            hasActiveComposition: hasActiveComposition ?? hasActiveTextComposition()
        )
    }

    private func shouldPassThroughIdleText(
        _ text: String,
        client: InputControllerClient?,
        reason: String
    ) -> Bool {
        inputClientCompositionWriter.shouldPassThroughIdleText(
            text,
            client: client,
            state: writeState(hasActiveComposition: false),
            reason: reason
        )
    }

    private func candidatePanelPlacementPreference(
        client: InputControllerClient?
    ) -> CandidatePanelPlacementPreference {
        appBundleIdentifier(client: client) == "com.apple.Spotlight"
            ? .preferVisualAbove
            : .automatic
    }

    private func publishLocalSuggestion(client: InputControllerClient?) {
        cancelPendingSuggestionRefresh()
        publishLocalSuggestionSynchronously(client: client)
    }

    private func cancelPendingSuggestionRefresh() {
        suggestionGeneration += 1
        suggestionTask?.cancel()
        suggestionTask = nil
        taskSupervisor.cancel(.localCandidates)
    }

    private func publishLocalSuggestionSynchronously(client: InputControllerClient?) {
        guard SuggestionRefreshPolicy.shouldRefresh(rawInput: rawBuffer) else {
            lastSuggestion = nil
            lastSuggestionRawInput = nil
            refreshComposition(client: client)
            updateCandidatePanelImmediately(suggestion: nil, client: client)
            return
        }

        guard let suggestion = conversionSuggestion() else {
            lastSuggestion = nil
            lastSuggestionRawInput = nil
            refreshComposition(client: client)
            updateCandidatePanelImmediately(suggestion: nil, client: client)
            return
        }

        let rimeSuggestion = augmentedSuggestion(suggestion)
        lastSuggestion = rimeSuggestion
        lastSuggestionRawInput = rawBuffer
        refreshComposition(client: client)
        updateCandidatePanelImmediately(suggestion: rimeSuggestion, client: client)
        scheduleAIRecommendation(for: rimeSuggestion, client: client)
    }

    private func refreshNativeHighlightPresentation(client: InputControllerClient?) {
        guard lastSuggestionRawInput == rawBuffer,
              let lastSuggestion else {
            publishLocalSuggestion(client: client)
            return
        }
        refreshComposition(client: client)
        updateCandidatePanelImmediately(suggestion: lastSuggestion, client: client)
    }

    private func conversionSuggestion() -> SuggestionResponse? {
        guard conversionEngine.isNativeActive else {
            return nil
        }
        return conversionEngine.snapshot.suggestionResponse(originalRawInput: rawBuffer)
    }

    private func lexicalContextSnapshot(for _: SuggestionResponse) -> LexicalContextSnapshot? {
        lexicalProfileRuntime.lexicalContextSnapshot(
            schemaID: conversionEngine.activeSchemaID,
            recentCommits: recentLexicalCommits,
            selectionHistory: recentLexicalSelections
        )
    }

    static func confirmedLockedPrefixText(for suggestion: SuggestionResponse) -> String? {
        let text = suggestion.lockedPrefix?.text
        return text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? text : nil
    }

    private func scheduleAIRecommendation(for suggestion: SuggestionResponse, client: InputControllerClient?) {
        let currentAppBundleID = appBundleIdentifier(client: client)
        if let cancelledRequestID = activeAIRecommendationRequestID {
            recordAIDiagnostic(
                .cancelPrevious,
                requestID: cancelledRequestID,
                compositionID: compositionID,
                rawLength: rawBuffer.count,
                appBundleID: currentAppBundleID,
                reason: "new_schedule"
            )
        }
        aiRecommendationTask?.cancel()
        activeAIRecommendationRequestID = nil
        taskSupervisor.cancel(.aiRecommendation)
        aiRecommendationGeneration += 1
        let generation = aiRecommendationGeneration
        let requestID = UUID()
        let lockedPrefixText = Self.confirmedLockedPrefixText(for: suggestion)

        guard !rawBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !compositionBuffer.hasResolvedSegments || compositionBuffer.isFullyResolved else {
            recordAIDiagnostic(
                .skippedIneligible,
                requestID: requestID,
                compositionID: compositionID,
                rawLength: rawBuffer.count,
                prefixLength: lockedPrefixText?.count,
                appBundleID: currentAppBundleID,
                reason: "no_stable_prefix"
            )
            aiRecommendationState = .idle
            updateCandidatePanel(suggestion: suggestion, client: client)
            return
        }

        let triggerDecision = AIRecommendationTriggerPolicy.default.decision(
            rawInput: rawBuffer,
            lockedPrefix: lockedPrefixText
        )
        guard triggerDecision.isEligible else {
            recordAIDiagnostic(
                .skippedPrefixTooShort,
                requestID: requestID,
                compositionID: compositionID,
                rawLength: rawBuffer.count,
                prefixLength: lockedPrefixText?.count,
                appBundleID: currentAppBundleID,
                reason: triggerDecision.rejectionReason?.rawValue ?? "prefix_too_short"
            )
            aiRecommendationState = .idle
            updateCandidatePanel(suggestion: suggestion, client: client)
            return
        }

        guard !TextProtection.containsSecretLikeContent(rawBuffer),
              lockedPrefixText.map({
                  !TextProtection.containsSecretLikeContent($0)
              }) ?? true else {
            recordAIDiagnostic(
                .skippedProtectedText,
                requestID: requestID,
                compositionID: compositionID,
                rawLength: rawBuffer.count,
                prefixLength: lockedPrefixText?.count,
                appBundleID: currentAppBundleID,
                reason: "secret_like_text"
            )
            aiRecommendationState = .ineligible(reason: "AI 已禁用")
            updateCandidatePanel(suggestion: suggestion, client: client)
            return
        }

        guard runtimePreferences.cloudContinuationEnabled else {
            recordAIDiagnostic(
                .skippedDisabled,
                requestID: requestID,
                compositionID: compositionID,
                rawLength: rawBuffer.count,
                prefixLength: lockedPrefixText?.count,
                appBundleID: currentAppBundleID,
                reason: "cloud_continuation_disabled"
            )
            aiRecommendationState = .ineligible(reason: "AI 已关闭")
            updateCandidatePanel(suggestion: suggestion, client: client)
            return
        }

        guard canRequestAIRecommendations else {
            recordAIDiagnostic(
                .skippedNoProvider,
                requestID: requestID,
                compositionID: compositionID,
                rawLength: rawBuffer.count,
                prefixLength: lockedPrefixText?.count,
                appBundleID: currentAppBundleID,
                reason: "provider_not_configured"
            )
            aiRecommendationState = aiRecommendationProvider == nil
                ? .idle
                : .unavailable(reason: "AI 未配置")
            updateCandidatePanel(suggestion: suggestion, client: client)
            return
        }

        guard let aiRecommendationProvider else {
            recordAIDiagnostic(
                .skippedNoProvider,
                requestID: requestID,
                compositionID: compositionID,
                rawLength: rawBuffer.count,
                prefixLength: lockedPrefixText?.count,
                appBundleID: currentAppBundleID,
                reason: "recommendation_provider_missing"
            )
            aiRecommendationState = .idle
            updateCandidatePanel(suggestion: suggestion, client: client)
            return
        }

        let rawInput = rawBuffer
        let currentCompositionID = compositionID
        let currentRawRevision = rawRevision
        let request = AIRecommendationRequest(
            rawInput: rawInput,
            lockedPrefix: lockedPrefixText,
            candidateHints: [],
            appBundleID: currentAppBundleID,
            appName: currentAppBundleID,
            locale: locale,
            compositionID: currentCompositionID,
            requestID: requestID,
            lexicalContext: lexicalContextSnapshot(for: suggestion),
            feedbackContext: aiAcceptedFeedbackProvider?.snapshot(schemaID: conversionEngine.activeSchemaID)
        )
        recordAIDiagnostic(
            .scheduled,
            requestID: requestID,
            compositionID: currentCompositionID,
            rawLength: rawInput.count,
            prefixLength: lockedPrefixText?.count,
            appBundleID: currentAppBundleID
        )
        aiRecommendationState = .pending(requestID: requestID)
        activeAIRecommendationRequestID = requestID
        updateCandidatePanel(suggestion: suggestion, client: client)
        let diagnosticSink = aiDiagnosticSink
        let task = Task.detached(priority: .utility) { [weak self, aiRecommendationProvider, diagnosticSink] in
            let state = await aiRecommendationProvider.recommendation(for: request)
            let patch = AIRecommendationPatch(
                requestID: requestID,
                generation: generation,
                compositionID: currentCompositionID,
                rawRevision: currentRawRevision,
                rawInput: rawInput,
                state: state
            )
            guard !Task.isCancelled else {
                diagnosticSink.record(
                    AIRecommendationDiagnosticEvent(
                        stage: .cancelled,
                        requestID: requestID,
                        compositionID: currentCompositionID,
                        rawLength: rawInput.count,
                        prefixLength: lockedPrefixText?.count,
                        appBundleID: currentAppBundleID,
                        reason: "task_cancelled_before_apply"
                    )
                )
                return
            }
            Task { @MainActor [weak self, diagnosticSink] in
                guard let self else {
                    diagnosticSink.record(
                        AIRecommendationDiagnosticEvent(
                            stage: .staleResultDropped,
                            requestID: requestID,
                            compositionID: currentCompositionID,
                            rawLength: rawInput.count,
                            prefixLength: lockedPrefixText?.count,
                            appBundleID: currentAppBundleID,
                            reason: "coordinator_released"
                        )
                    )
                    return
                }
                guard patch.matches(
                    requestID: self.activeAIRecommendationRequestID,
                    generation: self.aiRecommendationGeneration,
                    compositionID: self.compositionID,
                    rawRevision: self.rawRevision,
                    rawInput: self.rawBuffer
                ) else {
                    let reason = self.activeAIRecommendationRequestID == requestID
                        ? Self.aiDiagnosticReason(for: state)
                        : "request_inactive"
                    if self.activeAIRecommendationRequestID == requestID {
                        self.activeAIRecommendationRequestID = nil
                    }
                    diagnosticSink.record(
                        AIRecommendationDiagnosticEvent(
                            stage: .staleResultDropped,
                            requestID: requestID,
                            compositionID: currentCompositionID,
                            rawLength: rawInput.count,
                            prefixLength: lockedPrefixText?.count,
                            appBundleID: currentAppBundleID,
                            reason: reason
                        )
                    )
                    return
                }
                self.aiRecommendationState = patch.state
                self.clearNoProviderFallbackContinuationsIfProviderIsKnown()
                if self.activeAIRecommendationRequestID == requestID {
                    self.activeAIRecommendationRequestID = nil
                }
                diagnosticSink.record(
                    AIRecommendationDiagnosticEvent(
                        stage: .stateApplied,
                        requestID: requestID,
                        compositionID: currentCompositionID,
                        rawLength: rawInput.count,
                        prefixLength: lockedPrefixText?.count,
                        appBundleID: currentAppBundleID,
                        reason: Self.aiDiagnosticReason(for: patch.state)
                    )
                )
                self.updateCandidatePanel(suggestion: self.lastSuggestion, client: self.host?.currentClient)
            }
        }
        aiRecommendationTask = task
        taskSupervisor.replace(.aiRecommendation, with: task)
    }

    private var hasKnownProvider: Bool {
        hasEagerProvider || aiRecommendationProviderAvailability?.providerAvailability == .available
    }

    private func clearNoProviderFallbackContinuationsIfProviderIsKnown() {
        guard hasKnownProvider,
              let suggestion = lastSuggestion,
              suggestion.lockedPrefix?.candidateID == "composition-buffer",
              !suggestion.continuationCandidates.isEmpty else {
            return
        }
        lastSuggestion = SuggestionResponse(
            prefixCandidates: suggestion.prefixCandidates,
            lockedPrefix: suggestion.lockedPrefix,
            continuationCandidates: [],
            latencyMs: suggestion.latencyMs
        )
    }

    private func recordAIDiagnostic(
        _ stage: AIRecommendationDiagnosticStage,
        requestID: UUID? = nil,
        compositionID: Int? = nil,
        rawLength: Int? = nil,
        prefixLength: Int? = nil,
        appBundleID: String? = nil,
        reason: String? = nil
    ) {
        aiDiagnosticSink.record(
            AIRecommendationDiagnosticEvent(
                stage: stage,
                requestID: requestID,
                compositionID: compositionID,
                rawLength: rawLength,
                prefixLength: prefixLength,
                appBundleID: appBundleID,
                reason: reason
            )
        )
    }

    private static func aiDiagnosticReason(for state: AIRecommendationState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .pending:
            return "pending"
        case .ready:
            return "ready"
        case .ineligible(let reason):
            return "ineligible:\(reason)"
        case .unavailable(let reason):
            return "unavailable:\(reason)"
        }
    }

    private func augmentedSuggestion(_ suggestion: SuggestionResponse) -> SuggestionResponse {
        Self.augmentedSuggestion(
            suggestion,
            compositionBuffer: compositionBuffer,
            rawBuffer: rawBuffer
        )
    }

    private static func augmentedSuggestion(
        _ suggestion: SuggestionResponse,
        compositionBuffer: CompositionBuffer,
        rawBuffer: String
    ) -> SuggestionResponse {
        var prefixCandidates: [CorrectionCandidate]
        if compositionBuffer.isFullyResolved {
            prefixCandidates = [resolvedCompositionCandidate(compositionBuffer: compositionBuffer, rawBuffer: rawBuffer)]
        } else if compositionBuffer.hasResolvedSegments {
            prefixCandidates = []
        } else {
            prefixCandidates = suggestion.prefixCandidates
        }
        let continuations = shouldSuppressContinuations(
            prefixCandidates: prefixCandidates,
            compositionBuffer: compositionBuffer
        )
            ? []
            : suggestion.continuationCandidates
        let lockedPrefix: LockedPrefix?
        if compositionBuffer.isFullyResolved {
            lockedPrefix = LockedPrefix(
                text: compositionBuffer.commitText,
                rawInput: rawBuffer,
                candidateID: "composition-buffer"
            )
        } else {
            lockedPrefix = suggestion.lockedPrefix
        }
        return SuggestionResponse(
            prefixCandidates: prefixCandidates,
            lockedPrefix: lockedPrefix,
            continuationCandidates: continuations,
            latencyMs: suggestion.latencyMs
        )
    }

    private func resolvedCompositionCandidate() -> CorrectionCandidate {
        Self.resolvedCompositionCandidate(
            compositionBuffer: compositionBuffer,
            rawBuffer: rawBuffer
        )
    }

    private static func resolvedCompositionCandidate(
        compositionBuffer: CompositionBuffer,
        rawBuffer: String
    ) -> CorrectionCandidate {
        CorrectionCandidate(
            text: compositionBuffer.commitText,
            source: "composition-buffer",
            confidence: 1.0,
            correctionLevel: .contextual,
            rawRange: compositionBuffer.rawRange,
            segments: compositionBuffer.resolvedSegments
        )
    }

    private func shouldSuppressContinuations(prefixCandidates: [CorrectionCandidate]) -> Bool {
        Self.shouldSuppressContinuations(
            prefixCandidates: prefixCandidates,
            compositionBuffer: compositionBuffer
        )
    }

    private func shouldSuppressTabCommitForPartialComposition() -> Bool {
        if compositionBuffer.hasResolvedSegments && !compositionBuffer.isFullyResolved {
            return true
        }
        guard SuggestionPublicationGuard.hasCurrentSuggestion(
            suggestionRawInput: lastSuggestionRawInput,
            currentRawInput: rawBuffer
        ) else {
            return false
        }
        return shouldSuppressContinuations(prefixCandidates: lastSuggestion?.prefixCandidates ?? [])
    }

    private func hasVisibleContinuationForCurrentSuggestion() -> Bool {
        guard SuggestionPublicationGuard.hasCurrentSuggestion(
            suggestionRawInput: lastSuggestionRawInput,
            currentRawInput: rawBuffer
        ) else {
            return false
        }
        return lastSuggestion?.continuationCandidates.isEmpty == false
    }

    private static func shouldSuppressContinuations(
        prefixCandidates: [CorrectionCandidate],
        compositionBuffer: CompositionBuffer
    ) -> Bool {
        if compositionBuffer.hasResolvedSegments && !compositionBuffer.isFullyResolved {
            return true
        }
        guard !compositionBuffer.isFullyResolved,
              let firstPrefix = prefixCandidates.first else {
            return false
        }
        return isPartialSegmentCandidate(firstPrefix, compositionBuffer: compositionBuffer)
    }

    private func isPartialSegmentCandidate(_ candidate: CorrectionCandidate) -> Bool {
        Self.isPartialSegmentCandidate(candidate, compositionBuffer: compositionBuffer)
    }

    private static func isPartialSegmentCandidate(
        _ candidate: CorrectionCandidate,
        compositionBuffer: CompositionBuffer
    ) -> Bool {
        guard let rawRange = candidate.rawRange else {
            return false
        }
        return rawRange != compositionBuffer.rawRange
    }

    @discardableResult
    private func commit(action: InputAction, client: InputControllerClient?) -> Bool {
        if action == .space,
           !hasActiveTextComposition() {
            return insertDirectPassthroughText(" ", client: client)
        }
        if action == .commitRaw,
           !hasActiveTextComposition() {
            _ = finishCompositionLifecycle(reason: .commit, client: client, commitPolicy: .none)
            return false
        }
        if action == .space,
           conversionEngine.isNativeActive,
           rawBuffer.isEmpty == false {
            if let selectedNativeCandidate,
               shouldCommitSelectedNonNativeCandidateBeforeNativeSpace(selectedNativeCandidate) {
                let result = commitResult(for: action, client: client)
                learnSelectedPrefix(action: action, result: result, client: client)
                return applyCommitResult(
                    result,
                    client: client,
                    acceptedAIRecommendation: acceptedAIRecommendationCandidate(for: action, result: result)
                )
            }
            if let selectedNativeCandidate,
               shouldSelectNativeCandidateBeforeSpace(selectedNativeCandidate),
               let nativeIndex = nativeCandidateIndex(for: selectedNativeCandidate) {
                let result = conversionEngine.process(.selectCandidateOnCurrentPage(nativeIndex))
                learnNativeCommitIfFinal(result, client: client)
                if handleNativeConversionResult(result, client: client) {
                    return true
                }
            }
            let result = conversionEngine.process(.space)
            learnNativeCommitIfFinal(result, client: client)
            if handleNativeConversionResult(result, client: client) {
                return true
            }
            return applyCommitResult(rawBuffer.isEmpty ? .noAction : .commit(rawBuffer), client: client)
        }
        let result = commitResult(for: action, client: client)
        learnSelectedPrefix(action: action, result: result, client: client)
        return applyCommitResult(
            result,
            client: client,
            acceptedAIRecommendation: acceptedAIRecommendationCandidate(for: action, result: result)
        )
    }

    private func shouldCommitSelectedNonNativeCandidateBeforeNativeSpace(
        _ selection: InputCandidateSelection
    ) -> Bool {
        switch selection.kind {
        case .prefixCandidate, .fullCandidate:
            return false
        case .rawInput, .segmentCandidate, .aiRecommendation, .continuationCandidate:
            return true
        }
    }

    @discardableResult
    private func applyCommitResult(
        _ result: InputCommitResult,
        client: InputControllerClient?,
        acceptedAIRecommendation: AIRecommendationCandidate? = nil
    ) -> Bool {
        switch InputCommitResultPolicy.directive(for: result) {
        case .insertAndReset(let text):
            let acceptID = prepareAcceptedFeedbackTracking(
                text: text,
                client: client,
                acceptedAIRecommendation: acceptedAIRecommendation
            )
            recordTypingCommit(
                text,
                client: client,
                acceptedAIRecommendation: acceptedAIRecommendation,
                acceptID: acceptID
            )
            insert(text, client: client)
            if acceptID != nil {
                host?.scheduleDelayedReanchor { [weak self, client] in
                    self?.aiAcceptedFeedbackTracker.verifyPostInsertCaret(client: client)
                }
            }
            resetComposition(client: client)
            return true
        case .requestPolishAndKeepComposition(let text):
            Task { [sessionController] in
                await sessionController.requestPolish(rawInput: text)
            }
            refreshComposition(client: client)
            return true
        case .keepComposition:
            refreshComposition(client: client)
            return true
        case .noAction:
            return InputCommitResultPolicy.shouldConsumeNoAction(hasComposition: !rawBuffer.isEmpty)
        }
    }

    @discardableResult
    private func handleNativeConversionResult(
        _ result: ConversionEngineResult,
        client: InputControllerClient?
    ) -> Bool {
        if let commitText = result.commitText,
           !commitText.isEmpty {
            if result.snapshot.hasComposition {
                recordTypingCommit(commitText, client: client)
                insert(commitText, client: client)
                syncRawBufferToNativeSnapshot(result.snapshot)
                publishLocalSuggestion(client: client)
                return true
            }
            return applyCommitResult(.commit(commitText), client: client)
        }
        guard result.handled else {
            return false
        }
        guard nativeSnapshotHasActiveInput(result.snapshot) else {
            _ = finishCompositionLifecycle(reason: .nativeEnded, client: client, commitPolicy: .none)
            return true
        }
        syncRawBufferToNativeSnapshot(result.snapshot)
        publishLocalSuggestion(client: client)
        return true
    }

    private func nativeSnapshotHasActiveInput(_ snapshot: ConversionEngineSnapshot) -> Bool {
        !snapshot.rawInput.isEmpty || !snapshot.preedit.isEmpty
    }

    private func hasActiveTextComposition() -> Bool {
        !rawBuffer.isEmpty
            || compositionBuffer.hasResolvedSegments
            || conversionEngine.snapshot.hasComposition
    }

    private func learnNativeCommitIfFinal(_ result: ConversionEngineResult, client: InputControllerClient?) {
        guard let commitText = result.commitText,
              !commitText.isEmpty,
              !result.snapshot.hasComposition,
              commitText != rawBuffer else {
            return
        }
        recordUserSelection(commitText, client: client)
    }

    private func syncRawBufferToNativeSnapshot(_ snapshot: ConversionEngineSnapshot) {
        guard rawBuffer != snapshot.rawInput else {
            return
        }
        rawBuffer = snapshot.rawInput
        rawRevision += 1
        compositionBuffer.updateRawInput(rawBuffer)
    }

    private func learnSelectedPrefix(action: InputAction, result: InputCommitResult, client: InputControllerClient?) {
        guard case .commit(let committedText) = result,
              !committedText.isEmpty,
              !shouldSkipPrefixLearning(action: action),
              let prefix = selectedPrefixTextForLearning(),
              prefix != rawBuffer,
              committedText.hasPrefix(prefix) else {
            return
        }
        recordUserSelection(prefix, client: client)
    }

    private func shouldSkipPrefixLearning(action: InputAction) -> Bool {
        if action == .optionR {
            return true
        }
        if action == .tab,
           aiRecommendationState.isSelectableRecommendation {
            return true
        }
        if case .optionNumber(1) = action,
           aiRecommendationState.isSelectableRecommendation {
            return true
        }
        return false
    }

    private func selectedPrefixTextForLearning() -> String? {
        if let selectedNativeCandidate {
            switch selectedNativeCandidate.kind {
            case .rawInput:
                return nil
            case .prefixCandidate(let index), .fullCandidate(let index):
                return lastSuggestion?.prefixCandidates[inputControllerSafe: index]?.text
            case .segmentCandidate:
                return nil
            case .aiRecommendation:
                return nil
            case .continuationCandidate:
                return lastSuggestion?.prefixCandidates.first?.text
            }
        }

        switch candidatePanelState.windowState.selection {
        case .prefixCandidate(let index), .fullCandidate(let index):
            return lastSuggestion?.prefixCandidates[inputControllerSafe: index]?.text
        case .segmentCandidate:
            return nil
        case .aiRecommendation:
            return nil
        case .continuationCandidate:
            return lastSuggestion?.prefixCandidates.first?.text
        case .rawInput, .none:
            return lastSuggestion?.prefixCandidates.first?.text
        }
    }

    private func recordUserSelection(_ text: String, client: InputControllerClient?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        let appBundleID = appBundleIdentifier(client: client)
        guard !TextProtection.requiresNoCorrection(trimmed, appBundleID: appBundleID),
              !TextProtection.requiresNoCorrection(rawBuffer, appBundleID: appBundleID) else {
            return
        }
        publishRuntimeEvent(
            .candidateSelected(
                text: trimmed,
                schemaID: conversionEngine.activeSchemaID,
                compositionID: compositionID
            )
        )
        recordLexicalSelection(trimmed)
        scheduleLexicalProfileRefresh(reason: "selection")
        if let userSelectionHistoryPersistence {
            userSelectionHistory = userSelectionHistoryPersistence.recordSelection(
                trimmed,
                currentHistory: userSelectionHistory,
                maxEntries: Self.maxUserSelectionHistory
            )
            return
        }

        userSelectionHistory.append(trimmed)
        if userSelectionHistory.count > Self.maxUserSelectionHistory {
            userSelectionHistory.removeFirst(userSelectionHistory.count - Self.maxUserSelectionHistory)
        }
    }

    private func recordLexicalSelection(_ text: String) {
        recentLexicalSelections.append(text)
        if recentLexicalSelections.count > Self.maxUserSelectionHistory {
            recentLexicalSelections.removeFirst(recentLexicalSelections.count - Self.maxUserSelectionHistory)
        }
    }

    private func publishRuntimeEvent(_ event: InputRuntimeEvent) {
        Task.detached(priority: .utility) { [inputEventBus] in
            await inputEventBus.publish(event)
        }
    }

    private func flushUserSelectionHistory() {
        userSelectionHistoryPersistence?.flushHistory(
            userSelectionHistory,
            maxEntries: Self.maxUserSelectionHistory
        )
    }

    private func commitResult(for action: InputAction, client: InputControllerClient?) -> InputCommitResult {
        if action == .commitRaw {
            return rawBuffer.isEmpty ? .noAction : .commit(rawBuffer)
        }
        if let aiShortcutResult = InputCommitResultPolicy.aiShortcutResult(
            for: action,
            aiRecommendationState: aiRecommendationState
        ) {
            return aiShortcutResult
        }
        if action == .tab,
           let selectedNativeCandidate,
           case .segmentCandidate = selectedNativeCandidate.kind {
            return .noAction
        }
        if action == .tab,
           shouldSuppressTabCommitForPartialComposition() {
            return .noAction
        }
        if action == .tab,
           enablesAsyncSuggestionRefresh,
           !hasVisibleContinuationForCurrentSuggestion() {
            return .noAction
        }
        if action == .space,
           let selectedNativeCandidate,
           case .aiRecommendation = selectedNativeCandidate.kind {
            return aiRecommendationCommitResult()
        }
        if action == .space,
           let selectedNativeCandidate,
           case .segmentCandidate(let index) = selectedNativeCandidate.kind {
            return applySegmentCandidate(at: index, commitIfFullyResolved: true, client: client)
        }
        if action == .space,
           let selectedNativeCandidate,
           case .continuationCandidate = selectedNativeCandidate.kind {
            let commitSuggestion = commitSuggestionSnapshot(for: action, client: client)
            return InputSessionCommitPolicy.result(
                for: action,
                rawInput: rawBuffer,
                suggestion: commitSuggestion.suggestion,
                suggestionRawInput: commitSuggestion.rawInput,
                selectedCandidate: sessionSelection(from: selectedNativeCandidate),
                appBundleID: appBundleIdentifier(client: client),
                locale: locale,
                runtimePreferences: runtimePreferences,
                allowsSynchronousFallback: false
            )
        }
        if compositionBuffer.hasResolvedSegments,
           compositionBuffer.isFullyResolved {
            if let selectedNativeCandidate,
               case .continuationCandidate(let index) = selectedNativeCandidate.kind,
               action == .space,
               lastSuggestion?.continuationCandidates.indices.contains(index) == true {
                return InputCompositionController().handle(
                    action: .optionNumber(index + 1),
                    prefixCandidates: [resolvedCompositionCandidate()],
                    continuationCandidates: lastSuggestion?.continuationCandidates ?? [],
                    originalText: rawBuffer
                )
            }
            switch action {
            case .space:
                return .commit(compositionBuffer.commitText)
            case .tab:
                guard lastSuggestion?.continuationCandidates.isEmpty == false else {
                    return .noAction
                }
                return InputCompositionController().handle(
                    action: .tab,
                    prefixCandidates: [resolvedCompositionCandidate()],
                    continuationCandidates: lastSuggestion?.continuationCandidates ?? [],
                    originalText: rawBuffer
                )
            case .optionR:
                return .polishRequested(compositionBuffer.commitText)
            case .optionNumber, .toggleSymbolMode, .toggleTextMode, .commitRaw:
                break
            }
        }
        if action == .space,
           conversionEngine.isNativeActive,
           let selectedNativeCandidate,
           shouldSelectNativeCandidateBeforeSpace(selectedNativeCandidate) {
            return resultForNumberSelection(selectedNativeCandidate, client: client)
        }
        if action == .space,
           conversionEngine.isNativeActive,
           let selectedNativeCandidate,
           isNativeSelectablePrefixOrFull(selectedNativeCandidate),
           nativeCandidateIndex(for: selectedNativeCandidate) == nil {
            return resultForNumberSelection(selectedNativeCandidate, client: client)
        }
        if action == .space,
           conversionEngine.isNativeActive {
            let conversionResult = conversionEngine.process(.space)
            if let commitText = conversionResult.commitText,
               !commitText.isEmpty {
                return .commit(commitText)
            }
            if conversionResult.handled {
                publishLocalSuggestion(client: client)
                return .noAction
            }
            if !rawBuffer.isEmpty {
                return .commit(rawBuffer)
            }
        }
        if action == .space,
           !conversionEngine.isNativeActive {
            return rawBuffer.isEmpty ? .noAction : .commit(rawBuffer)
        }
        if case .optionNumber = action,
           !candidatePanelState.windowState.isVisible {
            return .noAction
        }

        let commitSuggestion = commitSuggestionSnapshot(for: action, client: client)
        return InputSessionCommitPolicy.result(
            for: action,
            rawInput: rawBuffer,
            suggestion: commitSuggestion.suggestion,
            suggestionRawInput: commitSuggestion.rawInput,
            selectedCandidate: commitSuggestion.usesPendingFallback
                ? nil
                : sessionSelection(from: selectedNativeCandidate),
            appBundleID: appBundleIdentifier(client: client),
            locale: locale,
            runtimePreferences: runtimePreferences,
            allowsSynchronousFallback: false
        )
    }

    private func commitSuggestionSnapshot(
        for action: InputAction,
        client: InputControllerClient?
    ) -> (suggestion: SuggestionResponse?, rawInput: String?, usesPendingFallback: Bool) {
        if SuggestionPublicationGuard.hasCurrentSuggestion(
            suggestionRawInput: lastSuggestionRawInput,
            currentRawInput: rawBuffer
        ) {
            return (lastSuggestion, lastSuggestionRawInput, false)
        }
        guard enablesAsyncSuggestionRefresh,
              action == .tab,
              SuggestionRefreshPolicy.shouldRefresh(rawInput: rawBuffer) else {
            return (lastSuggestion, lastSuggestionRawInput, false)
        }
        return (lastSuggestion, lastSuggestionRawInput, false)
    }

    private func applySegmentCandidate(
        at index: Int,
        commitIfFullyResolved: Bool,
        client: InputControllerClient?
    ) -> InputCommitResult {
        guard let candidate = lastSuggestion?.prefixCandidates[inputControllerSafe: index],
              candidate.rawRange != compositionBuffer.rawRange else {
            return .noAction
        }
        guard compositionBuffer.apply(candidate) else {
            return .noAction
        }
        let isFullyResolvedAfterApply = compositionBuffer.isFullyResolved
        publishLocalSuggestion(client: client)
        if isFullyResolvedAfterApply {
            refreshResolvedCompositionContinuations(client: client)
        } else {
            refreshSuggestion(client: client)
        }
        if commitIfFullyResolved, isFullyResolvedAfterApply {
            return .commit(compositionBuffer.commitText)
        }
        return .noAction
    }

    private func insert(_ text: String, client: InputControllerClient?) {
        inputClientCompositionWriter.insertText(
            text,
            client: client,
            state: writeState(),
            reason: "commit"
        )
    }

    private func insertDirectPassthroughText(_ text: String, client: InputControllerClient?) -> Bool {
        guard let lifecycleClient = client ?? host?.currentClient else {
            return false
        }
        aiAcceptedFeedbackTracker.cancel(reason: "idle_passthrough")
        let state = writeState(hasActiveComposition: false)
        _ = finishCompositionLifecycle(reason: .reset, client: nil, commitPolicy: .none)
        inputClientCompositionWriter.insertText(
            text,
            client: lifecycleClient,
            state: state,
            reason: "idle_passthrough",
            clearsOwnedMarkedText: false
        )
        return true
    }

    private func recordTypingCommit(
        _ text: String,
        client: InputControllerClient?,
        acceptedAIRecommendation: AIRecommendationCandidate? = nil,
        acceptID: UUID? = nil
    ) {
        let appBundleID = appBundleIdentifier(client: client)
        let commitKind = acceptedAIRecommendation == nil ? typingCommitKind(for: text) : .ai
        let candidateSource = acceptedAIRecommendation
            .map { "ai:\($0.provider)" }
            ?? typingCandidateSource(for: text)
        if commitKind == .ai {
            if TextProtection.requiresNoCorrection("knowtype", appBundleID: appBundleID) {
                aiDiagnosticSink.record(
                    AIRecommendationDiagnosticEvent(
                        stage: .acceptedLearningSkippedSecret,
                        reason: "protected_app_context"
                    )
                )
            } else {
                recordAcceptedAICommit(
                    text,
                    appBundleID: appBundleID,
                    acceptedAIRecommendation: acceptedAIRecommendation,
                    candidateSource: candidateSource,
                    acceptID: acceptID
                )
            }
        } else {
            aiAcceptedFeedbackTracker.observeVerifiedReplacementCommit(text, client: client)
        }
        guard !TextProtection.requiresNoCorrection(text, appBundleID: appBundleID),
              !TextProtection.requiresNoCorrection(rawBuffer, appBundleID: appBundleID) else {
            return
        }
        recordLexicalCommit(text)
        guard let aiContextEventRecorder,
              canRequestAIRecommendations,
              runtimePreferences.cloudContinuationEnabled,
              !text.isEmpty else {
            return
        }
        let event = AITypingEvent(
            appBundleID: appBundleIdentifier(client: client),
            appName: appBundleIdentifier(client: client),
            rawInput: rawBuffer.isEmpty ? nil : rawBuffer,
            committedText: text,
            commitKind: commitKind,
            candidateSource: candidateSource,
            deleteCountBeforeCommit: deleteCountBeforeCommit
        )
        Task.detached(priority: .utility) { [aiContextEventRecorder] in
            await aiContextEventRecorder.record(event)
        }
    }

    private func recordAcceptedAICommit(
        _ text: String,
        appBundleID: String?,
        acceptedAIRecommendation: AIRecommendationCandidate?,
        candidateSource: String,
        acceptID: UUID?
    ) {
        guard let aiAcceptedLearningRecorder,
              let candidate = acceptedAIRecommendation,
              candidate.displayText == text else {
            return
        }
        let lockedPrefix = candidate.prefixText.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = AIAcceptedLearningRecord(
            acceptID: acceptID,
            schemaID: conversionEngine.activeSchemaID,
            appBundleID: appBundleID,
            rawInput: rawBuffer.isEmpty ? nil : rawBuffer,
            lockedPrefix: lockedPrefix.isEmpty ? nil : lockedPrefix,
            acceptedText: text,
            provider: candidate.provider,
            contextVersion: candidate.contextVersion,
            candidateSource: candidateSource
        )
        Task.detached(priority: .utility) { [aiAcceptedLearningRecorder] in
            await aiAcceptedLearningRecorder.recordAcceptedAI(record)
        }
    }

    private func prepareAcceptedFeedbackTracking(
        text: String,
        client: InputControllerClient?,
        acceptedAIRecommendation: AIRecommendationCandidate?
    ) -> UUID? {
        guard let candidate = acceptedAIRecommendation,
              candidate.displayText == text else {
            return nil
        }
        let appBundleID = appBundleIdentifier(client: client)
        guard !TextProtection.requiresNoCorrection("knowtype", appBundleID: appBundleID) else {
            aiDiagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .acceptedFeedbackTrackingCancelled,
                    reason: "protected_app_context"
                )
            )
            return nil
        }
        let acceptID = UUID()
        let trackingTarget = acceptedFeedbackTrackingTarget(
            text: text,
            acceptedAIRecommendation: candidate
        )
        _ = aiAcceptedFeedbackTracker.armAcceptedSpan(
            acceptID: acceptID,
            acceptedText: text,
            trackingText: trackingTarget.text,
            trackingOffsetUTF16: trackingTarget.offsetUTF16,
            schemaID: conversionEngine.activeSchemaID,
            appBundleID: appBundleID,
            provider: candidate.provider,
            contextVersion: candidate.contextVersion,
            client: client
        )
        return acceptID
    }

    private func acceptedFeedbackTrackingTarget(
        text: String,
        acceptedAIRecommendation candidate: AIRecommendationCandidate
    ) -> (text: String, offsetUTF16: Int) {
        let prefix = candidate.prefixText
        guard candidate.continuationText != nil,
              !prefix.isEmpty,
              text.hasPrefix(prefix) else {
            return (text, 0)
        }
        let prefixLength = (prefix as NSString).length
        guard prefixLength < (text as NSString).length else {
            return (text, 0)
        }
        let generatedText = (text as NSString).substring(from: prefixLength)
        guard !generatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (text, 0)
        }
        return (generatedText, prefixLength)
    }

    private func recordLexicalCommit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        recentLexicalCommits.append(trimmed)
        if recentLexicalCommits.count > Self.maxRecentLexicalCommits {
            recentLexicalCommits.removeFirst(recentLexicalCommits.count - Self.maxRecentLexicalCommits)
        }
        publishRuntimeEvent(
            .compositionCommitted(
                text: trimmed,
                schemaID: conversionEngine.activeSchemaID,
                compositionID: compositionID
            )
        )
        scheduleLexicalProfileRefresh(reason: "commit")
    }

    private func scheduleLexicalProfileRefresh(reason: String) {
        lexicalProfileRuntime.scheduleRefresh(
            reason: reason,
            schemaID: conversionEngine.activeSchemaID,
            recentCommits: recentLexicalCommits,
            selectionHistory: recentLexicalSelections
        )
    }

    private func recordExternalDelete(client: InputControllerClient?) {
        guard let aiContextEventRecorder,
              canRequestAIRecommendations,
              runtimePreferences.cloudContinuationEnabled else {
            return
        }
        let appBundleID = appBundleIdentifier(client: client)
        let event = AITypingEvent(
            appBundleID: appBundleID,
            appName: appBundleID,
            rawInput: nil,
            committedText: nil,
            commitKind: .externalDelete,
            candidateSource: "external-delete",
            deleteCountBeforeCommit: 1
        )
        Task.detached(priority: .utility) { [aiContextEventRecorder] in
            await aiContextEventRecorder.record(event)
        }
    }

    private func typingCommitKind(for text: String) -> AITypingCommitKind {
        if text == rawBuffer {
            return .raw
        }
        if rawBuffer.isEmpty {
            return .symbol
        }
        return .traditional
    }

    private func typingCandidateSource(for text: String) -> String {
        if text == rawBuffer {
            return "raw"
        }
        if let selectedNativeCandidate {
            return selectedNativeCandidate.kind.analyticsSource
        }
        if let source = lastSuggestion?.prefixCandidates.first?.source {
            return source
        }
        return rawBuffer.isEmpty ? "symbol" : "traditional"
    }

    private func acceptedAIRecommendationCandidate(
        for action: InputAction,
        result: InputCommitResult
    ) -> AIRecommendationCandidate? {
        guard case .commit(let text) = result,
              case .ready(let candidate) = aiRecommendationState,
              candidate.displayText == text else {
            return nil
        }
        if action == .tab {
            return candidate
        }
        if case .optionNumber(1) = action {
            return candidate
        }
        if action == .space,
           let selectedNativeCandidate,
           case .aiRecommendation = selectedNativeCandidate.kind {
            return candidate
        }
        return nil
    }

    private func resetComposition(client: InputControllerClient? = nil) {
        _ = finishCompositionLifecycle(reason: .reset, client: client, commitPolicy: .none)
    }

    @discardableResult
    private func finishCompositionLifecycle(
        reason: CompositionLifecycleFinishReason,
        client: InputControllerClient?,
        commitPolicy: CompositionLifecycleCommitPolicy
    ) -> Bool {
        traceCompositionLifecycleFinish(reason: reason)
        let finishedCompositionID = compositionID
        hideCandidatePanel(reason: reason.panelVisibilityReason)

        let lifecycleClient = client ?? host?.currentClient
        let shouldClearOwnedMarkedText = reason.shouldClearMarkedTextWhenEndingWithoutCommit
            && hasActiveTextComposition()
        let commitText = lifecycleCommitText(for: commitPolicy)
        if let commitText,
           !commitText.isEmpty {
            recordTypingCommit(commitText, client: lifecycleClient)
            insert(commitText, client: lifecycleClient)
        } else if shouldClearOwnedMarkedText {
            inputClientCompositionWriter.clearOwnedMarkedTextIfNeeded(
                client: lifecycleClient,
                state: writeState()
            )
        }

        rawBuffer = ""
        conversionEngine.reset()
        compositionBuffer = CompositionBuffer()
        rawRevision += 1
        deleteCountBeforeCommit = 0
        resetAnchorState()
        invalidateSuggestion()
        inputClientCompositionWriter.finishLifecycle(
            shouldClearOwnedMarkedTextWhenEndingWithoutCommit: shouldClearOwnedMarkedText
        )
        publishRuntimeEvent(
            .compositionEnded(reason: reason.panelVisibilityReason, compositionID: finishedCompositionID)
        )
        return commitText?.isEmpty == false
    }

    private func lifecycleCommitText(for policy: CompositionLifecycleCommitPolicy) -> String? {
        switch policy {
        case .none:
            return nil
        case .commitRawIfNeeded:
            if compositionBuffer.hasResolvedSegments {
                return compositionBuffer.commitText
            }
            return rawBuffer.isEmpty ? nil : rawBuffer
        }
    }

    private func beginCompositionIfNeeded(client: InputControllerClient?) {
        if rawBuffer.isEmpty {
            if !didTraceFirstCompositionBegin {
                didTraceFirstCompositionBegin = true
                traceStartupEvent(
                    "first_composition_begin",
                    details: "bundle=\(appBundleIdentifier(client: client) ?? "<unknown>")"
                )
            }
            if !aiAcceptedFeedbackTracker.preserveForReplacementComposition(client: client) {
                aiAcceptedFeedbackTracker.cancel(reason: "new_composition")
            }
            reloadInputModeDefaultsIfNeeded(client: client)
            reloadRuntimePreferencesIfNeeded()
            reloadRuntimeLexiconEngineIfNeeded()
            compositionBuffer = CompositionBuffer()
            compositionID += 1
            publishRuntimeEvent(
                .compositionStarted(compositionID: compositionID, rawRevision: rawRevision)
            )
            anchorResolver.reset()
        }
    }

    private func reloadInputModeDefaultsIfNeeded(client: InputControllerClient?) {
        let now = Date()
        let appBundleID = appBundleIdentifier(client: client)
        let appBundleChanged = inputModeRuntime.appBundleID != appBundleID
        guard appBundleChanged || now.timeIntervalSince(lastInputModePreferenceReload) >= Self.preferenceReloadInterval else {
            return
        }
        lastInputModePreferenceReload = now
        inputModeRuntime.reloadIfChanged(
            preferences: inputModePreferenceStore.loadPreferences(),
            appBundleID: appBundleID
        )
    }

    @discardableResult
    private func reloadRuntimePreferencesIfNeeded() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastRuntimePreferenceReload) >= Self.preferenceReloadInterval else {
            return false
        }
        lastRuntimePreferenceReload = now
        let preferences = runtimePreferenceStore.loadPreferences()
        guard preferences != runtimePreferences else {
            return false
        }
        runtimePreferences = preferences
        sessionController = Self.polishOnlySessionController()
        invalidateSuggestion()
        return true
    }

    private func reloadRuntimeLexiconEngineIfNeeded() {
        // Rime is the only product conversion engine. Avoid rebuilding the
        // retired local lexicon on the IMK key path.
    }

    private func resetAnchorState() {
        compositionID += 1
        anchorResolver.reset()
    }

    private func invalidateSuggestion() {
        suggestionGeneration += 1
        lastSuggestion = nil
        lastSuggestionRawInput = nil
        selectedNativeCandidate = nil
        suggestionTask?.cancel()
        suggestionTask = nil
        taskSupervisor.cancel(.localCandidates)
        cancelActiveAIRecommendationForDiagnostics(
            compositionID: compositionID,
            rawLength: rawBuffer.count,
            reason: "composition_invalidated"
        )
        aiRecommendationGeneration += 1
        aiRecommendationTask?.cancel()
        aiRecommendationTask = nil
        taskSupervisor.cancel(.aiRecommendation)
        aiRecommendationState = .idle
    }

    private func cancelActiveAIRecommendationForDiagnostics(
        compositionID: Int?,
        rawLength: Int?,
        reason: String
    ) {
        guard let requestID = activeAIRecommendationRequestID else {
            return
        }
        recordAIDiagnostic(
            .cancelPrevious,
            requestID: requestID,
            compositionID: compositionID,
            rawLength: rawLength,
            reason: reason
        )
        activeAIRecommendationRequestID = nil
    }

    private func updateCandidatePanelImmediately(suggestion: SuggestionResponse?, client: InputControllerClient?) {
        panelUpdateGeneration += 1
        panelUpdateTask?.cancel()
        panelUpdateTask = nil
        taskSupervisor.cancel(.panelRender)
        guard canPublishCandidatePanel(suggestion: suggestion) else {
            hideCandidatePanel(reason: candidatePanelSuppressionReason(suggestion: suggestion))
            return
        }
        updateCandidatePanel(
            suggestion: suggestion,
            anchorResult: candidateAnchorResult(client: client),
            placementPreference: candidatePanelPlacementPreference(client: client),
            preeditDisplayText: candidatePanelPreeditDisplayText(client: client)
        )
    }

    private func updateCandidatePanel(suggestion: SuggestionResponse?, client: InputControllerClient?) {
        guard canPublishCandidatePanel(suggestion: suggestion) else {
            hideCandidatePanel(reason: candidatePanelSuppressionReason(suggestion: suggestion))
            return
        }
        guard enablesAsyncSuggestionRefresh else {
            updateCandidatePanel(
                suggestion: suggestion,
                anchorResult: candidateAnchorResult(client: client),
                placementPreference: candidatePanelPlacementPreference(client: client),
                preeditDisplayText: candidatePanelPreeditDisplayText(client: client)
            )
            return
        }
        scheduleCandidatePanelUpdate(suggestion: suggestion, client: client)
    }

    private func scheduleCandidatePanelUpdate(suggestion: SuggestionResponse?, client: InputControllerClient?) {
        panelUpdateGeneration += 1
        let generation = panelUpdateGeneration
        let rawInput = rawBuffer
        let currentCompositionID = compositionID
        let currentRawRevision = rawRevision
        panelUpdateTask?.cancel()
        taskSupervisor.cancel(.panelRender)
        let task = Task { @MainActor [weak self, client, suggestion] in
            await Task.yield()
            guard let self,
                  !Task.isCancelled,
                  self.panelUpdateGeneration == generation,
                  self.rawBuffer == rawInput,
                  self.rawRevision == currentRawRevision,
                  self.compositionID == currentCompositionID else {
                return
            }
            self.updateCandidatePanel(
                suggestion: suggestion,
                anchorResult: self.candidateAnchorResult(client: client),
                placementPreference: self.candidatePanelPlacementPreference(client: client),
                preeditDisplayText: self.candidatePanelPreeditDisplayText(client: client)
            )
        }
        panelUpdateTask = task
        taskSupervisor.replace(.panelRender, with: task)
    }

    private func updateCandidatePanel(
        suggestion: SuggestionResponse?,
        anchorResult: CandidateAnchorResult,
        placementPreference: CandidatePanelPlacementPreference,
        preeditDisplayText: String?
    ) {
        guard canPublishCandidatePanel(suggestion: suggestion) else {
            hideCandidatePanel(reason: candidatePanelSuppressionReason(suggestion: suggestion))
            return
        }
        let isDisplayable = anchorResult.source != .none
        let effectivePageSize = runtimePreferences.effectiveCandidatePageSize
        candidatePanelState.update(
            rawInput: rawBuffer,
            suggestion: suggestion,
            anchorRect: anchorResult.rect,
            anchorSource: anchorResult.source,
            isDisplayable: isDisplayable,
            pageSize: effectivePageSize,
            layoutMode: runtimePreferences.candidateLayoutMode,
            placementPreference: placementPreference,
            preeditDisplayText: preeditDisplayText,
            aiRecommendation: aiRecommendationState,
            preferredSelection: nativeHighlightedSelection(for: suggestion)
        )
        traceCandidatePanelUpdate(
            savedPageSize: runtimePreferences.candidatePageSize,
            effectivePageSize: effectivePageSize
        )
        selectedNativeCandidate = candidatePanelState.windowState.isVisible
            ? inputCandidateSelection(
                for: candidatePanelState.windowState.selection,
                in: candidatePanelState.windowState.viewModel
            )
            : nil
        traceFirstCandidatePanelMaterializationIfNeeded()
        candidatePanelPresenter.apply(
            currentCandidatePanelFrame(
                reason: candidatePanelState.windowState.isVisible ? .compositionActive : .layoutImpossible
            ),
            locale: locale
        )
    }

    private func traceFirstCandidatePanelMaterializationIfNeeded() {
        guard candidatePanelState.windowState.isVisible,
              !didTraceFirstCandidatePanelMaterialization else {
            return
        }
        didTraceFirstCandidatePanelMaterialization = true
        let rowCount = CandidatePanelRenderer(locale: locale)
            .render(
                candidatePanelState.windowState.viewModel,
                selected: candidatePanelState.windowState.selection,
                paging: candidatePanelState.windowState.paging
            )
            .rows
            .count
        traceStartupEvent(
            "first_candidate_panel_materialization",
            details: "anchorSource=\(candidatePanelState.windowState.anchorSource.rawValue) renderRows=\(rowCount)"
        )
    }

    private func nativeHighlightedSelection(for suggestion: SuggestionResponse?) -> CandidatePanelSelection? {
        guard conversionEngine.isNativeActive,
              let suggestion,
              !suggestion.prefixCandidates.isEmpty else {
            return nil
        }
        let highlightedIndex = conversionEngine.snapshot.highlightedIndex
        guard suggestion.prefixCandidates.indices.contains(highlightedIndex) else {
            return nil
        }
        let candidate = suggestion.prefixCandidates[highlightedIndex]
        guard let range = candidate.rawRange else {
            return .prefixCandidate(highlightedIndex)
        }
        return range == KnowTypeCore.TextRange(start: 0, length: rawBuffer.count)
            ? .fullCandidate(highlightedIndex)
            : .segmentCandidate(highlightedIndex)
    }

    private func hideCandidatePanel(reason: CandidatePanelVisibilityReason) {
        panelUpdateGeneration += 1
        delayedReanchorGeneration += 1
        panelUpdateTask?.cancel()
        panelUpdateTask = nil
        taskSupervisor.cancel(.panelRender)
        candidatePanelState.hide()
        selectedNativeCandidate = nil
        anchorResolver.reset()
        candidatePanelPresenter.hide(
            reason: reason,
            compositionID: compositionID,
            rawRevision: rawRevision,
            rawLength: rawBuffer.count
        )
    }

    private func canPublishCandidatePanel(suggestion: SuggestionResponse?) -> Bool {
        guard !rawBuffer.isEmpty else {
            return false
        }
        if suggestion != nil,
           let lastSuggestionRawInput,
           lastSuggestionRawInput != rawBuffer {
            return false
        }
        if conversionEngine.isNativeActive {
            return nativeSnapshotHasActiveInput(conversionEngine.snapshot) || !rawBuffer.isEmpty
        }
        return true
    }

    private func candidatePanelSuppressionReason(suggestion: SuggestionResponse?) -> CandidatePanelVisibilityReason {
        guard !rawBuffer.isEmpty else {
            return .rawEmpty
        }
        if suggestion != nil,
           let lastSuggestionRawInput,
           lastSuggestionRawInput != rawBuffer {
            return .staleUpdate
        }
        return .layoutImpossible
    }

    private func currentCandidatePanelFrame(reason: CandidatePanelVisibilityReason) -> CandidatePanelFrame {
        CandidatePanelFrame(
            compositionID: compositionID,
            rawRevision: rawRevision,
            rawLength: rawBuffer.count,
            panelModel: candidatePanelState,
            anchorSource: candidatePanelState.windowState.anchorSource,
            visibilityReason: reason
        )
    }

    private func traceCompositionLifecycleFinish(reason: CompositionLifecycleFinishReason) {
        guard ProcessInfo.processInfo.environment["KNOWTYPE_PANEL_DEBUG"] == "1" else {
            return
        }
        let message = "KnowType panel cleanup: reason=\(reason.rawValue)\n"
        if let data = message.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    private func traceCandidatePanelUpdate(savedPageSize: Int, effectivePageSize: Int) {
        guard ProcessInfo.processInfo.environment["KNOWTYPE_PANEL_DEBUG"] == "1" else {
            return
        }
        let windowState = candidatePanelState.windowState
        let rowCount = CandidatePanelRenderer(locale: locale)
            .render(
                windowState.viewModel,
                selected: windowState.selection,
                paging: windowState.paging
            )
            .rows
            .count
        fputs(
            "KnowType panel: layoutMode=\(windowState.layoutMode.rawValue) savedPageSize=\(savedPageSize) effectivePageSize=\(effectivePageSize) anchorSource=\(windowState.anchorSource.rawValue) visible=\(windowState.isVisible) renderRows=\(rowCount)\n",
            stderr
        )
    }

    private func handleNativePagingSymbol(_ text: String, client: InputControllerClient?) -> Bool {
        guard let navigation = Self.nativePagingSymbolNavigation(for: text) else {
            return false
        }
        return moveNativeCandidatePage(
            navigation,
            client: client,
            consumeOnlyWhenSnapshotChanges: true
        )
    }

    private static func nativePagingSymbolNavigation(for text: String) -> InputCandidateNavigation? {
        switch text {
        case "-", ",":
            return .pageUp
        case "=", ".":
            return .pageDown
        default:
            return nil
        }
    }

    private func moveNativeCandidatePage(
        _ navigation: InputCandidateNavigation,
        client: InputControllerClient?,
        consumeOnlyWhenSnapshotChanges: Bool = false
    ) -> Bool {
        guard conversionEngine.isNativeActive,
              !rawBuffer.isEmpty else {
            return false
        }
        let snapshotBeforePage = conversionEngine.snapshot
        let key: ConversionEngineKey
        switch navigation {
        case .pageUp:
            key = .pageUp
        case .pageDown:
            key = .pageDown
        case .up, .down, .left, .right:
            return false
        }
        let result = conversionEngine.process(key)
        guard result.handled else {
            return false
        }
        if consumeOnlyWhenSnapshotChanges,
           result.snapshot == snapshotBeforePage,
           result.commitText == nil {
            return false
        }
        publishLocalSuggestion(client: client)
        return true
    }

    private func moveCandidateSelection(_ navigation: InputCandidateNavigation) -> Bool {
        if conversionEngine.isNativeActive,
           !rawBuffer.isEmpty,
           conversionEngine.snapshot.hasComposition {
            if moveNativeCandidateSelection(navigation, client: host?.currentClient) {
                return true
            }
        }
        if moveNativeCandidatePage(navigation, client: host?.currentClient) {
            return true
        }
        if conversionEngine.isNativeActive,
           navigation == .pageDown || navigation == .pageUp {
            return false
        }
        let previousWindowState = candidatePanelState.windowState
        if candidatePanelState.moveSelection(navigation) {
            if conversionEngine.isNativeActive,
               candidatePanelState.windowState == previousWindowState,
               let pageNavigation = Self.nativeBoundaryPageNavigation(for: navigation),
               moveNativeCandidatePage(pageNavigation, client: host?.currentClient) {
                return true
            }
            selectedNativeCandidate = inputCandidateSelection(
                for: candidatePanelState.windowState.selection,
                in: candidatePanelState.windowState.viewModel
            )
            host?.updateCandidatePanel(state: candidatePanelState, locale: locale)
            return true
        }
        guard let pageNavigation = Self.nativeBoundaryPageNavigation(for: navigation) else {
            return false
        }
        return moveNativeCandidatePage(pageNavigation, client: host?.currentClient)
    }

    private func moveNativeCandidateSelection(
        _ navigation: InputCandidateNavigation,
        client: InputControllerClient?
    ) -> Bool {
        switch navigation {
        case .pageDown, .pageUp:
            return moveNativeCandidatePage(navigation, client: client)
        case .right, .down:
            return moveNativeCandidateHighlight(delta: 1, client: client)
        case .left, .up:
            return moveNativeCandidateHighlight(delta: -1, client: client)
        }
    }

    private func moveNativeCandidateHighlight(delta: Int, client: InputControllerClient?) -> Bool {
        let snapshot = conversionEngine.snapshot
        guard !snapshot.candidates.isEmpty else {
            return false
        }
        let currentIndex = min(max(snapshot.highlightedIndex, 0), snapshot.candidates.count - 1)
        let targetIndex = currentIndex + delta
        if snapshot.candidates.indices.contains(targetIndex) {
            let result = conversionEngine.process(.highlightCandidateOnCurrentPage(targetIndex))
            guard result.handled else {
                return false
            }
            refreshNativeHighlightPresentation(client: client)
            return true
        }

        if targetIndex >= snapshot.candidates.count {
            guard moveNativeCandidatePage(.pageDown, client: client) else {
                return true
            }
            let result = conversionEngine.process(.highlightCandidateOnCurrentPage(0))
            if result.handled {
                refreshNativeHighlightPresentation(client: client)
            }
            return true
        }

        guard moveNativeCandidatePage(.pageUp, client: client) else {
            return true
        }
        let previousPageSnapshot = conversionEngine.snapshot
        guard let lastIndex = previousPageSnapshot.candidates.indices.last else {
            return true
        }
        let result = conversionEngine.process(.highlightCandidateOnCurrentPage(lastIndex))
        if result.handled {
            refreshNativeHighlightPresentation(client: client)
        }
        return true
    }

    private static func nativeBoundaryPageNavigation(
        for navigation: InputCandidateNavigation
    ) -> InputCandidateNavigation? {
        switch navigation {
        case .right, .down:
            return .pageDown
        case .left, .up:
            return .pageUp
        case .pageDown, .pageUp:
            return nil
        }
    }

    private func candidateAnchorResult(client: InputControllerClient?) -> CandidateAnchorResult {
        anchorResolver.resolve(
            client: client,
            context: CandidateAnchorContext(
                compositionID: compositionID,
                appBundleID: appBundleIdentifier(client: client)
            )
        )
    }

    private func selectNativeCandidate(matching text: String?) {
        guard let text,
              let selection = displayedNativeCandidates.first(where: { $0.text == text }) else {
            selectedNativeCandidate = nil
            return
        }
        selectedNativeCandidate = selection
    }

    private func inputCandidateSelection(
        for selection: CandidatePanelSelection?,
        in viewModel: CandidatePanelViewModel
    ) -> InputCandidateSelection? {
        guard let selection else {
            return nil
        }

        switch selection {
        case .rawInput:
            guard !viewModel.rawInput.isEmpty else {
                return nil
            }
            return InputCandidateSelection(text: viewModel.rawInput, kind: .rawInput)
        case .prefixCandidate(let index):
            guard viewModel.prefixCandidates.indices.contains(index) else {
                return nil
            }
            let candidate = viewModel.prefixCandidates[index]
            return InputCandidateSelection(
                text: candidate.text,
                kind: .prefixCandidate(index: index),
                nativeCandidateIndex: ConversionCandidateSource.nativeIndex(from: candidate.source)
            )
        case .fullCandidate(let index):
            guard viewModel.prefixCandidates.indices.contains(index) else {
                return nil
            }
            let candidate = viewModel.prefixCandidates[index]
            return InputCandidateSelection(
                text: candidate.text,
                kind: .fullCandidate(index: index),
                nativeCandidateIndex: ConversionCandidateSource.nativeIndex(from: candidate.source)
            )
        case .segmentCandidate(let index):
            guard viewModel.prefixCandidates.indices.contains(index) else {
                return nil
            }
            let candidate = viewModel.prefixCandidates[index]
            return InputCandidateSelection(
                text: candidate.text,
                kind: .segmentCandidate(index: index),
                nativeCandidateIndex: ConversionCandidateSource.nativeIndex(from: candidate.source)
            )
        case .continuationCandidate(let index):
            guard viewModel.continuationCandidates.indices.contains(index) else {
                return nil
            }
            return InputCandidateSelection(
                text: viewModel.continuationCandidates[index].text,
                kind: .continuationCandidate(index: index)
            )
        case .aiRecommendation:
            guard let text = viewModel.aiRecommendation.displayText,
                  !text.isEmpty else {
                return nil
            }
            return InputCandidateSelection(
                text: text,
                kind: .aiRecommendation
            )
        }
    }

    private func sessionSelection(from selection: InputCandidateSelection?) -> InputSessionCandidateSelection? {
        guard let selection else {
            return nil
        }
        switch selection.kind {
        case .rawInput:
            return .rawInput
        case .prefixCandidate(let index), .fullCandidate(let index):
            return .prefixCandidate(index: index)
        case .segmentCandidate:
            return nil
        case .aiRecommendation:
            return nil
        case .continuationCandidate(let index):
            return .continuationCandidate(index: index)
        }
    }

    private func refreshComposition(client: InputControllerClient?) {
        let didWriteMarkedText = inputClientCompositionWriter.refreshComposition(
            client: client,
            state: writeState(),
            markedDisplayText: nativeMarkedText() ?? compositionBuffer.displayText
        )
        guard didWriteMarkedText,
              let client else {
            return
        }
        scheduleDelayedCandidateReanchor(
            client: client,
            rawInput: rawBuffer,
            compositionID: compositionID
        )
    }

    private func nativeMarkedText() -> String? {
        guard conversionEngine.isNativeActive else {
            return nil
        }
        let snapshot = conversionEngine.snapshot
        guard snapshot.hasComposition else {
            return nil
        }
        if !snapshot.preedit.isEmpty {
            return snapshot.preedit
        }
        return snapshot.rawInput.isEmpty ? nil : snapshot.rawInput
    }

    private func candidatePanelPreeditDisplayText(client: InputControllerClient?) -> String? {
        inputClientCompositionWriter.candidatePanelPreeditDisplayText(
            client: client,
            state: writeState(),
            markedDisplayText: nativeMarkedText() ?? compositionBuffer.displayText
        )
    }

    private func scheduleDelayedCandidateReanchor(
        client: InputControllerClient,
        rawInput: String,
        compositionID: Int
    ) {
        delayedReanchorGeneration += 1
        let generation = delayedReanchorGeneration
        host?.scheduleDelayedReanchor { [weak self, client] in
            guard let self,
                  self.delayedReanchorGeneration == generation,
                  CandidateAnchorRefreshPolicy.shouldApplyDelayedAnchor(
                      snapshotRawInput: rawInput,
                      currentRawInput: self.rawBuffer,
                      snapshotCompositionID: compositionID,
                      currentCompositionID: self.compositionID,
                      hasActiveComposition: !self.rawBuffer.isEmpty
                  ) else {
                return
            }
            self.updateCandidatePanel(
                suggestion: self.lastSuggestion,
                anchorResult: self.candidateAnchorResult(client: client),
                placementPreference: self.candidatePanelPlacementPreference(client: client),
                preeditDisplayText: self.candidatePanelPreeditDisplayText(client: client)
            )
        }
    }

    private static let textOnlyKeyCode = -1
    private static let maxUserSelectionHistory = 64
    private static let maxRecentLexicalCommits = 32
    private static let leadingFullCandidateCount = 5
    private static let preferenceReloadInterval: TimeInterval = 1

    private func traceStartupEvent(_ event: String, details: String = "") {
        guard ProcessInfo.processInfo.environment["KNOWTYPE_STARTUP_DEBUG"] == "1" else {
            return
        }
        let elapsedMs = Date().timeIntervalSince(startupDebugStartedAt) * 1_000
        let formattedElapsed = String(format: "%.1f", elapsedMs)
        let suffix = details.isEmpty ? "" : " \(details)"
        fputs("KnowType startup: event=\(event) elapsedMs=\(formattedElapsed)\(suffix)\n", stderr)
    }

    private static func isDirectPassthroughDigitText(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 48 && scalar.value <= 57
        }
    }
}

private enum CompositionLifecycleFinishReason: String {
    case commit
    case deactivate
    case close
    case reset
    case nativeEnded = "native_ended"

    var shouldClearMarkedTextWhenEndingWithoutCommit: Bool {
        true
    }

    var panelVisibilityReason: CandidatePanelVisibilityReason {
        switch self {
        case .commit:
            return .compositionEnded
        case .deactivate:
            return .deactivate
        case .close:
            return .close
        case .reset:
            return .reset
        case .nativeEnded:
            return .nativeEnded
        }
    }
}

private enum CompositionLifecycleCommitPolicy {
    case none
    case commitRawIfNeeded
}

final class LexicalProfileRefreshGate: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0

    func next() -> Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        generation += 1
        return generation
    }

    func isCurrent(_ candidate: Int) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return generation == candidate
    }

}

private extension Collection {
    subscript(inputControllerSafe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
