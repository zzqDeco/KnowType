import CoreGraphics
import Foundation
import KnowTypeAI
import KnowTypeCore
import KnowTypeProviders

final class InputControllerCoordinator: @unchecked Sendable {
    private let canRequestAIRecommendations: Bool
    private var conversionEngine: any KnowTypeConversionEngine
    private let keyMapper = InputKeyCommandMapper()
    private var punctuatorRuntime = InputPunctuatorRuntime()
    private let candidateListBuilder = InputCandidateListBuilder()
    private let anchorResolver: CandidateAnchorResolver
    private weak var host: InputControllerHost?
    private let inputEventBus = InputEventBus()
    private let activeSessionRuntime = InputActiveSessionRuntime()
    private let compositionLifecycleRuntime = InputCompositionLifecycleRuntime()
    private let suggestionStateRuntime = InputSuggestionStateRuntime()
    private var locale: KnowTypeLocale = .mixed
    private let inputModePreferenceStore: any InputModePreferenceStore
    private let inputModeStateRuntime: any InputModeStateRuntime
    private var inputModeSnapshot: InputModeSnapshot
    private var loadedGlobalSymbolWidth: InputSymbolWidth
    private let runtimePreferenceStore: any InputMethodRuntimePreferenceStore
    private var runtimePreferences: InputMethodRuntimePreferences
    private let nativeCandidateNavigationRuntime = InputNativeCandidateNavigationRuntime()
    private var modeStatusText: String?
    private var punctuationContextResolver = InputPunctuationContextResolver()
    private let lexicalCommitRuntime: InputLexicalCommitRuntime
    private let commitApplicationRuntime = InputCommitApplicationRuntime()
    private let commitDecisionRuntime = InputCommitDecisionRuntime()
    private let turnSequencingRuntime = InputTurnSequencingRuntime()
    private let turnSequenceValidator = InputTurnSequenceValidator()
    private let enablesAsyncSuggestionRefresh: Bool
    private let asyncSuggestionDelayNanoseconds: UInt64
    private let aiAcceptedFeedbackProvider: (any AIAcceptedFeedbackSnapshotProviding)?
    private let aiRecommendationRuntime: InputAIRecommendationRuntime
    private let aiRecommendationSchedulePolicy = InputAIRecommendationSchedulePolicy.default
    private let aiAcceptanceRuntime: InputAIAcceptanceRuntime
    private var aiRecommendationState: AIRecommendationState = .idle
    private let inputClientCompositionWriter: InputClientCompositionWriter
    private let taskSupervisor = InputTaskSupervisor()
    private let candidatePanelPublicationRuntime: InputCandidatePanelPublicationRuntime
    private let latencyTracer = InputLatencyTracer()
    private var lastInputModePreferenceReload = Date.distantPast
    private var lastRuntimePreferenceReload = Date.distantPast
    private let startupDebugStartedAt: Date

    private var compositionState: InputCompositionStateSnapshot {
        activeSessionRuntime.currentTextSnapshot
    }

    private var rawBuffer: String {
        compositionState.rawInput
    }

    private var compositionBuffer: CompositionBuffer {
        compositionState.compositionBuffer
    }

    private var compositionID: Int {
        activeSessionRuntime.currentCompositionID
    }

    private var rawRevision: Int {
        activeSessionRuntime.currentRevision
    }

