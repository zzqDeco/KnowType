import CoreGraphics
import Foundation
import KnowTypeAI
import KnowTypeCore
import KnowTypeProviders

final class InputControllerCoordinator: @unchecked Sendable {
    private let provider: (any LLMProvider)?
    private var sessionController: InputSessionController
    private let hasProvider: Bool
    private var conversionEngine: any KnowTypeConversionEngine
    private let keyMapper = InputKeyCommandMapper()
    private let symbolTransformer = InputSymbolTransformer()
    private let candidateListBuilder = InputCandidateListBuilder()
    private let anchorResolver: CandidateAnchorResolver
    private weak var host: InputControllerHost?
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
    private let aiContextEventRecorder: (any AIContextEventRecording)?
    private var aiRecommendationTask: Task<Void, Never>?
    private var aiRecommendationState: AIRecommendationState = .idle
    private var aiRecommendationGeneration = 0
    private var deleteCountBeforeCommit = 0
    private var recentLexicalCommits: [String] = []
    private var recentLexicalSelections: [String] = []
    private let lexicalContextBuilder = LexicalContextBuilder()
    private let taskSupervisor = InputTaskSupervisor()
    private let latencyTracer = InputLatencyTracer()
    private var lastInputModePreferenceReload = Date.distantPast
    private var lastRuntimePreferenceReload = Date.distantPast

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
        aiContextEventRecorder: (any AIContextEventRecording)? = nil,
        conversionEngine: (any KnowTypeConversionEngine)? = nil,
        conversionEngineFactory: (@Sendable (TraditionalInputEngine?) -> any KnowTypeConversionEngine)? = nil,
        host: InputControllerHost,
        anchorResolver: CandidateAnchorResolver,
        enablesAsyncSuggestionRefresh: Bool = true,
        asyncSuggestionDelayNanoseconds: UInt64 = 0
    ) {
        let inputModePreferences = inputModePreferenceStore.loadPreferences()
        let runtimePreferences = initialRuntimePreferences ?? runtimePreferenceStore.loadPreferences()
        self.provider = provider
        self.hasProvider = provider != nil
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
        self.aiContextEventRecorder = aiContextEventRecorder
        self.host = host
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
        latencyTracer.trace("handle-key") {
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
        host?.updateCandidatePanel(state: candidatePanelState, locale: locale)
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
        _ = applyCommitResult(result, client: client)
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
        if conversionEngine.isNativeActive,
           conversionEngine.snapshot.hasComposition {
            let result = conversionEngine.process(.commitComposition)
            if handleNativeConversionResult(result, client: client) {
                return
            }
        }
        let text = compositionBuffer.hasResolvedSegments ? compositionBuffer.commitText : rawBuffer
        _ = applyCommitResult(text.isEmpty ? .noAction : .commit(text), client: client)
    }

    func hidePalettes() {
        hideCandidatePanel()
    }

    func deactivateServer() {
        flushUserSelectionHistory()
        resetAnchorState()
    }

    func inputControllerWillClose() {
        flushUserSelectionHistory()
        aiRecommendationTask?.cancel()
        panelUpdateTask?.cancel()
        taskSupervisor.cancelAll()
        hideCandidatePanel()
    }

    private func handle(intent: InputKeyIntent, client: InputControllerClient?) -> Bool {
        switch intent {
        case .append(let text):
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
            }
            guard let symbol = symbolTransformer.text(for: text, state: inputModeRuntime.state) else {
                return appendComposition(text, client: client)
            }
            return commitSymbol(symbol, client: client)
        case .deleteBackward:
            guard !rawBuffer.isEmpty else {
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
            return commit(action: action, client: client)
        case .cancelComposition:
            guard !rawBuffer.isEmpty else {
                return false
            }
            resetComposition()
            refreshComposition(client: client)
            return true
        case .selectCandidate(let number):
            if conversionEngine.isNativeActive,
               !rawBuffer.isEmpty,
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
                    return applyCommitResult(result, client: client)
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

    private func resolvedCompositionFallbackContinuations(
        lockedPrefixText: String,
        rawInput: String,
        client: InputControllerClient?
    ) -> [ContinuationCandidate] {
        guard !hasProvider,
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

    private func lexicalContextSnapshot(for suggestion: SuggestionResponse) -> LexicalContextSnapshot? {
        lexicalContextBuilder.snapshot(
            rimeCandidates: suggestion.prefixCandidates.map(\.text),
            recentCommits: recentLexicalCommits,
            selectionHistory: recentLexicalSelections
        )
    }

    private func scheduleAIRecommendation(for suggestion: SuggestionResponse, client: InputControllerClient?) {
        aiRecommendationTask?.cancel()
        taskSupervisor.cancel(.aiRecommendation)
        aiRecommendationGeneration += 1
        let generation = aiRecommendationGeneration

        guard let firstPrefix = suggestion.prefixCandidates.first,
              !isPartialSegmentCandidate(firstPrefix),
              !compositionBuffer.hasResolvedSegments || compositionBuffer.isFullyResolved else {
            aiRecommendationState = .idle
            updateCandidatePanel(suggestion: suggestion, client: client)
            return
        }

        let currentAppBundleID = appBundleIdentifier(client: client)
        guard !TextProtection.requiresNoCorrection(rawBuffer, appBundleID: currentAppBundleID),
              !TextProtection.requiresNoCorrection(firstPrefix.text, appBundleID: currentAppBundleID) else {
            aiRecommendationState = .idle
            updateCandidatePanel(suggestion: suggestion, client: client)
            return
        }

        guard runtimePreferences.cloudContinuationEnabled else {
            aiRecommendationState = .ineligible(reason: "AI 已关闭")
            updateCandidatePanel(suggestion: suggestion, client: client)
            return
        }

        guard hasProvider else {
            aiRecommendationState = aiRecommendationProvider == nil
                ? .idle
                : .unavailable(reason: "AI 未配置")
            updateCandidatePanel(suggestion: suggestion, client: client)
            return
        }

        guard let aiRecommendationProvider else {
            aiRecommendationState = .idle
            updateCandidatePanel(suggestion: suggestion, client: client)
            return
        }

        let requestID = UUID()
        let rawInput = rawBuffer
        let currentCompositionID = compositionID
        let request = AIRecommendationRequest(
            rawInput: rawInput,
            traditionalCandidate: firstPrefix,
            appBundleID: currentAppBundleID,
            appName: currentAppBundleID,
            locale: locale,
            compositionID: currentCompositionID,
            lexicalContext: lexicalContextSnapshot(for: suggestion)
        )
        aiRecommendationState = .pending(requestID: requestID)
        updateCandidatePanel(suggestion: suggestion, client: client)
        let task = Task.detached(priority: .utility) { [weak self, aiRecommendationProvider] in
            let state = await aiRecommendationProvider.recommendation(for: request)
            guard !Task.isCancelled else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self,
                      self.aiRecommendationGeneration == generation,
                      self.rawBuffer == rawInput,
                      self.compositionID == currentCompositionID else {
                    return
                }
                self.aiRecommendationState = state
                self.updateCandidatePanel(suggestion: self.lastSuggestion, client: self.host?.currentClient)
            }
        }
        aiRecommendationTask = task
        taskSupervisor.replace(.aiRecommendation, with: task)
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
           conversionEngine.isNativeActive,
           rawBuffer.isEmpty == false {
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
        return applyCommitResult(result, client: client)
    }

    @discardableResult
    private func applyCommitResult(_ result: InputCommitResult, client: InputControllerClient?) -> Bool {
        switch InputCommitResultPolicy.directive(for: result) {
        case .insertAndReset(let text):
            recordTypingCommit(text, client: client)
            insert(text, client: client)
            resetComposition()
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
        syncRawBufferToNativeSnapshot(result.snapshot)
        publishLocalSuggestion(client: client)
        return true
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
        recordLexicalSelection(trimmed)
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
        if action == .tab,
           aiRecommendationState.isSelectableRecommendation {
            return aiRecommendationCommitResult()
        }
        if case .optionNumber(1) = action,
           aiRecommendationState.isSelectableRecommendation {
            return aiRecommendationCommitResult()
        }
        if action == .tab,
           case .pending = aiRecommendationState {
            return .noAction
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
            case .optionNumber, .toggleSymbolMode, .commitRaw:
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
        client?.insertText(text, replacementRange: replacementRangeForCommit(client))
    }

    private func recordTypingCommit(_ text: String, client: InputControllerClient?) {
        let appBundleID = appBundleIdentifier(client: client)
        guard !TextProtection.requiresNoCorrection(text, appBundleID: appBundleID),
              !TextProtection.requiresNoCorrection(rawBuffer, appBundleID: appBundleID) else {
            return
        }
        recordLexicalCommit(text)
        guard let aiContextEventRecorder,
              hasProvider,
              runtimePreferences.cloudContinuationEnabled,
              !text.isEmpty else {
            return
        }
        let event = AITypingEvent(
            appBundleID: appBundleIdentifier(client: client),
            appName: appBundleIdentifier(client: client),
            rawInput: rawBuffer.isEmpty ? nil : rawBuffer,
            committedText: text,
            commitKind: typingCommitKind(for: text),
            candidateSource: typingCandidateSource(for: text),
            deleteCountBeforeCommit: deleteCountBeforeCommit
        )
        Task.detached(priority: .utility) { [aiContextEventRecorder] in
            await aiContextEventRecorder.record(event)
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
    }

    private func recordExternalDelete(client: InputControllerClient?) {
        guard let aiContextEventRecorder,
              hasProvider,
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
        if case .ready(let candidate) = aiRecommendationState,
           candidate.displayText == text {
            return .ai
        }
        if text == rawBuffer {
            return .raw
        }
        if rawBuffer.isEmpty {
            return .symbol
        }
        return .traditional
    }

    private func typingCandidateSource(for text: String) -> String {
        if case .ready(let candidate) = aiRecommendationState,
           candidate.displayText == text {
            return "ai:\(candidate.provider)"
        }
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

    private func resetComposition() {
        rawBuffer = ""
        conversionEngine.reset()
        compositionBuffer = CompositionBuffer()
        rawRevision += 1
        deleteCountBeforeCommit = 0
        resetAnchorState()
        invalidateSuggestion()
        hideCandidatePanel()
    }

    private func beginCompositionIfNeeded(client: InputControllerClient?) {
        if rawBuffer.isEmpty {
            reloadInputModeDefaultsIfNeeded(client: client)
            reloadRuntimePreferencesIfNeeded()
            reloadRuntimeLexiconEngineIfNeeded()
            compositionBuffer = CompositionBuffer()
            compositionID += 1
            anchorResolver.reset()
        }
    }

    private func reloadInputModeDefaultsIfNeeded(client: InputControllerClient?) {
        let now = Date()
        guard now.timeIntervalSince(lastInputModePreferenceReload) >= Self.preferenceReloadInterval else {
            return
        }
        lastInputModePreferenceReload = now
        inputModeRuntime.reloadIfChanged(
            preferences: inputModePreferenceStore.loadPreferences(),
            appBundleID: appBundleIdentifier(client: client)
        )
    }

    private func reloadRuntimePreferencesIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastRuntimePreferenceReload) >= Self.preferenceReloadInterval else {
            return
        }
        lastRuntimePreferenceReload = now
        let preferences = runtimePreferenceStore.loadPreferences()
        guard preferences != runtimePreferences else {
            return
        }
        runtimePreferences = preferences
        sessionController = Self.polishOnlySessionController()
        invalidateSuggestion()
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
        aiRecommendationGeneration += 1
        aiRecommendationTask?.cancel()
        aiRecommendationTask = nil
        taskSupervisor.cancel(.aiRecommendation)
        aiRecommendationState = .idle
    }

    private func updateCandidatePanelImmediately(suggestion: SuggestionResponse?, client: InputControllerClient?) {
        panelUpdateGeneration += 1
        panelUpdateTask?.cancel()
        panelUpdateTask = nil
        taskSupervisor.cancel(.panelRender)
        guard !rawBuffer.isEmpty || suggestion != nil else {
            hideCandidatePanel()
            return
        }
        updateCandidatePanel(suggestion: suggestion, anchorResult: candidateAnchorResult(client: client))
    }

    private func updateCandidatePanel(suggestion: SuggestionResponse?, client: InputControllerClient?) {
        guard !rawBuffer.isEmpty || suggestion != nil else {
            hideCandidatePanel()
            return
        }
        guard enablesAsyncSuggestionRefresh else {
            updateCandidatePanel(suggestion: suggestion, anchorResult: candidateAnchorResult(client: client))
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
                anchorResult: self.candidateAnchorResult(client: client)
            )
        }
        panelUpdateTask = task
        taskSupervisor.replace(.panelRender, with: task)
    }

    private func updateCandidatePanel(suggestion: SuggestionResponse?, anchorResult: CandidateAnchorResult) {
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
        host?.updateCandidatePanel(state: candidatePanelState, locale: locale)
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

    private func hideCandidatePanel() {
        panelUpdateGeneration += 1
        panelUpdateTask?.cancel()
        panelUpdateTask = nil
        taskSupervisor.cancel(.panelRender)
        candidatePanelState.hide()
        selectedNativeCandidate = nil
        anchorResolver.reset()
        host?.hideCandidatePanel()
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
        guard let client else {
            host?.updateComposition()
            return
        }

        let markedText = nativeMarkedText() ?? compositionBuffer.displayText
        guard !markedText.isEmpty else {
            clearMarkedText(client)
            return
        }

        let replacement = activeMarkedRange(for: client) ?? NSRange(location: NSNotFound, length: NSNotFound)
        client.setMarkedText(
            markedText,
            selectionRange: NSRange(location: (markedText as NSString).length, length: 0),
            replacementRange: replacement
        )
        scheduleDelayedCandidateReanchor(
            client: client,
            rawInput: rawBuffer,
            compositionID: compositionID
        )
    }

    private func clearMarkedText(_ client: InputControllerClient) {
        guard let markedRange = activeMarkedRange(for: client) else {
            host?.updateComposition()
            return
        }
        client.setMarkedText(
            "",
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: markedRange
        )
    }

    private func replacementRangeForCommit(_ client: InputControllerClient?) -> NSRange {
        client.flatMap(activeMarkedRange(for:)) ?? NSRange(location: NSNotFound, length: NSNotFound)
    }

    private func activeMarkedRange(for client: InputControllerClient) -> NSRange? {
        client.markedRange
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
                anchorResult: self.candidateAnchorResult(client: client)
            )
        }
    }

    private static let textOnlyKeyCode = -1
    private static let maxUserSelectionHistory = 64
    private static let maxRecentLexicalCommits = 32
    private static let leadingFullCandidateCount = 5
    private static let preferenceReloadInterval: TimeInterval = 1
}

private extension Collection {
    subscript(inputControllerSafe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
