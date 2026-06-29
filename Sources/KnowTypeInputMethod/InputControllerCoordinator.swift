import CoreGraphics
import Foundation
import KnowTypeAI
import KnowTypeCore
import KnowTypeProviders

final class InputControllerCoordinator: @unchecked Sendable {
    private var sessionController: InputSessionController
    private let canRequestAIRecommendations: Bool
    private var conversionEngine: any KnowTypeConversionEngine
    private let keyMapper = InputKeyCommandMapper()
    private let symbolTransformer = InputSymbolTransformer()
    private let candidateListBuilder = InputCandidateListBuilder()
    private let anchorResolver: CandidateAnchorResolver
    private weak var host: InputControllerHost?
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
    private let nativeCandidateNavigationRuntime = InputNativeCandidateNavigationRuntime()
    private let selectionHistoryRuntime: InputSelectionHistoryRuntime
    private let enablesAsyncSuggestionRefresh: Bool
    private let asyncSuggestionDelayNanoseconds: UInt64
    private var suggestionGeneration = 0
    private let aiAcceptedFeedbackProvider: (any AIAcceptedFeedbackSnapshotProviding)?
    private let aiRecommendationRuntime: InputAIRecommendationRuntime
    private let aiAcceptanceRuntime: InputAIAcceptanceRuntime
    private var aiRecommendationState: AIRecommendationState = .idle
    private var deleteCountBeforeCommit = 0
    private var recentLexicalCommits: [String] = []
    private let lexicalProfileRuntime: LexicalProfileRuntime
    private let inputClientCompositionWriter: InputClientCompositionWriter
    private let taskSupervisor = InputTaskSupervisor()
    private let candidatePanelPublicationRuntime: InputCandidatePanelPublicationRuntime
    private let latencyTracer = InputLatencyTracer()
    private var lastInputModePreferenceReload = Date.distantPast
    private var lastRuntimePreferenceReload = Date.distantPast
    private let startupDebugStartedAt: Date
    private var didTraceFirstCompositionBegin = false

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
        let startupDebugStartedAt = Date()
        let inputModePreferences = inputModePreferenceStore.loadPreferences()
        let runtimePreferences = initialRuntimePreferences ?? runtimePreferenceStore.loadPreferences()
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
        self.selectionHistoryRuntime = InputSelectionHistoryRuntime(
            persistence: userSelectionHistoryPersistence,
            maxEntries: Self.maxUserSelectionHistory
        )
        self.aiAcceptedFeedbackProvider = aiAcceptedFeedback
        self.aiRecommendationRuntime = InputAIRecommendationRuntime(
            provider: aiRecommendationProvider,
            providerAvailability: aiRecommendationProviderAvailability,
            hasEagerProvider: provider != nil,
            diagnosticSink: aiDiagnosticSink
        )
        self.aiAcceptanceRuntime = InputAIAcceptanceRuntime(
            contextEventRecorder: aiContextEventRecorder,
            acceptedLearningRecorder: aiAcceptedLearning,
            acceptedFeedbackRecorder: aiAcceptedFeedback,
            diagnosticSink: aiDiagnosticSink,
            canRequestAIRecommendations: self.canRequestAIRecommendations,
            runtimePreferences: runtimePreferences
        )
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
        self.startupDebugStartedAt = startupDebugStartedAt
        self.host = host
        self.candidatePanelPublicationRuntime = InputCandidatePanelPublicationRuntime(
            host: host,
            taskSupervisor: taskSupervisor,
            traceStartupEvent: { event, details in
                Self.traceStartupEvent(event: event, details: details, startedAt: startupDebugStartedAt)
            }
        )
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
        nativeCandidateNavigationRuntime.cacheDisplayedCandidates(selections)
        return selections.map(\.text)
    }

    func candidateSelectionChanged(_ text: String?) {
        nativeCandidateNavigationRuntime.selectDisplayedCandidate(matching: text)
        if let selectedNativeCandidate = nativeCandidateNavigationRuntime.selectedCandidate {
            _ = applyNativeNavigationResult(
                nativeCandidateNavigationRuntime.highlightSelectionIfNeeded(
                    selectedNativeCandidate,
                    engine: &conversionEngine
                ),
                client: host?.currentClient
            )
        }
    }

    func candidateSelected(_ text: String?, client: InputControllerClient?) {
        nativeCandidateNavigationRuntime.selectDisplayedCandidate(matching: text)
        if let selectedNativeCandidate = nativeCandidateNavigationRuntime.selectedCandidate,
           commitNativeSelectionIfNeeded(selectedNativeCandidate, client: client) {
            return
        }
        commit(action: .space, client: client)
    }

    func hoverCandidatePanelSelection(_ selection: CandidatePanelSelection) {
        guard let result = candidatePanelPublicationRuntime.selectVisibleRow(selection) else {
            return
        }
        let selectedNativeCandidate = nativeCandidateNavigationRuntime.updateSelectedCandidate(
            for: result.selection,
            in: result.state.windowState.viewModel
        )
        if let selectedNativeCandidate,
           highlightNativeSelectionIfNeeded(selectedNativeCandidate, client: host?.currentClient) {
            return
        }
        candidatePanelPublicationRuntime.applyCurrentFrame(
            reason: .compositionActive,
            compositionID: compositionID,
            rawRevision: rawRevision,
            rawLength: rawBuffer.count,
            locale: locale
        )
    }

    func commitCandidatePanelSelection(_ selection: CandidatePanelSelection, client: InputControllerClient?) {
        guard let publicationResult = candidatePanelPublicationRuntime.selectVisibleRow(selection),
              let inputSelection = nativeCandidateNavigationRuntime.inputCandidateSelection(
                  for: publicationResult.selection,
                  in: publicationResult.state.windowState.viewModel
              ) else {
            return
        }
        nativeCandidateNavigationRuntime.setSelectedCandidate(inputSelection)
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
        aiAcceptanceRuntime.cancelFeedback(reason: "deactivate")
        _ = finishCompositionLifecycle(reason: .deactivate, client: client, commitPolicy: .commitRawIfNeeded)
    }

    func inputControllerWillClose() {
        flushUserSelectionHistory()
        aiRecommendationState = aiRecommendationRuntime.reset(
            compositionID: compositionID,
            rawLength: rawBuffer.count,
            reason: "input_controller_will_close"
        )
        aiAcceptanceRuntime.cancelFeedback(reason: "input_controller_will_close")
        lexicalProfileRuntime.cancelRefresh()
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
                _ = aiAcceptanceRuntime.observeDeleteBackward(client: client)
                aiAcceptanceRuntime.recordExternalDelete(appBundleID: appBundleIdentifier(client: client))
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
            let panelState = candidatePanelPublicationRuntime.state
            if panelState.windowState.isVisible {
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
                   panelState.windowState.selection == .rawInput,
                   !rawBuffer.isEmpty {
                    return applyCommitResult(.commit(rawBuffer), client: client)
                }
                if let selectionResult = candidatePanelPublicationRuntime.selectVisiblePrefixCandidate(shortcutNumber: number),
                   let inputSelection = nativeCandidateNavigationRuntime.inputCandidateSelection(
                       for: selectionResult.selection,
                       in: selectionResult.state.windowState.viewModel
                   ) {
                    nativeCandidateNavigationRuntime.setSelectedCandidate(inputSelection)
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
        guard !aiRecommendationRuntime.hasKnownProvider,
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
               InputNativeCandidateNavigationRuntime.isNativeSelectablePrefixOrFull(selection) {
                guard let conversionResult = nativeCandidateNavigationRuntime.selectNativeCandidateForCommit(
                    selection,
                    engine: &conversionEngine
                ) else {
                    return .noAction
                }
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
        applyNativeNavigationResult(
            nativeCandidateNavigationRuntime.selectCandidateOnCurrentPage(
                index,
                engine: &conversionEngine
            ),
            client: client
        )
    }

    private func commitNativeSelectionIfNeeded(
        _ selection: InputCandidateSelection,
        client: InputControllerClient?
    ) -> Bool {
        applyNativeNavigationResult(
            nativeCandidateNavigationRuntime.selectNativeCandidateIfNeeded(
                selection,
                engine: &conversionEngine
            ),
            client: client
        )
    }

    private func highlightNativeSelectionIfNeeded(
        _ selection: InputCandidateSelection,
        client: InputControllerClient?
    ) -> Bool {
        applyNativeNavigationResult(
            nativeCandidateNavigationRuntime.highlightSelectionIfNeeded(
                selection,
                engine: &conversionEngine
            ),
            client: client
        )
    }

    private func shouldSelectNativeCandidateBeforeSpace(_ selection: InputCandidateSelection) -> Bool {
        nativeCandidateNavigationRuntime.shouldSelectBeforeSpace(selection, engine: conversionEngine)
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
            selectionHistory: selectionHistoryRuntime.recentSelectionHistory
        )
    }

    static func confirmedLockedPrefixText(for suggestion: SuggestionResponse) -> String? {
        let text = suggestion.lockedPrefix?.text
        return text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? text : nil
    }

    private func scheduleAIRecommendation(for suggestion: SuggestionResponse, client: InputControllerClient?) {
        let currentAppBundleID = appBundleIdentifier(client: client)
        let lockedPrefixText = Self.confirmedLockedPrefixText(for: suggestion)
        let context = InputAIRecommendationRuntimeContext(
            rawInput: rawBuffer,
            hasResolvedSegments: compositionBuffer.hasResolvedSegments,
            isFullyResolved: compositionBuffer.isFullyResolved,
            lockedPrefix: lockedPrefixText,
            cloudContinuationEnabled: runtimePreferences.cloudContinuationEnabled,
            canRequestAIRecommendations: canRequestAIRecommendations,
            appBundleID: currentAppBundleID,
            locale: locale,
            compositionID: compositionID,
            rawRevision: rawRevision,
            lexicalContext: lexicalContextSnapshot(for: suggestion),
            feedbackContext: aiAcceptedFeedbackProvider?.snapshot(schemaID: conversionEngine.activeSchemaID)
        )
        aiRecommendationState = aiRecommendationRuntime.schedule(
            context: context,
            currentSnapshot: { [weak self] in
                guard let self else {
                    return nil
                }
                return InputAIRecommendationRuntimeCompositionSnapshot(
                    compositionID: self.compositionID,
                    rawRevision: self.rawRevision,
                    rawInput: self.rawBuffer
                )
            },
            onStateChange: { [weak self] state in
                guard let self else {
                    return
                }
                self.aiRecommendationState = state
                self.clearNoProviderFallbackContinuationsIfProviderIsKnown()
                self.updateCandidatePanel(suggestion: self.lastSuggestion, client: self.host?.currentClient)
            }
        )
        updateCandidatePanel(suggestion: suggestion, client: client)
    }

    private func clearNoProviderFallbackContinuationsIfProviderIsKnown() {
        guard aiRecommendationRuntime.hasKnownProvider,
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
            if let selectedNativeCandidate = nativeCandidateNavigationRuntime.selectedCandidate,
               shouldCommitSelectedNonNativeCandidateBeforeNativeSpace(selectedNativeCandidate) {
                let result = commitResult(for: action, client: client)
                learnSelectedPrefix(action: action, result: result, client: client)
                return applyCommitResult(
                    result,
                    client: client,
                    acceptedAIRecommendation: acceptedAIRecommendationCandidate(for: action, result: result)
                )
            }
            if let selectedNativeCandidate = nativeCandidateNavigationRuntime.selectedCandidate,
               shouldSelectNativeCandidateBeforeSpace(selectedNativeCandidate) {
                if applyNativeNavigationResult(
                    nativeCandidateNavigationRuntime.selectNativeCandidateIfNeeded(
                        selectedNativeCandidate,
                        engine: &conversionEngine
                    ),
                    client: client
                ) {
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
            let acceptID = aiAcceptanceRuntime.prepareAcceptedFeedbackTracking(
                context: InputAIAcceptanceFeedbackContext(
                    text: text,
                    schemaID: conversionEngine.activeSchemaID,
                    appBundleID: appBundleIdentifier(client: client),
                    acceptedAIRecommendation: acceptedAIRecommendation,
                    client: client
                )
            )
            recordCommitSideEffects(
                text,
                client: client,
                acceptedAIRecommendation: acceptedAIRecommendation,
                acceptID: acceptID
            )
            insert(text, client: client)
            if acceptID != nil {
                host?.scheduleDelayedReanchor { [weak self, client] in
                    self?.aiAcceptanceRuntime.verifyPostInsertCaret(client: client)
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
                recordCommitSideEffects(commitText, client: client)
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

    @discardableResult
    private func applyNativeNavigationResult(
        _ result: InputNativeCandidateNavigationResult,
        client: InputControllerClient?
    ) -> Bool {
        for effect in result.effects {
            switch effect {
            case .publishLocalSuggestion:
                publishLocalSuggestion(client: client)
            case .refreshNativeHighlightPresentation:
                refreshNativeHighlightPresentation(client: client)
            }
        }
        guard let conversionResult = result.conversionResult else {
            return result.handled
        }
        learnNativeCommitIfFinal(conversionResult, client: client)
        let didHandleConversion = handleNativeConversionResult(conversionResult, client: client)
        return didHandleConversion || (result.consumesUnhandledConversionResult && result.handled)
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
        if let selectedNativeCandidate = nativeCandidateNavigationRuntime.selectedCandidate {
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

        switch candidatePanelPublicationRuntime.state.windowState.selection {
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
        guard let event = selectionHistoryRuntime.recordSelection(
            text,
            rawInput: rawBuffer,
            appBundleID: appBundleIdentifier(client: client),
            schemaID: conversionEngine.activeSchemaID,
            compositionID: compositionID
        ) else {
            return
        }
        publishRuntimeEvent(event)
        scheduleLexicalProfileRefresh(reason: "selection")
    }

    private func publishRuntimeEvent(_ event: InputRuntimeEvent) {
        Task.detached(priority: .utility) { [inputEventBus] in
            await inputEventBus.publish(event)
        }
    }

    private func flushUserSelectionHistory() {
        selectionHistoryRuntime.flush()
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
        let selectedNativeCandidate = nativeCandidateNavigationRuntime.selectedCandidate
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
           InputNativeCandidateNavigationRuntime.isNativeSelectablePrefixOrFull(selectedNativeCandidate),
           nativeCandidateNavigationRuntime.nativeCandidateIndex(
               for: selectedNativeCandidate,
               engine: conversionEngine
           ) == nil {
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
           !candidatePanelPublicationRuntime.state.windowState.isVisible {
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
        aiAcceptanceRuntime.cancelFeedback(reason: "idle_passthrough")
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

    private func recordCommitSideEffects(
        _ text: String,
        client: InputControllerClient?,
        acceptedAIRecommendation: AIRecommendationCandidate? = nil,
        acceptID: UUID? = nil
    ) {
        let effects = aiAcceptanceRuntime.recordCommit(
            context: InputAIAcceptanceCommitContext(
                text: text,
                rawInput: rawBuffer,
                schemaID: conversionEngine.activeSchemaID,
                appBundleID: appBundleIdentifier(client: client),
                acceptedAIRecommendation: acceptedAIRecommendation,
                acceptID: acceptID,
                selectedNativeCandidateSource: nativeCandidateNavigationRuntime.selectedCandidate?.kind.analyticsSource,
                prefixCandidateSource: lastSuggestion?.prefixCandidates.first?.source,
                deleteCountBeforeCommit: deleteCountBeforeCommit,
                client: client
            )
        )
        if effects.shouldRecordLexicalCommit {
            recordLexicalCommit(text)
        }
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
            selectionHistory: selectionHistoryRuntime.recentSelectionHistory
        )
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
           let selectedNativeCandidate = nativeCandidateNavigationRuntime.selectedCandidate,
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
            recordCommitSideEffects(commitText, client: lifecycleClient)
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
            if !aiAcceptanceRuntime.preserveFeedbackForReplacementComposition(client: client) {
                aiAcceptanceRuntime.cancelFeedback(reason: "new_composition")
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
        aiAcceptanceRuntime.updateRuntimePreferences(preferences)
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
        nativeCandidateNavigationRuntime.clearSelectedCandidate()
        suggestionTask?.cancel()
        suggestionTask = nil
        taskSupervisor.cancel(.localCandidates)
        aiRecommendationState = aiRecommendationRuntime.reset(
            compositionID: compositionID,
            rawLength: rawBuffer.count,
            reason: "composition_invalidated"
        )
    }

    private func updateCandidatePanelImmediately(suggestion: SuggestionResponse?, client: InputControllerClient?) {
        let snapshot = candidatePanelPublicationSnapshot(suggestion: suggestion)
        let result = candidatePanelPublicationRuntime.publishImmediately(
            snapshot: snapshot,
            request: { self.candidatePanelPublicationRequest(suggestion: suggestion, client: client) },
            locale: locale
        )
        applyCandidatePanelPublicationResult(result)
    }

    private func updateCandidatePanel(suggestion: SuggestionResponse?, client: InputControllerClient?) {
        let snapshot = candidatePanelPublicationSnapshot(suggestion: suggestion)
        if let result = candidatePanelPublicationRuntime.publish(
            snapshot: snapshot,
            enablesAsyncRefresh: enablesAsyncSuggestionRefresh,
            request: { [weak self, client, suggestion] in
                guard let self else {
                    return nil
                }
                return self.candidatePanelPublicationRequest(suggestion: suggestion, client: client)
            },
            currentSnapshot: { [weak self, suggestion] in
                guard let self else {
                    return snapshot
                }
                return self.candidatePanelPublicationSnapshot(suggestion: suggestion)
            },
            locale: locale,
            onPublication: { [weak self] result in
                self?.applyCandidatePanelPublicationResult(result)
            }
        ) {
            applyCandidatePanelPublicationResult(result)
        }
    }

    private func candidatePanelPublicationSnapshot(
        suggestion: SuggestionResponse?
    ) -> InputCandidatePanelPublicationSnapshot {
        InputCandidatePanelPublicationSnapshot(
            rawInput: rawBuffer,
            compositionID: compositionID,
            rawRevision: rawRevision,
            suggestion: suggestion,
            lastSuggestionRawInput: lastSuggestionRawInput,
            nativeIsActive: conversionEngine.isNativeActive,
            nativeHasActiveInput: nativeSnapshotHasActiveInput(conversionEngine.snapshot)
        )
    }

    private func candidatePanelPublicationRequest(
        suggestion: SuggestionResponse?,
        client: InputControllerClient?
    ) -> InputCandidatePanelPublicationRequest {
        InputCandidatePanelPublicationRequest(
            snapshot: candidatePanelPublicationSnapshot(suggestion: suggestion),
            anchorResult: candidateAnchorResult(client: client),
            placementPreference: candidatePanelPlacementPreference(client: client),
            preeditDisplayText: candidatePanelPreeditDisplayText(client: client),
            aiRecommendation: aiRecommendationState,
            savedPageSize: runtimePreferences.candidatePageSize,
            effectivePageSize: runtimePreferences.effectiveCandidatePageSize,
            layoutMode: runtimePreferences.candidateLayoutMode,
            preferredSelection: nativeCandidateNavigationRuntime.nativeHighlightedSelection(
                suggestion: suggestion,
                rawInput: rawBuffer,
                engine: conversionEngine
            )
        )
    }

    private func hideCandidatePanel(reason: CandidatePanelVisibilityReason) {
        let result = candidatePanelPublicationRuntime.hide(
            reason: reason,
            compositionID: compositionID,
            rawRevision: rawRevision,
            rawLength: rawBuffer.count
        )
        applyCandidatePanelPublicationResult(result)
    }

    private func applyCandidatePanelPublicationResult(_ result: InputCandidatePanelPublicationResult) {
        if result.isVisible {
            nativeCandidateNavigationRuntime.updateSelectedCandidate(
                for: result.selection,
                in: result.state.windowState.viewModel
            )
        } else {
            nativeCandidateNavigationRuntime.clearSelectedCandidate()
        }
        if result.didHide {
            anchorResolver.reset()
        }
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

    private func handleNativePagingSymbol(_ text: String, client: InputControllerClient?) -> Bool {
        applyNativeNavigationResult(
            nativeCandidateNavigationRuntime.moveNativeCandidatePage(
                forPagingSymbol: text,
                rawInput: rawBuffer,
                engine: &conversionEngine
            ),
            client: client
        )
    }

    private func moveNativeCandidatePage(
        _ navigation: InputCandidateNavigation,
        client: InputControllerClient?,
        consumeOnlyWhenSnapshotChanges: Bool = false
    ) -> Bool {
        applyNativeNavigationResult(
            nativeCandidateNavigationRuntime.moveNativeCandidatePage(
                navigation,
                rawInput: rawBuffer,
                engine: &conversionEngine,
                consumeOnlyWhenSnapshotChanges: consumeOnlyWhenSnapshotChanges
            ),
            client: client
        )
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
        let previousWindowState = candidatePanelPublicationRuntime.state.windowState
        if let result = candidatePanelPublicationRuntime.moveLocalSelection(navigation) {
            if conversionEngine.isNativeActive,
               result.state.windowState == previousWindowState,
               let pageNavigation = nativeCandidateNavigationRuntime.boundaryPageNavigation(for: navigation),
               moveNativeCandidatePage(pageNavigation, client: host?.currentClient) {
                return true
            }
            nativeCandidateNavigationRuntime.updateSelectedCandidate(
                for: result.selection,
                in: result.state.windowState.viewModel
            )
            candidatePanelPublicationRuntime.applyCurrentFrame(
                reason: .compositionActive,
                compositionID: compositionID,
                rawRevision: rawRevision,
                rawLength: rawBuffer.count,
                locale: locale
            )
            return true
        }
        guard let pageNavigation = nativeCandidateNavigationRuntime.boundaryPageNavigation(for: navigation) else {
            return false
        }
        return moveNativeCandidatePage(pageNavigation, client: host?.currentClient)
    }

    private func moveNativeCandidateSelection(
        _ navigation: InputCandidateNavigation,
        client: InputControllerClient?
    ) -> Bool {
        applyNativeNavigationResult(
            nativeCandidateNavigationRuntime.moveNativeCandidateSelection(
                navigation,
                rawInput: rawBuffer,
                engine: &conversionEngine
            ),
            client: client
        )
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
        candidatePanelPublicationRuntime.scheduleDelayedReanchor(
            rawInput: rawInput,
            compositionID: compositionID,
            currentSnapshot: { [weak self] in
                guard let self else {
                    return InputCandidatePanelReanchorSnapshot(
                        rawInput: "",
                        compositionID: compositionID,
                        hasActiveComposition: false
                    )
                }
                return InputCandidatePanelReanchorSnapshot(
                    rawInput: self.rawBuffer,
                    compositionID: self.compositionID,
                    hasActiveComposition: !self.rawBuffer.isEmpty
                )
            },
            publish: { [weak self, client] in
                guard let self else {
                    return
                }
                self.updateCandidatePanelImmediately(suggestion: self.lastSuggestion, client: client)
            }
        )
    }

    private static let textOnlyKeyCode = -1
    private static let maxUserSelectionHistory = 64
    private static let maxRecentLexicalCommits = 32
    private static let leadingFullCandidateCount = 5
    private static let preferenceReloadInterval: TimeInterval = 1

    private func traceStartupEvent(_ event: String, details: String = "") {
        Self.traceStartupEvent(event: event, details: details, startedAt: startupDebugStartedAt)
    }

    private static func traceStartupEvent(event: String, details: String, startedAt: Date) {
        guard ProcessInfo.processInfo.environment["KNOWTYPE_STARTUP_DEBUG"] == "1" else {
            return
        }
        let elapsedMs = Date().timeIntervalSince(startedAt) * 1_000
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
