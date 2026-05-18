import CoreGraphics
import Foundation
import KnowTypeCore
import KnowTypeProviders

final class InputControllerCoordinator: @unchecked Sendable {
    private let provider: (any LLMProvider)?
    private var sessionController: InputSessionController
    private let hasProvider: Bool
    private var traditionalInputEngine: TraditionalInputEngine
    private var lexiconRuntimeSnapshot: InputMethodLexiconRuntimeSnapshot
    private let lexiconRuntime: InputMethodLexiconRuntime
    private let keyMapper = InputKeyCommandMapper()
    private let symbolTransformer = InputSymbolTransformer()
    private let candidateListBuilder = InputCandidateListBuilder()
    private let anchorResolver: CandidateAnchorResolver
    private weak var host: InputControllerHost?
    private var rawBuffer = ""
    private var compositionBuffer = CompositionBuffer()
    private var compositionID = 0
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
    private var suggestionGeneration = 0
    private var runtimeReloadGeneration = 0
    private var runtimeReloadTask: Task<Void, Never>?

    init(
        provider: (any LLMProvider)?,
        traditionalInputEngine: TraditionalInputEngine,
        lexiconRuntimeSnapshot: InputMethodLexiconRuntimeSnapshot,
        lexiconRuntime: InputMethodLexiconRuntime = .defaultRuntime(),
        inputModePreferenceStore: any InputModePreferenceStore,
        runtimePreferenceStore: any InputMethodRuntimePreferenceStore = UserDefaultsInputMethodRuntimePreferenceStore.defaultStore(),
        initialRuntimePreferences: InputMethodRuntimePreferences? = nil,
        initialAppBundleID: String?,
        userSelectionHistoryPersistence: (any InputControllerUserSelectionHistoryPersisting)?,
        host: InputControllerHost,
        anchorResolver: CandidateAnchorResolver,
        enablesAsyncSuggestionRefresh: Bool = true
    ) {
        let inputModePreferences = inputModePreferenceStore.loadPreferences()
        let runtimePreferences = initialRuntimePreferences ?? runtimePreferenceStore.loadPreferences()
        self.provider = provider
        self.hasProvider = provider != nil
        self.traditionalInputEngine = traditionalInputEngine
        self.lexiconRuntimeSnapshot = lexiconRuntimeSnapshot
        self.lexiconRuntime = lexiconRuntime
        self.sessionController = InputSessionController(
            provider: provider,
            traditionalInputEngine: traditionalInputEngine,
            runtimePreferences: runtimePreferences
        )
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
        self.host = host
        self.anchorResolver = anchorResolver
        self.enablesAsyncSuggestionRefresh = enablesAsyncSuggestionRefresh
        if enablesAsyncSuggestionRefresh {
            scheduleRuntimeLexiconReloadIfNeeded()
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
        handle(intent: keyMapper.intent(for: stroke), client: client)
    }

    func composedString() -> Any {
        compositionBuffer.displayText
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
    }

    func candidateSelected(_ text: String?, client: InputControllerClient?) {
        selectNativeCandidate(matching: text)
        commit(action: .space, client: client)
    }

    func commitComposition(client: InputControllerClient?) {
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
        runtimeReloadGeneration += 1
        runtimeReloadTask?.cancel()
        hideCandidatePanel()
    }

    private func handle(intent: InputKeyIntent, client: InputControllerClient?) -> Bool {
        switch intent {
        case .append(let text):
            return appendComposition(text, client: client)
        case .symbol(let text):
            if rawBuffer.isEmpty {
                reloadInputModeDefaultsIfNeeded(client: client)
            }
            guard let symbol = symbolTransformer.text(for: text, state: inputModeRuntime.state) else {
                return appendComposition(text, client: client)
            }
            return commitSymbol(symbol, client: client)
        case .deleteBackward:
            guard !rawBuffer.isEmpty else {
                return false
            }
            if !compositionBuffer.undoLastResolvedSegment() {
                rawBuffer.removeLast()
                compositionBuffer.updateRawInput(rawBuffer)
                if rawBuffer.isEmpty {
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
                    let result = resultForNumberSelection(inputSelection, client: client)
                    learnSelectedPrefix(action: .space, result: result)
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
        compositionBuffer.updateRawInput(rawBuffer)
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
            if enablesAsyncSuggestionRefresh {
                let snapshot = compositionBuffer
                let segmentResult = applyPendingSegmentFallback(commitIfFullyResolved: true, client: client)
                if case .commit(let text) = segmentResult {
                    return applyCommitResult(.commit(text + symbol), client: client)
                }
                compositionBuffer = snapshot
            }
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
        let appBundleID = appBundleIdentifier(client: client)
        let selectionHistory = userSelectionHistory
        let currentLocale = locale
        let currentCompositionID = compositionID
        let compositionSnapshot = compositionBuffer
        let engineSnapshot = traditionalInputEngine
        let runtimePreferencesSnapshot = runtimePreferences
        let sessionController = sessionController
        suggestionGeneration += 1
        let generation = suggestionGeneration
        suggestionTask = Task { [weak self, sessionController, engineSnapshot, runtimePreferencesSnapshot, compositionSnapshot] in
            let context = InputContext(
                rawInput: rawInput,
                appBundleID: appBundleID,
                locale: currentLocale,
                userSelectionHistory: selectionHistory
            )
            let suggestion: SuggestionResponse
            if compositionSnapshot.hasResolvedSegments {
                suggestion = InputMethodPipeline.localSuggestions(
                    for: context,
                    includeFallbackContinuations: false,
                    traditionalInputEngine: engineSnapshot,
                    runtimePreferences: runtimePreferencesSnapshot
                )
            } else {
                suggestion = await sessionController.update(
                    rawInput: rawInput,
                    appBundleID: appBundleID,
                    locale: currentLocale,
                    userSelectionHistory: selectionHistory
                )
            }
            guard !Task.isCancelled else {
                return
            }
            let augmentedSuggestion = Self.augmentedSuggestion(
                suggestion,
                compositionBuffer: compositionSnapshot,
                rawBuffer: rawInput,
                locale: currentLocale,
                traditionalInputEngine: engineSnapshot
            )
            guard !Task.isCancelled else {
                return
            }
            Task { @MainActor [weak self, augmentedSuggestion] in
                guard let self else {
                    return
                }
                let currentClient = self.host?.currentClient
                guard SuggestionPublicationGuard.shouldPublish(
                    requestedRawInput: rawInput,
                    currentRawInput: self.rawBuffer,
                    isCancelled: Task.isCancelled
                ),
                    self.compositionID == currentCompositionID,
                    self.compositionBuffer == compositionSnapshot,
                    self.suggestionGeneration == generation else {
                    return
                }
                self.lastSuggestion = augmentedSuggestion
                self.lastSuggestionRawInput = rawInput
                self.refreshComposition(client: currentClient)
                self.updateCandidatePanel(suggestion: augmentedSuggestion, client: currentClient)
            }
        }
    }

    private func refreshResolvedCompositionContinuations(client: InputControllerClient?) {
        guard enablesAsyncSuggestionRefresh,
              compositionBuffer.isFullyResolved else {
            return
        }
        suggestionTask?.cancel()
        let rawInput = rawBuffer
        let lockedPrefixText = compositionBuffer.commitText
        let appBundleID = appBundleIdentifier(client: client)
        let currentLocale = locale
        let selectedCompositionID = compositionID
        let lockedPrefix = LockedPrefix(
            text: lockedPrefixText,
            rawInput: rawInput,
            candidateID: "composition-buffer"
        )
        let context = InputContext(
            rawInput: rawInput,
            appBundleID: appBundleID,
            locale: currentLocale,
            userSelectionHistory: userSelectionHistory
        )
        guard runtimePreferences.cloudContinuationEnabled else {
            let suggestion = resolvedCompositionSuggestion(
                lockedPrefix: lockedPrefix,
                continuations: [],
                fallbackLatency: lastSuggestion?.latencyMs ?? 0
            )
            lastSuggestion = suggestion
            lastSuggestionRawInput = rawInput
            refreshComposition(client: client)
            updateCandidatePanel(suggestion: suggestion, client: client)
            return
        }
        guard let provider else {
            let continuations = runtimePreferences.localContinuationEnabledWhenNoProvider
                ? PrefixContinuationEngine().fallbackContinuations(
                    for: lockedPrefixText,
                    lengthLevel: runtimePreferences.continuationLengthLevel,
                    maxCandidates: runtimePreferences.maxContinuationCandidates
                )
                : []
            let suggestion = resolvedCompositionSuggestion(
                lockedPrefix: lockedPrefix,
                continuations: continuations,
                fallbackLatency: lastSuggestion?.latencyMs ?? 0
            )
            lastSuggestion = suggestion
            lastSuggestionRawInput = rawInput
            refreshComposition(client: client)
            updateCandidatePanel(suggestion: suggestion, client: client)
            return
        }
        suggestionTask = Task { @MainActor [weak self, provider] in
            guard let self else {
                return
            }
            let continuations = await PrefixContinuationEngine(provider: provider).continuations(
                for: lockedPrefix,
                context: context,
                lengthLevel: self.runtimePreferences.continuationLengthLevel,
                maxCandidates: self.runtimePreferences.maxContinuationCandidates
            )
            guard !Task.isCancelled else {
                return
            }
            guard self.rawBuffer == rawInput,
                  self.compositionID == selectedCompositionID,
                  self.compositionBuffer.isFullyResolved,
                  self.compositionBuffer.commitText == lockedPrefixText else {
                return
            }
            let currentClient = self.host?.currentClient
            let suggestion = self.resolvedCompositionSuggestion(
                lockedPrefix: lockedPrefix,
                continuations: continuations,
                fallbackLatency: self.lastSuggestion?.latencyMs ?? 0
            )
            self.lastSuggestion = suggestion
            self.lastSuggestionRawInput = rawInput
            self.refreshComposition(client: currentClient)
            self.updateCandidatePanel(suggestion: suggestion, client: currentClient)
        }
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

    private func resultForNumberSelection(
        _ selection: InputCandidateSelection,
        client: InputControllerClient?
    ) -> InputCommitResult {
        switch selection.kind {
        case .segmentCandidate(let index):
            return applySegmentCandidate(at: index, commitIfFullyResolved: false, client: client)
        case .rawInput:
            return rawBuffer.isEmpty ? .noAction : .commit(rawBuffer)
        case .prefixCandidate, .fullCandidate, .continuationCandidate:
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
                locale: locale
            )
        }
    }

    private func appBundleIdentifier(client: InputControllerClient?) -> String? {
        client?.bundleIdentifier
    }

    private func publishLocalSuggestion(client: InputControllerClient?) {
        guard !enablesAsyncSuggestionRefresh else {
            publishPendingSuggestion(client: client)
            return
        }
        publishLocalSuggestionSynchronously(client: client)
    }

    private func publishPendingSuggestion(client: InputControllerClient?) {
        suggestionGeneration += 1
        suggestionTask?.cancel()
        suggestionTask = nil
        guard SuggestionRefreshPolicy.shouldRefresh(rawInput: rawBuffer) else {
            lastSuggestion = nil
            lastSuggestionRawInput = nil
            refreshComposition(client: client)
            updateCandidatePanel(suggestion: nil, client: client)
            return
        }
        lastSuggestion = nil
        lastSuggestionRawInput = nil
        selectedNativeCandidate = nil
        refreshComposition(client: client)
        updateCandidatePanel(suggestion: nil, client: client)
    }

    private func publishLocalSuggestionSynchronously(client: InputControllerClient?) {
        guard SuggestionRefreshPolicy.shouldRefresh(rawInput: rawBuffer) else {
            lastSuggestion = nil
            lastSuggestionRawInput = nil
            refreshComposition(client: client)
            updateCandidatePanel(suggestion: nil, client: client)
            return
        }

        let context = InputContext(
            rawInput: rawBuffer,
            appBundleID: appBundleIdentifier(client: client),
            locale: locale,
            userSelectionHistory: userSelectionHistory
        )
        let suggestion = InputMethodPipeline.localSuggestions(
            for: context,
            includeFallbackContinuations: !hasProvider,
            traditionalInputEngine: traditionalInputEngine,
            runtimePreferences: runtimePreferences
        )
        let augmentedSuggestion = augmentedSuggestion(suggestion)
        lastSuggestion = augmentedSuggestion
        lastSuggestionRawInput = rawBuffer
        refreshComposition(client: client)
        updateCandidatePanel(suggestion: augmentedSuggestion, client: client)
    }

    private func augmentedSuggestion(_ suggestion: SuggestionResponse) -> SuggestionResponse {
        Self.augmentedSuggestion(
            suggestion,
            compositionBuffer: compositionBuffer,
            rawBuffer: rawBuffer,
            locale: locale,
            traditionalInputEngine: traditionalInputEngine
        )
    }

    private static func augmentedSuggestion(
        _ suggestion: SuggestionResponse,
        compositionBuffer: CompositionBuffer,
        rawBuffer: String,
        locale: KnowTypeLocale,
        traditionalInputEngine: TraditionalInputEngine
    ) -> SuggestionResponse {
        var prefixCandidates: [CorrectionCandidate]
        if compositionBuffer.isFullyResolved {
            prefixCandidates = [resolvedCompositionCandidate(compositionBuffer: compositionBuffer, rawBuffer: rawBuffer)]
        } else if compositionBuffer.hasResolvedSegments {
            prefixCandidates = []
        } else {
            prefixCandidates = suggestion.prefixCandidates
        }
        if let activeRange = compositionBuffer.activeRange {
            let segmentCandidates = prioritizedSegmentCandidates(
                for: activeRange,
                compositionBuffer: compositionBuffer,
                rawBuffer: rawBuffer,
                locale: locale,
                traditionalInputEngine: traditionalInputEngine
            )
                .filter { canApplyOrCommit(candidate: $0, compositionBuffer: compositionBuffer) }
            if compositionBuffer.hasResolvedSegments {
                prefixCandidates = segmentCandidates
            } else {
                let leadingFullCandidates = Array(prefixCandidates.prefix(Self.leadingFullCandidateCount))
                let remainingFullCandidates = Array(prefixCandidates.dropFirst(Self.leadingFullCandidateCount))
                let leadingMerged = mergedPrefixCandidates(leadingFullCandidates, with: segmentCandidates)
                prefixCandidates = mergedPrefixCandidates(leadingMerged, with: remainingFullCandidates)
            }
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

    private func prioritizedSegmentCandidates(for activeRange: KnowTypeCore.TextRange) -> [CorrectionCandidate] {
        Self.prioritizedSegmentCandidates(
            for: activeRange,
            compositionBuffer: compositionBuffer,
            rawBuffer: rawBuffer,
            locale: locale,
            traditionalInputEngine: traditionalInputEngine
        )
    }

    private static func prioritizedSegmentCandidates(
        for activeRange: KnowTypeCore.TextRange,
        compositionBuffer: CompositionBuffer,
        rawBuffer: String,
        locale: KnowTypeLocale,
        traditionalInputEngine: TraditionalInputEngine
    ) -> [CorrectionCandidate] {
        let preserveCapitalizedPinyin = locale != .zhCN
        let candidates = traditionalInputEngine
            .segmentCandidates(
                for: rawBuffer,
                activeRange: activeRange,
                preserveCapitalizedPinyin: preserveCapitalizedPinyin,
                options: InputMethodPipeline.interactiveQueryOptions
            )
            .map { candidate in
                CorrectionCandidate(
                    text: candidate.text,
                    source: candidate.rawRange == compositionBuffer.rawRange
                        ? "local-full-input"
                        : "local-segment-input",
                    confidence: candidate.confidence,
                    correctionLevel: .contextual,
                    rawRange: candidate.rawRange,
                    segments: candidate.segments
                )
            }

        let grouped = Dictionary(grouping: candidates) { candidate in
            candidate.rawRange ?? KnowTypeCore.TextRange(start: 0, length: 0)
        }
        let orderedRanges = grouped.keys.sorted { lhs, rhs in
            if lhs.length == rhs.length {
                return lhs.start < rhs.start
            }
            return lhs.length > rhs.length
        }
        let sortedGroups = orderedRanges.map { range in
            (grouped[range] ?? [])
                .sorted { lhs, rhs in
                    if lhs.confidence == rhs.confidence {
                        return lhs.text < rhs.text
                    }
                    return lhs.confidence > rhs.confidence
                }
        }
        let primaryCandidates = sortedGroups.compactMap(\.first)
        let alternateCandidates = sortedGroups.flatMap { group in
            group.dropFirst().prefix(2)
        }
        return primaryCandidates + alternateCandidates
    }

    private func mergedPrefixCandidates(
        _ existingCandidates: [CorrectionCandidate],
        with additionalCandidates: [CorrectionCandidate]
    ) -> [CorrectionCandidate] {
        Self.mergedPrefixCandidates(existingCandidates, with: additionalCandidates)
    }

    private static func mergedPrefixCandidates(
        _ existingCandidates: [CorrectionCandidate],
        with additionalCandidates: [CorrectionCandidate]
    ) -> [CorrectionCandidate] {
        var merged = existingCandidates
        for candidate in additionalCandidates {
            guard !merged.contains(where: { existing in
                existing.text == candidate.text && existing.rawRange == candidate.rawRange
            }) else {
                continue
            }
            merged.append(candidate)
        }
        return merged
    }

    private func canApplyOrCommit(candidate: CorrectionCandidate) -> Bool {
        Self.canApplyOrCommit(candidate: candidate, compositionBuffer: compositionBuffer)
    }

    private static func canApplyOrCommit(
        candidate: CorrectionCandidate,
        compositionBuffer: CompositionBuffer
    ) -> Bool {
        guard candidate.rawRange != compositionBuffer.rawRange else {
            return true
        }
        var probe = compositionBuffer
        return probe.apply(candidate)
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
        let result = commitResult(for: action, client: client)
        learnSelectedPrefix(action: action, result: result)
        return applyCommitResult(result, client: client)
    }

    @discardableResult
    private func applyCommitResult(_ result: InputCommitResult, client: InputControllerClient?) -> Bool {
        switch InputCommitResultPolicy.directive(for: result) {
        case .insertAndReset(let text):
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

    private func learnSelectedPrefix(action: InputAction, result: InputCommitResult) {
        guard case .commit(let committedText) = result,
              !committedText.isEmpty,
              action != .optionR,
              let prefix = selectedPrefixTextForLearning(),
              prefix != rawBuffer,
              committedText.hasPrefix(prefix) else {
            return
        }
        recordUserSelection(prefix)
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
            case .continuationCandidate:
                return lastSuggestion?.prefixCandidates.first?.text
            }
        }

        switch candidatePanelState.windowState.selection {
        case .prefixCandidate(let index), .fullCandidate(let index):
            return lastSuggestion?.prefixCandidates[inputControllerSafe: index]?.text
        case .segmentCandidate:
            return nil
        case .continuationCandidate:
            return lastSuggestion?.prefixCandidates.first?.text
        case .rawInput, .none:
            return lastSuggestion?.prefixCandidates.first?.text
        }
    }

    private func recordUserSelection(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
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
           compositionBuffer.hasResolvedSegments,
           !compositionBuffer.isFullyResolved {
            return .noAction
        }
        if action == .tab,
           let selectedNativeCandidate,
           case .segmentCandidate = selectedNativeCandidate.kind {
            return .noAction
        }
        if compositionBuffer.hasResolvedSegments,
           compositionBuffer.isFullyResolved {
            if let selectedNativeCandidate,
               case .continuationCandidate(let index) = selectedNativeCandidate.kind,
               (action == .space || action == .tab),
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
                return InputCompositionController().handle(
                    action: .tab,
                    prefixCandidates: [
                        CorrectionCandidate(
                            text: compositionBuffer.commitText,
                            source: "composition-buffer",
                            confidence: 1.0,
                            correctionLevel: .light,
                            rawRange: compositionBuffer.rawRange,
                            segments: compositionBuffer.resolvedSegments
                        )
                    ],
                    continuationCandidates: lastSuggestion?.continuationCandidates ?? [],
                    originalText: rawBuffer
                )
            case .optionR:
                return .polishRequested(compositionBuffer.commitText)
            case .optionNumber, .toggleSymbolMode, .commitRaw:
                break
            }
        }
        if let selectedNativeCandidate,
           case .segmentCandidate(let index) = selectedNativeCandidate.kind,
           action == .space {
            return applySegmentCandidate(at: index, commitIfFullyResolved: true, client: client)
        }
        if case .optionNumber = action,
           !candidatePanelState.windowState.isVisible {
            return .noAction
        }
        if action == .space,
           enablesAsyncSuggestionRefresh,
           compositionBuffer.hasResolvedSegments,
           !compositionBuffer.isFullyResolved,
           !SuggestionPublicationGuard.hasCurrentSuggestion(
                suggestionRawInput: lastSuggestionRawInput,
                currentRawInput: rawBuffer
           ) {
            return applyPendingSegmentFallback(commitIfFullyResolved: true, client: client)
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
            traditionalInputEngine: traditionalInputEngine,
            runtimePreferences: runtimePreferences,
            allowsSynchronousFallback: !enablesAsyncSuggestionRefresh
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
              action == .space || action == .tab,
              SuggestionRefreshPolicy.shouldRefresh(rawInput: rawBuffer) else {
            return (lastSuggestion, lastSuggestionRawInput, false)
        }

        let context = InputContext(
            rawInput: rawBuffer,
            appBundleID: appBundleIdentifier(client: client),
            locale: locale,
            userSelectionHistory: userSelectionHistory
        )
        let suggestion = InputMethodPipeline.localSuggestions(
            for: context,
            includeFallbackContinuations: action == .tab,
            traditionalInputEngine: traditionalInputEngine,
            runtimePreferences: runtimePreferences
        )
        return (augmentedSuggestion(suggestion), rawBuffer, true)
    }

    private func applyPendingSegmentFallback(
        commitIfFullyResolved: Bool,
        client: InputControllerClient?
    ) -> InputCommitResult {
        guard let activeRange = compositionBuffer.activeRange else {
            return .noAction
        }
        guard let candidate = prioritizedSegmentCandidates(for: activeRange)
            .first(where: { candidate in
                candidate.rawRange != compositionBuffer.rawRange
                    && canApplyOrCommit(candidate: candidate)
            }) else {
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

    private func resetComposition() {
        rawBuffer = ""
        compositionBuffer = CompositionBuffer()
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
        inputModeRuntime.reloadIfChanged(
            preferences: inputModePreferenceStore.loadPreferences(),
            appBundleID: appBundleIdentifier(client: client)
        )
    }

    private func reloadRuntimePreferencesIfNeeded() {
        let preferences = runtimePreferenceStore.loadPreferences()
        guard preferences != runtimePreferences else {
            return
        }
        runtimePreferences = preferences
        sessionController = InputSessionController(
            provider: provider,
            traditionalInputEngine: traditionalInputEngine,
            runtimePreferences: runtimePreferences
        )
        invalidateSuggestion()
    }

    private func reloadRuntimeLexiconEngineIfNeeded() {
        guard !enablesAsyncSuggestionRefresh else {
            scheduleRuntimeLexiconReloadIfNeeded()
            return
        }
        let snapshot = lexiconRuntime.snapshot(scheme: runtimePreferences.inputScheme)
        guard snapshot != lexiconRuntimeSnapshot else {
            return
        }

        traditionalInputEngine = lexiconRuntime.makeEngine(scheme: runtimePreferences.inputScheme)
        lexiconRuntimeSnapshot = snapshot
        sessionController = InputSessionController(
            provider: provider,
            traditionalInputEngine: traditionalInputEngine,
            runtimePreferences: runtimePreferences
        )
        invalidateSuggestion()
    }

    private func scheduleRuntimeLexiconReloadIfNeeded() {
        let currentSnapshot = lexiconRuntimeSnapshot
        let lexiconRuntime = lexiconRuntime
        let scheme = runtimePreferences.inputScheme
        let runtimePreferences = runtimePreferences
        runtimeReloadGeneration += 1
        let generation = runtimeReloadGeneration
        runtimeReloadTask?.cancel()
        runtimeReloadTask = Task { [weak self, lexiconRuntime, currentSnapshot, scheme, runtimePreferences, generation] in
            let snapshot = lexiconRuntime.snapshot(scheme: scheme)
            guard snapshot != currentSnapshot, !Task.isCancelled else {
                return
            }
            let engine = lexiconRuntime.makeEngine(scheme: scheme)
            guard !Task.isCancelled else {
                return
            }
            Task { @MainActor [weak self, engine, snapshot, currentSnapshot, generation] in
                guard let self,
                      self.runtimeReloadGeneration == generation,
                      self.lexiconRuntimeSnapshot == currentSnapshot,
                      snapshot != self.lexiconRuntimeSnapshot else {
                    return
                }
                self.traditionalInputEngine = engine
                self.lexiconRuntimeSnapshot = snapshot
                InputMethodLexiconRuntime.cacheEngine(engine, snapshot: snapshot)
                self.sessionController = InputSessionController(
                    provider: self.provider,
                    traditionalInputEngine: engine,
                    runtimePreferences: runtimePreferences
                )
                self.invalidateSuggestion()
                if !self.rawBuffer.isEmpty {
                    let currentClient = self.host?.currentClient
                    self.publishLocalSuggestion(client: currentClient)
                    self.refreshSuggestion(client: currentClient)
                }
            }
        }
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
    }

    private func updateCandidatePanel(suggestion: SuggestionResponse?, client: InputControllerClient?) {
        guard !rawBuffer.isEmpty || suggestion != nil else {
            hideCandidatePanel()
            return
        }
        updateCandidatePanel(suggestion: suggestion, anchorResult: candidateAnchorResult(client: client))
    }

    private func updateCandidatePanel(suggestion: SuggestionResponse?, anchorResult: CandidateAnchorResult) {
        let isDisplayable = anchorResult.source != .none
        candidatePanelState.update(
            rawInput: rawBuffer,
            suggestion: suggestion,
            anchorRect: anchorResult.rect,
            isDisplayable: isDisplayable,
            pageSize: runtimePreferences.candidatePageSize,
            layoutMode: runtimePreferences.candidateLayoutMode
        )
        selectedNativeCandidate = candidatePanelState.windowState.isVisible
            ? inputCandidateSelection(
                for: candidatePanelState.windowState.selection,
                in: candidatePanelState.windowState.viewModel
            )
            : nil
        host?.updateCandidatePanel(state: candidatePanelState, locale: locale)
    }

    private func hideCandidatePanel() {
        candidatePanelState.hide()
        selectedNativeCandidate = nil
        anchorResolver.reset()
        host?.hideCandidatePanel()
    }

    private func moveCandidateSelection(_ navigation: InputCandidateNavigation) -> Bool {
        guard candidatePanelState.moveSelection(navigation) else {
            return false
        }
        selectedNativeCandidate = inputCandidateSelection(
            for: candidatePanelState.windowState.selection,
            in: candidatePanelState.windowState.viewModel
        )
        host?.updateCandidatePanel(state: candidatePanelState, locale: locale)
        return true
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
            return InputCandidateSelection(
                text: viewModel.prefixCandidates[index].text,
                kind: .prefixCandidate(index: index)
            )
        case .fullCandidate(let index):
            guard viewModel.prefixCandidates.indices.contains(index) else {
                return nil
            }
            return InputCandidateSelection(
                text: viewModel.prefixCandidates[index].text,
                kind: .fullCandidate(index: index)
            )
        case .segmentCandidate(let index):
            guard viewModel.prefixCandidates.indices.contains(index) else {
                return nil
            }
            return InputCandidateSelection(
                text: viewModel.prefixCandidates[index].text,
                kind: .segmentCandidate(index: index)
            )
        case .continuationCandidate(let index):
            guard viewModel.continuationCandidates.indices.contains(index) else {
                return nil
            }
            return InputCandidateSelection(
                text: viewModel.continuationCandidates[index].text,
                kind: .continuationCandidate(index: index)
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
        case .continuationCandidate(let index):
            return .continuationCandidate(index: index)
        }
    }

    private func refreshComposition(client: InputControllerClient?) {
        guard let client else {
            host?.updateComposition()
            return
        }

        let markedText = compositionBuffer.displayText
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

    private func scheduleDelayedCandidateReanchor(
        client: InputControllerClient,
        rawInput: String,
        compositionID: Int
    ) {
        host?.scheduleDelayedReanchor { [weak self, client] in
            guard let self,
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
    private static let leadingFullCandidateCount = 5
}

private extension Collection {
    subscript(inputControllerSafe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