    init(
        provider: (any LLMProvider)?,
        traditionalInputEngine: TraditionalInputEngine? = nil,
        lexiconRuntimeSnapshot _: InputMethodLexiconRuntimeSnapshot = InputMethodLexiconRuntimeSnapshot(
            directories: [],
            scheme: .fullPinyin
        ),
        lexiconRuntime _: InputMethodLexiconRuntime = InputMethodLexiconRuntime(directories: []),
        inputModePreferenceStore: any InputModePreferenceStore,
        inputModeStateRuntime: (any InputModeStateRuntime)? = nil,
        runtimePreferenceStore: any InputMethodRuntimePreferenceStore = UserDefaultsInputMethodRuntimePreferenceStore.defaultStore(),
        initialRuntimePreferences: InputMethodRuntimePreferences? = nil,
        initialAppBundleID _: String?,
        userSelectionHistoryPersistence: (any InputControllerUserSelectionHistoryPersisting)?,
        aiRecommendationProvider: (any AIRecommendationProviding)? = nil,
        aiRecommendationProviderAvailability: (any AIRecommendationProviderAvailabilitySnapshotting)? = nil,
        aiContextEventRecorder: (any AIContextEventRecording)? = nil,
        aiAcceptedLearning: (any AIAcceptedLearningRecording & AIAcceptedLearningSnapshotProviding)? = nil,
        aiAcceptedFeedback: (any AIAcceptedFeedbackRecording & AIAcceptedFeedbackSnapshotProviding)? = nil,
        aiRecommendationDispatchDebounceMilliseconds: Int = InputAIRecommendationRuntime.Defaults.dispatchDebounceMilliseconds,
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
        let resolvedInputModeStateRuntime = inputModeStateRuntime
            ?? ProcessInputModeStateRuntime(initialSymbolWidth: inputModePreferences.globalSymbolWidth)
        _ = resolvedInputModeStateRuntime.synchronizeConfiguredSymbolWidth(
            inputModePreferences.globalSymbolWidth
        )
        let runtimePreferences = initialRuntimePreferences ?? runtimePreferenceStore.loadPreferences()
        self.canRequestAIRecommendations = provider != nil || aiRecommendationProvider != nil
        if let conversionEngine {
            self.conversionEngine = conversionEngine
        } else if let conversionEngineFactory {
            self.conversionEngine = conversionEngineFactory(traditionalInputEngine)
        } else {
            self.conversionEngine = RimeConversionEngine()
        }
        self.inputModePreferenceStore = inputModePreferenceStore
        self.inputModeStateRuntime = resolvedInputModeStateRuntime
        self.inputModeSnapshot = resolvedInputModeStateRuntime.currentSnapshot()
        self.loadedGlobalSymbolWidth = inputModePreferences.globalSymbolWidth
        self.runtimePreferenceStore = runtimePreferenceStore
        self.runtimePreferences = runtimePreferences
        let selectionHistoryRuntime = InputSelectionHistoryRuntime(
            persistence: userSelectionHistoryPersistence,
            maxEntries: Self.maxUserSelectionHistory
        )
        self.aiAcceptedFeedbackProvider = aiAcceptedFeedback
        self.aiRecommendationRuntime = InputAIRecommendationRuntime(
            provider: aiRecommendationProvider,
            providerAvailability: aiRecommendationProviderAvailability,
            hasEagerProvider: provider != nil,
            dispatchDebounceMilliseconds: aiRecommendationDispatchDebounceMilliseconds,
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
        let lexicalProfileRuntime = LexicalProfileRuntime(
            store: lexicalProfileStore,
            rimeMaintenanceService: rimeUserDBTextProvider,
            acceptedLearningProvider: aiAcceptedLearning,
            diagnosticSink: aiDiagnosticSink,
            refreshGate: lexicalProfileRefreshGate
        )
        self.lexicalCommitRuntime = InputLexicalCommitRuntime(
            selectionHistoryRuntime: selectionHistoryRuntime,
            lexicalProfileRuntime: lexicalProfileRuntime
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
        self.conversionEngine.synchronizeInputMode(self.inputModeSnapshot)
    }

    func handleText(_ string: String?, client: InputControllerClient?) -> Bool {
        let stroke = InputKeyStroke(
            text: string ?? "",
            keyCode: Self.textOnlyKeyCode
        )
        return handle(stroke: stroke, client: client)
    }

    func handle(stroke: InputKeyStroke, client: InputControllerClient?) -> Bool {
        return latencyTracer.trace("handle_key_total") {
            handle(intent: keyMapper.intent(for: stroke), client: client)
        }
    }

    func handle(commandSelectorName: String, client: InputControllerClient?) -> Bool {
        guard let intent = keyMapper.intent(forCommandSelectorName: commandSelectorName) else {
            return false
        }
        return latencyTracer.trace("handle_key_total") {
            handle(intent: intent, client: client)
        }
    }

    func composedString() -> Any {
        nativeMarkedText() ?? compositionBuffer.displayText
    }

    func originalString() -> NSAttributedString {
        NSAttributedString(string: rawBuffer)
    }

    func currentInputModeState() -> InputModeState {
        inputModeStateRuntime.currentSnapshot().state
    }

    func candidates() -> [Any] {
        let selections = candidateListBuilder.candidateSelections(
            rawInput: rawBuffer,
            suggestion: suggestionStateRuntime.currentSnapshot().suggestion
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
        if case .symbolCandidate(let index) = selection,
           activeSessionRuntime.currentSymbolComposition != nil {
            guard let plan = activeSessionRuntime.transitionForPanelSelection(at: index) else {
                return
            }
            _ = executeActiveSymbolTransitionPlan(
                plan,
                client: host?.currentClient,
                hideReason: .compositionEnded
            )
            return
        }
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
        if case .symbolCandidate(let index) = selection {
            guard let plan = activeSessionRuntime.transitionForMouseCommit(at: index) else {
                return
            }
            _ = executeActiveSymbolTransitionPlan(
                plan,
                client: client,
                hideReason: .compositionEnded
            )
            return
        }
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
            if activeSessionRuntime.currentSymbolComposition != nil {
                guard let plan = activeSessionRuntime.transition(
                    for: .moveCandidateSelection(navigation)
                ) else {
                    return true
                }
                _ = executeActiveSymbolTransitionPlan(
                    plan,
                    client: host?.currentClient,
                    hideReason: .compositionEnded
                )
                return true
            }
            return moveCandidateSelection(navigation)
        case .down, .up, .left, .right:
            return false
        }
    }

    func commitComposition(client: InputControllerClient?) {
        let client = effectiveClient(client)
        if let plan = activeSessionRuntime.transition(for: .commitComposition) {
            _ = executeActiveSymbolTransitionPlan(
                plan,
                client: client,
                hideReason: .compositionEnded
            )
            return
        }
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
        let client = host?.currentClient
        if let plan = activeSessionRuntime.transition(
            for: .clickOutside(
                currentHostSnapshot: client.map { hostCursorSnapshot(client: $0) }
            )
        ) {
            _ = executeActiveSymbolTransitionPlan(plan, client: client, hideReason: .escape)
            return
        }
        hideCandidatePanel(reason: .escape)
    }

    func deactivateServer(client: InputControllerClient?) {
        flushUserSelectionHistory()
        aiAcceptanceRuntime.cancelFeedback(reason: "deactivate")
        resetPunctuationSessionContext()
        let effectiveClient = effectiveClient(client)
        if let plan = activeSessionRuntime.transition(
            for: .deactivate(
                currentHostSnapshot: effectiveClient.map { hostCursorSnapshot(client: $0) }
            )
        ) {
            _ = executeActiveSymbolTransitionPlan(
                plan,
                client: effectiveClient,
                hideReason: .deactivate
            )
            return
        }
        _ = finishCompositionLifecycle(reason: .deactivate, client: client, commitPolicy: .commitRawIfNeeded)
    }

    func inputControllerWillClose() {
        flushUserSelectionHistory()
        if let plan = activeSessionRuntime.transition(for: .controllerClose) {
            _ = executeActiveSymbolTransitionPlan(
                plan,
                client: nil,
                hideReason: .compositionEnded
            )
        }
        aiRecommendationState = aiRecommendationRuntime.reset(
            compositionID: compositionID,
            rawLength: rawBuffer.count,
            reason: "input_controller_will_close"
        )
        aiAcceptanceRuntime.cancelFeedback(reason: "input_controller_will_close")
        lexicalCommitRuntime.cancelRefresh()
        taskSupervisor.cancelAll()
        resetPunctuationSessionContext()
        _ = finishCompositionLifecycle(reason: .close, client: nil, commitPolicy: .none)
    }

    func reloadRuntimePreferencesForExternalChange() {
        lastRuntimePreferenceReload = .distantPast
        guard reloadRuntimePreferencesIfNeeded() else {
            return
        }
        let client = host?.currentClient
        if activeSessionRuntime.currentSymbolComposition != nil {
            publishCurrentSymbolComposition(client: client)
            return
        }
        publishLocalSuggestionSynchronously(client: client)
        updateCandidatePanelImmediately(
            suggestion: suggestionStateRuntime.currentSnapshot().suggestion,
            client: client
        )
    }

    private func handle(intent: InputKeyIntent, client: InputControllerClient?) -> Bool {
        let client = client ?? (
            hasActiveTextComposition() || activeSessionRuntime.currentSymbolComposition != nil
                ? host?.currentClient
                : nil
        )
        synchronizeInputModeSnapshot(client: client)
        clearTransientModeStatusBeforeUserInputIfNeeded(intent)
        if activeSessionRuntime.currentSymbolComposition != nil {
            switch handleActiveSymbolCandidateIntent(intent, client: client) {
            case .handled(let handled):
                return handled
            case .replay:
                break
            }
        }
        switch intent {
        case .append(let text):
            if !hasActiveTextComposition() {
                reloadInputModePreferencesIfNeeded()
                if shouldPassThroughIdleText(text, client: client, reason: "idle_append") {
                    return false
                }
                if inputModeSnapshot.state.textMode == .ascii,
                   let fullWidthText = fullWidthIdleText(for: text) {
                    return insertDirectPassthroughText(fullWidthText, client: client)
                }
                if Self.isDirectPassthroughDigitText(text) {
                    return insertDirectPassthroughText(text, client: client)
                }
            }
            return appendComposition(text, client: client)
        case .symbol(let text):
            if conversionEngine.isNativeActive,
               !rawBuffer.isEmpty {
                if handleNativePagingSymbol(text, client: client) {
                    return true
                }
                if !InputNativeCandidateNavigationRuntime.isPagingSymbol(text) {
                    let result = conversionEngine.process(.text(text))
                    if result.handled {
                        return handleNativeConversionResult(result, client: client)
                    }
                }
            }
            if rawBuffer.isEmpty {
                reloadInputModePreferencesIfNeeded()
            }
            let punctuatorContext = inputPunctuatorContext(for: text, client: client)
            guard let rule = punctuatorRuntime.rule(for: text, context: punctuatorContext) else {
                return appendComposition(text, client: client)
            }
            return handlePunctuatorRule(rule, originalInput: text, client: client)
        case .deleteBackward:
            guard !rawBuffer.isEmpty else {
                resetPunctuationSessionContext()
                _ = aiAcceptanceRuntime.observeDeleteBackward(client: client)
                aiAcceptanceRuntime.recordExternalDelete(appBundleID: appBundleIdentifier(client: client))
                return false
            }
            let deleteResult = activeSessionRuntime.deleteBackward()
            if deleteResult.removedRawCharacter {
                _ = conversionEngine.process(.deleteBackward)
                if deleteResult.becameEmpty {
                    conversionEngine.reset()
                    resetAnchorState()
                }
            }
            invalidateSuggestion(reason: "input_changed")
            publishLocalSuggestion(client: client)
            return true
        case .action(let action):
            if action == .toggleSymbolMode || action == .toggleTextMode || action == .toggleSymbolWidth {
                reloadInputModePreferencesIfNeeded()
            }
            if action == .toggleSymbolMode {
                applyInputModeTransition(.togglePunctuationMode)
                showModeStatus(client: client)
                return true
            }
            if action == .toggleTextMode {
                applyInputModeTransition(.toggleTextMode)
                showModeStatus(client: client)
                return true
            }
            if action == .toggleSymbolWidth {
                applyInputModeTransition(.toggleSymbolWidth)
                showModeStatus(client: client)
                return true
            }
            if action == .space,
               !hasActiveTextComposition() {
                reloadInputModePreferencesIfNeeded()
                if shouldPassThroughIdleText(" ", client: client, reason: "idle_space") {
                    return false
                }
                if let fullWidthSpace = fullWidthIdleText(for: " ") {
                    return insertDirectPassthroughText(fullWidthSpace, client: client)
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
                reloadInputModePreferencesIfNeeded()
                let text = String(number)
                if shouldPassThroughIdleText(text, client: client, reason: "idle_digit") {
                    return false
                }
                if let fullWidthDigit = fullWidthIdleText(for: text) {
                    return insertDirectPassthroughText(fullWidthDigit, client: client)
                }
                return insertDirectPassthroughText(text, client: client)
            }
            if conversionEngine.isNativeActive,
               conversionEngine.snapshot.hasComposition,
               number > 0 {
                return selectNativeCandidateOnCurrentPage(number - 1, client: client)
            }
            let panelState = candidatePanelPublicationRuntime.state
            if panelState.windowState.isVisible {
                let suggestionSnapshot = suggestionStateRuntime.currentSnapshot()
                if number == 0,
                   let result = InputSessionCommitPolicy.resultForCandidateNumber(
                       number,
                       rawInput: rawBuffer,
                       suggestion: suggestionSnapshot.suggestion,
                       suggestionRawInput: suggestionSnapshot.rawInput
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
            if !hasActiveTextComposition() {
                resetPunctuationSessionContext()
            }
            return moveCandidateSelection(navigation)
        case .modifierFlagsChanged:
            return false
        case .hostShortcut:
            resetPunctuationSessionContext()
            return false
        case .ignored:
            resetPunctuationSessionContext()
            return false
        }
    }

    private func appendComposition(_ text: String, client: InputControllerClient?) -> Bool {
        beginCompositionIfNeeded(client: client)
        activeSessionRuntime.appendText(text)
        _ = conversionEngine.process(.text(text))
        aiRecommendationState = .idle
        invalidateSuggestion(reason: "input_changed")
        publishLocalSuggestion(client: client)
        return true
    }

    private func handlePunctuatorRule(
        _ rule: InputSymbolRule,
        originalInput: String,
        client: InputControllerClient?
    ) -> Bool {
        if !hasActiveTextComposition(),
           shouldPassThroughIdleText(originalInput, client: client, reason: "idle_symbol") {
            return false
        }
        switch rule {
        case .direct(let text):
            return commitSymbol(text, client: client)
        case .candidates(let trigger, let outputs):
            return beginSymbolCandidateComposition(
                trigger: trigger,
                candidates: outputs,
                client: client
            )
        }
    }

    private func handleActiveSymbolCandidateIntent(
        _ intent: InputKeyIntent,
        client: InputControllerClient?
    ) -> ActiveSymbolIntentResult {
        guard let plan = activeSessionRuntime.transition(for: intent) else {
            return .handled(false)
        }
        return executeActiveSymbolTransitionPlan(
            plan,
            client: client,
            hideReason: .compositionEnded
        )
    }

    private func executeActiveSymbolTransitionPlan(
        _ plan: SymbolCompositionTransitionPlan,
        client: InputControllerClient?,
        hideReason: CandidatePanelVisibilityReason
    ) -> ActiveSymbolIntentResult {
        switch plan {
        case .keep(let composition, let handled, let reason):
            traceSymbolSessionTransition(
                reason.rawValue,
                composition: composition,
                handled: handled
            )
            return .handled(handled)
        case .update(let composition, let reason):
            traceSymbolSessionTransition(
                reason.rawValue,
                composition: composition,
                handled: true
            )
            publishCurrentSymbolComposition(client: client)
            return .handled(true)
        case .commit(let composition, let candidate, let replayIntent, let reason):
            traceSymbolSessionTransition(
                reason.rawValue,
                composition: composition,
                handled: true
            )
            _ = commitSymbol(candidate.text, client: client)
            hideCandidatePanelIfVisible(reason: hideReason)
            return replayIntent == nil ? .handled(true) : .replay
        case .cancel(let composition, let replayIntent, let handled, let reason):
            traceSymbolSessionTransition(
                reason.rawValue,
                composition: composition,
                handled: handled
            )
            hideCandidatePanel(reason: hideReason)
            if reason == .hostShortcut {
                resetPunctuationSessionContext()
            }
            return replayIntent == nil ? .handled(handled) : .replay
        }
    }

    private enum ActiveSymbolIntentResult {
        case handled(Bool)
        case replay
    }

    private func beginSymbolCandidateComposition(
        trigger: String,
        candidates: [InputSymbolCandidate],
        client: InputControllerClient?
    ) -> Bool {
        if hasActiveTextComposition() {
            guard let client else {
                return true
            }
            commitComposition(client: client)
            guard !hasActiveTextComposition() else {
                return true
            }
        }
        aiRecommendationState = aiRecommendationRuntime.reset(
            compositionID: compositionID,
            rawLength: rawBuffer.count,
            reason: "symbol_candidate"
        )
        guard activeSessionRuntime.beginSymbolComposition(
            trigger: trigger,
            candidates: candidates,
            pageSize: runtimePreferences.effectiveCandidatePageSize,
            hostCursorSnapshot: hostCursorSnapshot(client: client)
        ) != nil else {
            return false
        }
        traceSymbolSessionTransition("begin")
        publishCurrentSymbolComposition(client: client)
        return true
    }

    private func publishCurrentSymbolComposition(client: InputControllerClient?) {
        guard let composition = activeSessionRuntime.currentSymbolComposition else {
            return
        }
        publishPanelOverlay(
            modeStatusText: modeStatusText,
            symbolCandidates: composition.candidates,
            preferredSelection: .symbolCandidate(composition.selectedIndex),
            pageSize: composition.pageSize,
            client: client
        )
    }

    private func hostCursorSnapshot(client: InputControllerClient?) -> InputHostCursorSnapshot {
        InputHostCursorSnapshot(
            selectedRange: client?.selectedRange ?? NSRange(location: NSNotFound, length: 0),
            markedRange: client?.markedRange,
            hostIdentity: client?.feedbackTrackingID,
            bundleIdentifier: client?.bundleIdentifier
        )
    }

    private func traceSymbolSessionTransition(
        _ reason: String,
        composition: SymbolComposition? = nil,
        handled: Bool = true
    ) {
        guard InputDebugDiagnostics.isEnabled(.turn) else {
            return
        }
        let compositionID = composition?.compositionID ?? self.compositionID
        let revision = composition?.revision ?? rawRevision
        InputDebugDiagnostics.emit(
            category: .turn,
            fields: [
                .init(.stage, "symbol_session"),
                .init(.compositionID, compositionID),
                .init(.rawRevision, revision),
                .init(.reason, reason),
                .init(.handled, handled)
            ]
        )
    }

    private func commitSymbol(_ symbol: String, client: InputControllerClient?) -> Bool {
        guard !rawBuffer.isEmpty else {
            hideCandidatePanelIfVisible(reason: .compositionEnded)
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

        let baseResultPlan = latencyTracer.trace("commit_decision") {
            commitDecisionRuntime.resultPlan(context: commitDecisionContext(action: .space, client: client))
        }
        let baseResult = executeCommitDecisionResultPlan(baseResultPlan, client: client)
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

    private func refreshResolvedCompositionContinuations(client: InputControllerClient?) {
        guard enablesAsyncSuggestionRefresh,
              compositionBuffer.isFullyResolved else {
            return
        }
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
            fallbackLatency: suggestionStateRuntime.currentSnapshot().suggestion?.latencyMs ?? 0
        )
        suggestionStateRuntime.store(suggestion: suggestion, rawInput: rawInput)
        refreshComposition(client: client)
        updateCandidatePanel(suggestion: suggestion, client: client)
        scheduleAIRecommendation(for: suggestion, client: client)
    }

    private func resolvedCompositionSuggestion(
        lockedPrefix: LockedPrefix,
        continuations: [ContinuationCandidate],
        fallbackLatency: Int
    ) -> SuggestionResponse {
        let currentSuggestion = suggestionStateRuntime.currentSnapshot().suggestion
        let prefixCandidates = currentSuggestion?.prefixCandidates.isEmpty == false
            ? currentSuggestion?.prefixCandidates ?? []
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
        let plan = latencyTracer.trace("commit_decision") {
            commitDecisionRuntime.numberSelectionPlan(
                selection: selection,
                context: commitDecisionContext(action: .space, client: client)
            )
        }
        return executeCommitDecisionResultPlan(plan, client: client)
    }

    @discardableResult
    private func applyCommitDecisionResultPlan(
        _ plan: InputCommitDecisionResultPlan,
        action: InputAction,
        client: InputControllerClient?
    ) -> Bool {
        let result = executeCommitDecisionResultPlan(
            plan,
            client: client
        )
        learnSelectedPrefix(action: action, result: result, client: client)
        return applyCommitResult(
            result,
            client: client,
            acceptedAIRecommendation: acceptedAIRecommendationCandidate(for: action, result: result)
        )
    }

    @discardableResult
    private func executeCommitDecisionResultPlan(
        _ plan: InputCommitDecisionResultPlan,
        client: InputControllerClient?
    ) -> InputCommitResult {
        switch plan {
        case .result(let result):
            return result
        case .applySegmentCandidate(let index, let commitIfFullyResolved):
            return applySegmentCandidate(
                at: index,
                commitIfFullyResolved: commitIfFullyResolved,
                client: client
            )
        case .selectNativeCandidateForCommit(let selection):
            return nativeCandidateCommitResult(selection, client: client)
        case .processNativeSpace:
            return nativeSpaceCommitResult(client: client)
        }
    }

    private func nativeCandidateCommitResult(
        _ selection: InputCandidateSelection,
        client: InputControllerClient?
    ) -> InputCommitResult {
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

    private func nativeSpaceCommitResult(client: InputControllerClient?) -> InputCommitResult {
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
        return .noAction
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

    private func appBundleIdentifier(client: InputControllerClient?) -> String? {
        client?.bundleIdentifier
    }

    private func inputPunctuatorContext(
        for input: String,
        client: InputControllerClient?
    ) -> InputPunctuatorContext {
        let hasActiveComposition = hasActiveTextComposition()
        guard input == "." || input == "\"" || input == "'" else {
            return InputPunctuatorContext(
                state: inputModeSnapshot.state,
                hasActiveComposition: hasActiveComposition
            )
        }
        let readsChineseQuoteContext = (input == "\"" || input == "'")
            && inputModeSnapshot.state.punctuationMode == .chinese
            && inputModeSnapshot.state.symbolWidth == .halfWidth
        let resolution = punctuationContextResolver.resolve(
            client: client,
            hasActiveComposition: hasActiveComposition,
            readsCharacterBeforeCaret: readsChineseQuoteContext
        )
        if resolution.didSelectionOrFocusChange {
            punctuatorRuntime.resetPairingState()
        }
        let previous = resolution.previousCharacter
        if InputDebugDiagnostics.isEnabled(.turn) {
            InputDebugDiagnostics.emit(
                category: .turn,
                fields: [
                    .init(.stage, "punctuation_context"),
                    .init(.reason, "previous=\(previous.kind.rawValue);source=\(previous.source.rawValue)")
                ]
            )
        }
        return InputPunctuatorContext(
            state: inputModeSnapshot.state,
            previousCharacterKind: previous.kind,
            quoteContext: previous.quoteContext,
            hasActiveComposition: hasActiveComposition
        )
    }

    private func effectiveClient(_ client: InputControllerClient?) -> InputControllerClient? {
        client ?? host?.currentClient
    }

    private func writeState(hasActiveComposition: Bool? = nil) -> InputClientCompositionWriteState {
        InputClientCompositionWriteState(
            compositionID: compositionID,
            rawLength: rawBuffer.count,
            inputModeState: inputModeSnapshot.state,
            hasActiveComposition: hasActiveComposition ?? hasActiveTextComposition()
        )
    }

    private func commitDecisionContext(
        action: InputAction,
        client: InputControllerClient?
    ) -> InputCommitDecisionContext {
        let selectedCandidate = nativeCandidateNavigationRuntime.selectedCandidate
        let selectedCandidateHasNativeIndex = selectedCandidate.map {
            nativeCandidateNavigationRuntime.nativeCandidateIndex(for: $0, engine: conversionEngine) != nil
        } ?? false
        return InputCommitDecisionContext(
            action: action,
            rawInput: rawBuffer,
            compositionBuffer: compositionBuffer,
            suggestionSnapshot: suggestionStateRuntime.currentSnapshot(),
            commitSuggestionSnapshot: suggestionStateRuntime.commitSnapshot(
                action: action,
                rawInput: rawBuffer,
                asyncEnabled: enablesAsyncSuggestionRefresh
            ),
            selectedCandidate: selectedCandidate,
            panelSelection: candidatePanelPublicationRuntime.state.windowState.selection,
            panelIsVisible: candidatePanelPublicationRuntime.state.windowState.isVisible,
            aiRecommendationState: aiRecommendationState,
            hasActiveTextComposition: hasActiveTextComposition(),
            enablesAsyncSuggestionRefresh: enablesAsyncSuggestionRefresh,
            isNativeActive: conversionEngine.isNativeActive,
            selectedCandidateShouldSelectBeforeSpace: selectedCandidate.map(shouldSelectNativeCandidateBeforeSpace) ?? false,
            selectedCandidateHasNativeIndex: selectedCandidateHasNativeIndex,
            appBundleID: appBundleIdentifier(client: client),
            locale: locale,
            runtimePreferences: runtimePreferences
        )
    }

    private func shouldPassThroughIdleText(
        _ text: String,
        client: InputControllerClient?,
        reason: String
    ) -> Bool {
        if inputModeSnapshot.state.symbolWidth == .fullWidth,
           fullWidthIdleText(for: text) != nil,
           inputClientCompositionWriter.writeMode(
               client: client,
               state: writeState(hasActiveComposition: false)
           ) != .disabled {
            return false
        }
        let shouldPassThrough = inputClientCompositionWriter.shouldPassThroughIdleText(
            text,
            client: client,
            state: writeState(hasActiveComposition: false),
            reason: reason
        )
        if shouldPassThrough {
            hideCandidatePanelIfVisible(reason: .compositionEnded)
        }
        return shouldPassThrough
    }

    private func fullWidthIdleText(for text: String) -> String? {
        guard inputModeSnapshot.state.symbolWidth == .fullWidth else {
            return nil
        }
        let transformed = InputSymbolTransformer.textWithWidth(for: text, width: .fullWidth)
        return transformed == text ? nil : transformed
    }

    private func candidatePanelPlacementPreference(
        client: InputControllerClient?
    ) -> CandidatePanelPlacementPreference {
        appBundleIdentifier(client: client) == "com.apple.Spotlight"
            ? .preferVisualAbove
            : .automatic
    }

    private func publishLocalSuggestion(client: InputControllerClient?) {
        latencyTracer.trace("publish_local_suggestion") {
            publishLocalSuggestionSynchronously(client: client)
        }
    }

    private func publishLocalSuggestionSynchronously(client: InputControllerClient?) {
        guard SuggestionRefreshPolicy.shouldRefresh(rawInput: rawBuffer) else {
            suggestionStateRuntime.clear()
            refreshComposition(client: client)
            updateCandidatePanelImmediately(suggestion: nil, client: client)
            return
        }

        guard let suggestion = conversionSuggestion() else {
            suggestionStateRuntime.clear()
            refreshComposition(client: client)
            updateCandidatePanelImmediately(suggestion: nil, client: client)
            return
        }

        let rimeSuggestion = augmentedSuggestion(suggestion)
        suggestionStateRuntime.store(suggestion: rimeSuggestion, rawInput: rawBuffer)
        refreshComposition(client: client)
        updateCandidatePanelImmediately(suggestion: rimeSuggestion, client: client)
        scheduleAIRecommendation(for: rimeSuggestion, client: client)
    }

    private func refreshNativeHighlightPresentation(client: InputControllerClient?) {
        let snapshot = suggestionStateRuntime.currentSnapshot()
        guard suggestionStateRuntime.hasCurrentSuggestion(rawInput: rawBuffer),
              let suggestion = snapshot.suggestion else {
            publishLocalSuggestion(client: client)
            return
        }
        refreshComposition(client: client)
        updateCandidatePanelImmediately(suggestion: suggestion, client: client)
    }

    private func conversionSuggestion() -> SuggestionResponse? {
        guard conversionEngine.isNativeActive else {
            return nil
        }
        return conversionEngine.snapshot.suggestionResponse(originalRawInput: rawBuffer)
    }

    private func lexicalContextSnapshot(for _: SuggestionResponse) -> LexicalContextSnapshot? {
        lexicalCommitRuntime.lexicalContextSnapshot(schemaID: conversionEngine.activeSchemaID)
    }

    static func confirmedLockedPrefixText(for suggestion: SuggestionResponse) -> String? {
        let text = suggestion.lockedPrefix?.text
        return text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? text : nil
    }

    private func scheduleAIRecommendation(for suggestion: SuggestionResponse, client: InputControllerClient?) {
        let currentAppBundleID = appBundleIdentifier(client: client)
        let lockedPrefixText = Self.confirmedLockedPrefixText(for: suggestion)
        let shouldScheduleRecommendationRequest = aiRecommendationRuntime.shouldScheduleRecommendationRequest
        let canBuildRecommendationContext = aiRecommendationRuntime.shouldBuildRecommendationContext
        let scheduleDecision = aiRecommendationSchedulePolicy.decision(
            for: InputAIRecommendationScheduleContext(
                rawInput: rawBuffer,
                hasResolvedSegments: compositionBuffer.hasResolvedSegments,
                isFullyResolved: compositionBuffer.isFullyResolved,
                lockedPrefix: lockedPrefixText,
                cloudContinuationEnabled: runtimePreferences.cloudContinuationEnabled,
                canRequestAIRecommendations: canRequestAIRecommendations,
                hasRecommendationProvider: shouldScheduleRecommendationRequest
            )
        )
        let shouldBuildRecommendationContext: Bool
        if case .schedule = scheduleDecision {
            shouldBuildRecommendationContext = canBuildRecommendationContext
        } else {
            shouldBuildRecommendationContext = false
        }
        let isProviderAvailabilityProbe: Bool
        if case .schedule = scheduleDecision {
            isProviderAvailabilityProbe = shouldScheduleRecommendationRequest && !canBuildRecommendationContext
        } else {
            isProviderAvailabilityProbe = false
        }
        let context = InputAIRecommendationRuntimeContext(
            rawInput: rawBuffer,
            hasResolvedSegments: compositionBuffer.hasResolvedSegments,
            isFullyResolved: compositionBuffer.isFullyResolved,
            lockedPrefix: lockedPrefixText,
            cloudContinuationEnabled: runtimePreferences.cloudContinuationEnabled,
            canRequestAIRecommendations: canRequestAIRecommendations,
            hasRecommendationProvider: shouldScheduleRecommendationRequest,
            isProviderAvailabilityProbe: isProviderAvailabilityProbe,
            appBundleID: currentAppBundleID,
            locale: locale,
            compositionID: compositionID,
            rawRevision: rawRevision,
            lexicalContext: shouldBuildRecommendationContext ? lexicalContextSnapshot(for: suggestion) : nil,
            feedbackContext: shouldBuildRecommendationContext
                ? aiAcceptedFeedbackProvider?.snapshot(schemaID: conversionEngine.activeSchemaID)
                : nil
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
                self.updateCandidatePanel(
                    suggestion: self.suggestionStateRuntime.currentSnapshot().suggestion,
                    client: self.host?.currentClient
                )
            }
        )
        updateCandidatePanel(suggestion: suggestion, client: client)
    }

    private func clearNoProviderFallbackContinuationsIfProviderIsKnown() {
        _ = suggestionStateRuntime.clearNoProviderFallbackContinuationsIfNeeded(
            hasKnownProvider: aiRecommendationRuntime.hasKnownProvider
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
        let plan = latencyTracer.trace("commit_decision") {
            commitDecisionRuntime.commitPlan(context: commitDecisionContext(action: action, client: client))
        }
        return executeCommitDecisionPlan(
            plan,
            action: action,
            client: client
        )
    }

    @discardableResult
    private func executeCommitDecisionPlan(
        _ plan: InputCommitDecisionPlan,
        action: InputAction,
        client: InputControllerClient?
    ) -> Bool {
        switch plan {
        case .directPassthroughSpace:
            return insertDirectPassthroughText(" ", client: client)
        case .finishEmptyRawCommit:
            _ = finishCompositionLifecycle(reason: .commit, client: client, commitPolicy: .none)
            return false
        case .selectNativeCandidateBeforeSpace(let selectedNativeCandidate):
            if applyNativeNavigationResult(
                nativeCandidateNavigationRuntime.selectNativeCandidateIfNeeded(
                    selectedNativeCandidate,
                    engine: &conversionEngine
                ),
                client: client
            ) {
                return true
            }
            return processNativeSpace(client: client)
        case .processNativeSpace:
            return processNativeSpace(client: client)
        case .resolve(let resultPlan):
            return applyCommitDecisionResultPlan(resultPlan, action: action, client: client)
        }
    }

    private func processNativeSpace(client: InputControllerClient?) -> Bool {
        let result = conversionEngine.process(.space)
        learnNativeCommitIfFinal(result, client: client)
        if handleNativeConversionResult(result, client: client) {
            return true
        }
        return applyCommitResult(rawBuffer.isEmpty ? .noAction : .commit(rawBuffer), client: client)
    }

    @discardableResult
    private func applyCommitResult(
        _ result: InputCommitResult,
        client: InputControllerClient?,
        acceptedAIRecommendation: AIRecommendationCandidate? = nil
    ) -> Bool {
        let turn = turnSequencingRuntime.beginTurn(
            kind: .commitResult,
            snapshot: compositionState
        )
        let resetPlan = compositionLifecycleRuntime.finishPlan(
            reason: .reset,
            compositionSnapshot: turn.compositionSnapshot,
            hasNativeComposition: conversionEngine.snapshot.hasComposition,
            commitText: nil
        )
        let sequence = turnSequencingRuntime.commitSequence(
            token: turn,
            applicationPlan: commitApplicationRuntime.plan(for: result, hasComposition: !rawBuffer.isEmpty),
            acceptedAIRecommendation: acceptedAIRecommendation,
            resetPlan: resetPlan
        )
        return executeTurnEffectSequence(sequence, client: client)
    }

    @discardableResult
    private func handleNativeConversionResult(
        _ result: ConversionEngineResult,
        client: InputControllerClient?
    ) -> Bool {
        if let commitText = result.commitText,
           !commitText.isEmpty {
            if result.snapshot.hasComposition {
                let turn = turnSequencingRuntime.beginTurn(
                    kind: .nativeCommit,
                    snapshot: compositionState
                )
                return executeTurnEffectSequence(
                    turnSequencingRuntime.nativeCommitSequence(
                        token: turn,
                        text: commitText,
                        snapshot: result.snapshot
                    ),
                    client: client
                )
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
        let turn = turnSequencingRuntime.beginTurn(
            kind: .nativeHandled,
            snapshot: compositionState
        )
        return executeTurnEffectSequence(
            turnSequencingRuntime.nativeHandledSequence(token: turn, snapshot: result.snapshot),
            client: client
        )
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
        hasActiveTextComposition(snapshot: compositionState)
            || conversionEngine.snapshot.hasComposition
    }

    private func hasActiveTextComposition(snapshot: InputCompositionStateSnapshot) -> Bool {
        snapshot.hasActiveTextComposition
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
        activeSessionRuntime.syncRawInputFromNativeSnapshot(snapshot)
    }

    private func learnSelectedPrefix(action: InputAction, result: InputCommitResult, client: InputControllerClient?) {
        guard case .commit(let committedText) = result,
              !committedText.isEmpty,
              !commitDecisionRuntime.shouldSkipPrefixLearning(
                action: action,
                aiRecommendationState: aiRecommendationState
              ),
              let prefix = commitDecisionRuntime.selectedPrefixTextForLearning(
                selectedCandidate: nativeCandidateNavigationRuntime.selectedCandidate,
                panelSelection: candidatePanelPublicationRuntime.state.windowState.selection,
                suggestion: suggestionStateRuntime.currentSnapshot().suggestion
              ),
              prefix != rawBuffer,
              committedText.hasPrefix(prefix) else {
            return
        }
        recordUserSelection(prefix, client: client)
    }

    private func recordUserSelection(_ text: String, client: InputControllerClient?) {
        let context = InputLexicalSelectionContext(
            text: text,
            rawInput: rawBuffer,
            appBundleID: appBundleIdentifier(client: client),
            schemaID: conversionEngine.activeSchemaID,
            compositionID: compositionID
        )
        guard let event = lexicalCommitRuntime.recordSelection(context: context) else {
            return
        }
        publishRuntimeEvent(event)
    }

    private func publishRuntimeEvent(_ event: InputRuntimeEvent) {
        Task.detached(priority: .utility) { [inputEventBus] in
            await inputEventBus.publish(event)
        }
    }

    private func flushUserSelectionHistory() {
        lexicalCommitRuntime.flushSelectionHistory()
    }

    private func applySegmentCandidate(
        at index: Int,
        commitIfFullyResolved: Bool,
        client: InputControllerClient?
    ) -> InputCommitResult {
        guard let candidate = suggestionStateRuntime.currentSnapshot().suggestion?.prefixCandidates[inputControllerSafe: index],
              candidate.rawRange != compositionBuffer.rawRange else {
            return .noAction
        }
        guard activeSessionRuntime.applySegmentCandidate(candidate) else {
            return .noAction
        }
        let isFullyResolvedAfterApply = compositionBuffer.isFullyResolved
        publishLocalSuggestion(client: client)
        if isFullyResolvedAfterApply {
            refreshResolvedCompositionContinuations(client: client)
        }
        if commitIfFullyResolved, isFullyResolvedAfterApply {
            return .commit(compositionBuffer.commitText)
        }
        return .noAction
    }

    private func insert(_ text: String, client: InputControllerClient?) {
        insertTextAndRecordPunctuationContext(
            text,
            client: client,
            state: writeState(),
            reason: "commit"
        )
    }

    private func insertTextAndRecordPunctuationContext(
        _ text: String,
        client: InputControllerClient?,
        state: InputClientCompositionWriteState,
        reason: String,
        clearsOwnedMarkedText: Bool = true
    ) {
        let selectedRangeBeforeInsertion = client?.selectedRange
        inputClientCompositionWriter.insertText(
            text,
            client: client,
            state: state,
            reason: reason,
            clearsOwnedMarkedText: clearsOwnedMarkedText
        )
        punctuationContextResolver.recordInsertion(
            text,
            client: client,
            selectedRangeBeforeInsertion: selectedRangeBeforeInsertion
        )
    }

    private func insertDirectPassthroughText(_ text: String, client: InputControllerClient?) -> Bool {
        guard let lifecycleClient = client ?? host?.currentClient else {
            return false
        }
        let directWriteState = writeState(hasActiveComposition: false)
        let turn = turnSequencingRuntime.beginTurn(
            kind: .directPassthrough,
            snapshot: compositionState
        )
        let resetPlan = compositionLifecycleRuntime.finishPlan(
            reason: .reset,
            compositionSnapshot: turn.compositionSnapshot,
            hasNativeComposition: conversionEngine.snapshot.hasComposition,
            commitText: nil
        )
        return executeTurnEffectSequence(
            turnSequencingRuntime.directPassthroughSequence(
                token: turn,
                text: text,
                resetPlan: resetPlan
            ),
            client: lifecycleClient,
            directPassthroughWriteState: directWriteState
        )
    }

    private func commitSideEffectContexts(
        _ text: String,
        client: InputControllerClient?,
        acceptedAIRecommendation: AIRecommendationCandidate? = nil,
        acceptID: UUID? = nil,
        compositionSnapshot: InputCompositionStateSnapshot
    ) -> InputCommitApplicationSideEffectContexts {
        commitApplicationRuntime.sideEffectContexts(
            text: text,
            schemaID: conversionEngine.activeSchemaID,
            appBundleID: appBundleIdentifier(client: client),
            acceptedAIRecommendation: acceptedAIRecommendation,
            acceptID: acceptID,
            selectedNativeCandidateSource: nativeCandidateNavigationRuntime.selectedCandidate?.kind.analyticsSource,
            prefixCandidateSource: suggestionStateRuntime.currentSnapshot().suggestion?.prefixCandidates.first?.source,
            compositionSnapshot: compositionSnapshot,
            client: client
        )
    }

    private func recordCommitSideEffects(_ contexts: InputCommitApplicationSideEffectContexts) {
        let effects = aiAcceptanceRuntime.recordCommit(
            context: contexts.aiAcceptance
        )
        if effects.shouldRecordLexicalCommit {
            if let event = lexicalCommitRuntime.recordCommit(context: contexts.lexicalCommit) {
                publishRuntimeEvent(event)
            }
        }
    }

    private func acceptedAIRecommendationCandidate(
        for action: InputAction,
        result: InputCommitResult
    ) -> AIRecommendationCandidate? {
        commitDecisionRuntime.acceptedAIRecommendationCandidate(
            action: action,
            result: result,
            selectedCandidate: nativeCandidateNavigationRuntime.selectedCandidate,
            aiRecommendationState: aiRecommendationState
        )
    }

    private func resetComposition(client: InputControllerClient? = nil) {
        _ = finishCompositionLifecycle(reason: .reset, client: client, commitPolicy: .none)
    }

    @discardableResult
    private func finishCompositionLifecycle(
        reason: CompositionLifecycleFinishReason,
        client: InputControllerClient?,
        commitPolicy: InputCompositionLifecycleCommitPolicy
    ) -> Bool {
        if let plan = activeSessionRuntime.transition(for: .reset) {
            _ = executeActiveSymbolTransitionPlan(
                plan,
                client: client,
                hideReason: .compositionEnded
            )
        }
        if reason != .commit && reason != .nativeEnded {
            punctuatorRuntime.resetPairingState()
        }
        traceCompositionLifecycleFinish(reason: reason)
        let finishingSnapshot = compositionState
        let finishPlan = compositionLifecycleRuntime.finishPlan(
            reason: reason,
            compositionSnapshot: finishingSnapshot,
            hasNativeComposition: conversionEngine.snapshot.hasComposition,
            commitText: activeSessionRuntime.lifecycleCommitText(policy: commitPolicy)
        )
        let turn = turnSequencingRuntime.beginTurn(
            kind: .lifecycleFinish,
            snapshot: finishingSnapshot
        )
        return executeTurnEffectSequence(
            turnSequencingRuntime.lifecycleFinishSequence(token: turn, finishPlan: finishPlan),
            client: client
        )
    }

    @discardableResult
    private func executeTurnEffectSequence(
        _ sequence: InputTurnEffectSequence,
        client: InputControllerClient?,
        directPassthroughWriteState: InputClientCompositionWriteState? = nil
    ) -> Bool {
        let sequenceViolations = turnSequenceValidator.validate(sequence)
        var preparedAcceptedFeedbackID: UUID?
        for effect in sequence.effects {
            traceTurnEffect(effect, sequence: sequence) {
                switch effect {
            case .prepareAcceptedFeedback(let text, let acceptedAIRecommendation):
                preparedAcceptedFeedbackID = aiAcceptanceRuntime.prepareAcceptedFeedbackTracking(
                    context: commitApplicationRuntime.acceptedFeedbackContext(
                        text: text,
                        schemaID: conversionEngine.activeSchemaID,
                        appBundleID: appBundleIdentifier(client: client),
                        acceptedAIRecommendation: acceptedAIRecommendation,
                        client: client
                    )
                )
            case .recordCommitSideEffects(let text, let acceptedAIRecommendation, let clientScope):
                let effectClient = turnClient(for: clientScope, providedClient: client)
                recordCommitSideEffects(
                    commitSideEffectContexts(
                        text,
                        client: effectClient,
                        acceptedAIRecommendation: acceptedAIRecommendation,
                        acceptID: acceptedAIRecommendation == nil ? nil : preparedAcceptedFeedbackID,
                        compositionSnapshot: sequence.token.compositionSnapshot
                    )
                )
            case .insertCommittedText(let text, let clientScope):
                insert(text, client: turnClient(for: clientScope, providedClient: client))
            case .schedulePostInsertCaretVerification:
                guard preparedAcceptedFeedbackID != nil else {
                    return
                }
                host?.schedulePostInsertCaretVerification { [weak self, client] in
                    self?.aiAcceptanceRuntime.verifyPostInsertCaret(client: client)
                }
            case .refreshComposition:
                refreshComposition(client: client)
            case .hideCandidatePanel(let reason):
                hideCandidatePanel(reason: reason)
            case .clearOwnedMarkedText:
                inputClientCompositionWriter.clearOwnedMarkedTextIfNeeded(
                    client: turnClient(for: .effective, providedClient: client),
                    state: writeState()
                )
            case .resetConversionEngine:
                conversionEngine.reset()
            case .resetCompositionStateAfterLifecycleFinish:
                activeSessionRuntime.resetTextAfterLifecycleFinish()
            case .resetAnchorState:
                resetAnchorState()
            case .invalidateSuggestion:
                invalidateSuggestion()
            case .finishWriterLifecycle(let shouldClearOwnedMarkedTextWhenEndingWithoutCommit):
                inputClientCompositionWriter.finishLifecycle(
                    shouldClearOwnedMarkedTextWhenEndingWithoutCommit: shouldClearOwnedMarkedTextWhenEndingWithoutCommit
                )
            case .publishCompositionEnded(let reason, let compositionID):
                publishRuntimeEvent(
                    .compositionEnded(reason: reason, compositionID: compositionID)
                )
            case .cancelAIFeedback(let reason):
                aiAcceptanceRuntime.cancelFeedback(reason: reason)
            case .insertDirectPassthroughText(let text):
                guard let passthroughClient = turnClient(for: .effective, providedClient: client) else {
                    return
                }
                insertTextAndRecordPunctuationContext(
                    text,
                    client: passthroughClient,
                    state: directPassthroughWriteState ?? writeState(hasActiveComposition: false),
                    reason: "idle_passthrough",
                    clearsOwnedMarkedText: false
                )
            case .syncRawInputFromNativeSnapshot(let snapshot):
                syncRawBufferToNativeSnapshot(snapshot)
            case .publishLocalSuggestion:
                publishLocalSuggestion(client: client)
            }
            }
        }
        traceTurnSequence(sequence, violations: sequenceViolations)
        return sequence.handled
    }

    private func traceTurnEffect(
        _ effect: InputTurnEffect,
        sequence: InputTurnEffectSequence,
        operation: () -> Void
    ) {
        let isTurnTraceEnabled = InputDebugDiagnostics.isEnabled(.turn)
        guard isTurnTraceEnabled || latencyTracer.isEnabled else {
            operation()
            return
        }
        let stage = "turn_effect.\(effect.privacySafeName)"
        let fields = turnTraceFields(for: sequence)
        guard !isTurnTraceEnabled else {
            InputDebugDiagnostics.trace(
                category: .turn,
                stage: stage,
                fields: fields,
                operation: operation
            )
            return
        }
        latencyTracer.trace(
            stage,
            fields: fields
        ) {
            operation()
        }
    }

    private func traceTurnSequence(
        _ sequence: InputTurnEffectSequence,
        violations: [InputTurnSequenceViolation]
    ) {
        guard InputDebugDiagnostics.isEnabled(.turn) || !violations.isEmpty else {
            return
        }
        let effects = sequence.effects.map(\.privacySafeName).joined(separator: ",")
        let violationText = violations.isEmpty
            ? "none"
            : violations.map(\.description).joined(separator: ";")
        var fields = turnTraceFields(for: sequence)
        fields.insert(.init(.stage, "sequence.\(sequence.token.kind.rawValue)"), at: 0)
        fields.append(.init(.reason, "effects=\(effects);violations=\(violationText)"))
        InputDebugDiagnostics.emit(
            category: .turn,
            fields: fields,
            force: !violations.isEmpty
        )
    }

    private func turnTraceFields(for sequence: InputTurnEffectSequence) -> [InputDebugDiagnostics.Field] {
        [
            .init(.turnID, sequence.token.turnID),
            .init(.compositionID, sequence.token.compositionID),
            .init(.rawRevision, sequence.token.rawRevision),
            .init(.rawLength, sequence.token.rawLength),
            .init(.handled, sequence.handled),
            .init(.panelGeneration, candidatePanelPublicationRuntime.currentPresentationGeneration)
        ]
    }

    private func turnClient(
        for scope: InputTurnClientScope,
        providedClient client: InputControllerClient?
    ) -> InputControllerClient? {
        switch scope {
        case .provided:
            return client
        case .effective:
            return client ?? host?.currentClient
        }
    }

    private func beginCompositionIfNeeded(client: InputControllerClient?) {
        let beginPlan = compositionLifecycleRuntime.beginPlan(compositionSnapshot: compositionState)
        guard beginPlan.shouldBegin else {
            return
        }

        if beginPlan.shouldTraceFirstCompositionBegin {
            traceStartupEvent(
                "first_composition_begin",
                details: "bundle=\(appBundleIdentifier(client: client) ?? "<unknown>")"
            )
        }
        if let feedbackCancellationReason = beginPlan.feedbackCancellationReason,
           !aiAcceptanceRuntime.preserveFeedbackForReplacementComposition(client: client) {
            aiAcceptanceRuntime.cancelFeedback(reason: feedbackCancellationReason)
        }
        if beginPlan.shouldReloadPreferences {
            reloadInputModePreferencesIfNeeded()
            reloadRuntimePreferencesIfNeeded()
        }
        if beginPlan.shouldReloadRuntimeLexicon {
            reloadRuntimeLexiconEngineIfNeeded()
        }
        let beginResult = activeSessionRuntime.beginTextCompositionIfNeeded()
        if beginPlan.shouldPublishCompositionStarted {
            publishRuntimeEvent(
                .compositionStarted(
                    compositionID: beginResult.snapshot.compositionID,
                    rawRevision: beginResult.snapshot.rawRevision
                )
            )
        }
        if beginPlan.shouldResetAnchor {
            anchorResolver.reset()
        }
    }

    private func reloadInputModePreferencesIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastInputModePreferenceReload) >= Self.preferenceReloadInterval else {
            return
        }
        lastInputModePreferenceReload = now
        let globalSymbolWidth = inputModePreferenceStore.loadPreferences().globalSymbolWidth
        guard globalSymbolWidth != loadedGlobalSymbolWidth else {
            return
        }
        loadedGlobalSymbolWidth = globalSymbolWidth
        let transition = inputModeStateRuntime.synchronizeConfiguredSymbolWidth(globalSymbolWidth)
        inputModeSnapshot = transition.current
        conversionEngine.synchronizeInputMode(inputModeSnapshot)
        guard transition.didChange else {
            return
        }
        resetPunctuationSessionContext()
        if let plan = activeSessionRuntime.transition(for: .inputModeGenerationChanged) {
            _ = executeActiveSymbolTransitionPlan(
                plan,
                client: host?.currentClient,
                hideReason: .compositionEnded
            )
        }
    }

    private func synchronizeInputModeSnapshot(client: InputControllerClient?) {
        let latest = inputModeStateRuntime.currentSnapshot()
        guard latest.generation != inputModeSnapshot.generation else {
            return
        }
        inputModeSnapshot = latest
        conversionEngine.synchronizeInputMode(inputModeSnapshot)
        resetPunctuationSessionContext()
        if let plan = activeSessionRuntime.transition(for: .inputModeGenerationChanged) {
            _ = executeActiveSymbolTransitionPlan(
                plan,
                client: client,
                hideReason: .compositionEnded
            )
        }
    }

    private func applyInputModeTransition(_ event: InputModeTransitionEvent) {
        let transition = inputModeStateRuntime.transition(event)
        inputModeSnapshot = transition.current
        conversionEngine.synchronizeInputMode(inputModeSnapshot)
        if transition.didChange {
            resetPunctuationSessionContext()
        }
    }

    private func resetPunctuationSessionContext() {
        punctuatorRuntime.resetPairingState()
        punctuationContextResolver.invalidate()
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
        invalidateSuggestion(reason: "runtime_preferences_changed")
        return true
    }

    private func reloadRuntimeLexiconEngineIfNeeded() {
        // Rime is the only product conversion engine. Avoid rebuilding the
        // retired local lexicon on the IMK key path.
    }

    private func resetAnchorState() {
        activeSessionRuntime.incrementCompositionIDForAnchorReset()
        anchorResolver.reset()
    }

    private func invalidateSuggestion(reason: String = "composition_invalidated") {
        suggestionStateRuntime.invalidate()
        nativeCandidateNavigationRuntime.clearSelectedCandidate()
        aiRecommendationState = aiRecommendationRuntime.reset(
            compositionID: compositionID,
            rawLength: rawBuffer.count,
            reason: reason
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

    private func publishPanelOverlay(
        modeStatusText: String?,
        symbolCandidates: [InputSymbolCandidate],
        preferredSelection: CandidatePanelSelection?,
        pageSize: Int? = nil,
        client: InputControllerClient?
    ) {
        let result = candidatePanelPublicationRuntime.publishOverlay(
            request: InputCandidatePanelOverlayRequest(
                rawInput: rawBuffer,
                compositionID: compositionID,
                rawRevision: rawRevision,
                anchorResult: candidateAnchorResult(client: client),
                placementPreference: candidatePanelPlacementPreference(client: client),
                preeditDisplayText: rawBuffer.isEmpty ? nil : candidatePanelPreeditDisplayText(client: client),
                modeStatusText: modeStatusText,
                symbolCandidates: symbolCandidates,
                pageSize: pageSize ?? runtimePreferences.effectiveCandidatePageSize,
                layoutMode: runtimePreferences.candidateLayoutMode,
                preferredSelection: preferredSelection
            ),
            locale: locale
        )
        applyCandidatePanelPublicationResult(result)
    }

    private func showModeStatus(client: InputControllerClient?) {
        modeStatusText = modeStatusDescription(for: inputModeSnapshot.state)
        if hasActiveTextComposition() {
            updateCandidatePanelImmediately(
                suggestion: suggestionStateRuntime.currentSnapshot().suggestion,
                client: client
            )
        } else {
            publishPanelOverlay(
                modeStatusText: modeStatusText,
                symbolCandidates: [],
                preferredSelection: nil,
                client: client
            )
        }
        scheduleModeStatusClear(client: client)
    }

    private func scheduleModeStatusClear(client: InputControllerClient?) {
        let visibleStatus = modeStatusText
        let task = Task { @MainActor [weak self, weak client] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self,
                  !Task.isCancelled,
                  self.modeStatusText == visibleStatus else {
                return
            }
            let effectiveClient = self.host?.currentClient ?? client
            self.modeStatusText = nil
            if self.hasActiveTextComposition() {
                self.updateCandidatePanelImmediately(
                    suggestion: self.suggestionStateRuntime.currentSnapshot().suggestion,
                    client: effectiveClient
                )
            } else if self.activeSessionRuntime.currentSymbolComposition != nil {
                self.publishCurrentSymbolComposition(client: effectiveClient)
            } else {
                self.hideCandidatePanel(reason: .compositionEnded)
            }
        }
        taskSupervisor.replace(.modeStatusClear, with: task)
    }

    private func clearTransientModeStatusBeforeUserInputIfNeeded(_ intent: InputKeyIntent) {
        guard modeStatusText != nil,
              intent.clearsTransientModeStatus else {
            return
        }
        taskSupervisor.cancel(.modeStatusClear)
        modeStatusText = nil
        let hadVisiblePanel = candidatePanelPublicationRuntime.state.windowState.isVisible
        let shouldReplayCurrentPanelFrame = intent.replaysCurrentPanelFrameAfterClearingModeStatus
            && (hasActiveTextComposition() || activeSessionRuntime.currentSymbolComposition != nil)
        if candidatePanelPublicationRuntime.clearModeStatusText(),
           hadVisiblePanel,
           shouldReplayCurrentPanelFrame {
            candidatePanelPublicationRuntime.applyCurrentFrame(
                reason: .compositionActive,
                compositionID: compositionID,
                rawRevision: rawRevision,
                rawLength: rawBuffer.count,
                locale: locale
            )
        }
        if intent.hidesModeStatusWhenNoReplacementFrame,
           hadVisiblePanel,
           !hasActiveTextComposition(),
           activeSessionRuntime.currentSymbolComposition == nil {
            hideCandidatePanel(reason: .compositionEnded)
        }
    }

    private func hideCandidatePanelIfVisible(reason: CandidatePanelVisibilityReason) {
        guard candidatePanelPublicationRuntime.state.windowState.isVisible else {
            return
        }
        hideCandidatePanel(reason: reason)
    }

    private func modeStatusDescription(for state: InputModeState) -> String {
        let textMode = state.textMode == .chinese ? "中" : "英"
        let punctuationMode = state.punctuationMode == .chinese ? "中文标点" : "英文标点"
        let width = state.symbolWidth == .halfWidth ? "半角" : "全角"
        return "\(textMode) · \(punctuationMode) · \(width)"
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
            lastSuggestionRawInput: suggestionStateRuntime.currentSnapshot().rawInput,
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
            modeStatusText: modeStatusText,
            symbolCandidates: [],
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
            rawLength: rawBuffer.count,
            locale: locale
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
        InputDebugDiagnostics.emit(
            category: .panel,
            fields: [
                .init(.stage, "lifecycle_cleanup"),
                .init(.reason, reason.rawValue),
                .init(.compositionID, compositionID),
                .init(.rawRevision, rawRevision),
                .init(.rawLength, rawBuffer.count),
                .init(.panelGeneration, candidatePanelPublicationRuntime.currentPresentationGeneration)
            ]
        )
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

    private func refreshComposition(client: InputControllerClient?) {
        let didWriteMarkedText = latencyTracer.trace("refresh_composition") {
            inputClientCompositionWriter.refreshComposition(
                client: client,
                state: writeState(),
                markedDisplayText: nativeMarkedText() ?? compositionBuffer.displayText
            )
        }
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
                self.updateCandidatePanelImmediately(
                    suggestion: self.suggestionStateRuntime.currentSnapshot().suggestion,
                    client: client
                )
            }
        )
    }

    private static let textOnlyKeyCode = -1
    private static let maxUserSelectionHistory = 64
    private static let leadingFullCandidateCount = 5
    private static let preferenceReloadInterval: TimeInterval = 1

    private func traceStartupEvent(_ event: String, details: String = "") {
        Self.traceStartupEvent(event: event, details: details, startedAt: startupDebugStartedAt)
    }

    private static func traceStartupEvent(event: String, details: String, startedAt: Date) {
        let elapsedMs = Date().timeIntervalSince(startedAt) * 1_000
        let formattedElapsed = String(format: "%.1f", elapsedMs)
        var fields: [InputDebugDiagnostics.Field] = [
            .init(.stage, event),
            .init(.elapsedMs, formattedElapsed)
        ]
        if !details.isEmpty {
            fields.append(.init(.reason, details))
        }
        InputDebugDiagnostics.emit(category: .startup, fields: fields)
    }

    private static func isDirectPassthroughDigitText(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 48 && scalar.value <= 57
        }
    }
}

private extension InputKeyIntent {
    var clearsTransientModeStatus: Bool {
        switch self {
        case .modifierFlagsChanged, .hostShortcut, .ignored:
            return false
        case .action(.toggleSymbolMode), .action(.toggleTextMode), .action(.toggleSymbolWidth):
            return false
        default:
            return true
        }
    }

    var hidesModeStatusWhenNoReplacementFrame: Bool {
        switch self {
        case .deleteBackward, .cancelComposition, .moveCandidateSelection:
            return true
        case .action(.space), .action(.tab), .action(.optionNumber), .action(.commitRaw):
            return true
        default:
            return false
        }
    }

    var replaysCurrentPanelFrameAfterClearingModeStatus: Bool {
        switch self {
        case .moveCandidateSelection:
            return true
        case .action(.tab), .action(.optionNumber):
            return true
        default:
            return false
        }
    }
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
