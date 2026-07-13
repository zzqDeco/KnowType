import Foundation
import KnowTypeCore

public enum InputSessionMode: Sendable, Equatable {
    case empty
    case composing
    case candidate
    case aiPending
    case ascii
}

public struct InputSessionState: Sendable, Equatable {
    public var mode: InputSessionMode
    public var rawInput: String
    public var latestSuggestion: SuggestionResponse?
    public var latestSuggestionRawInput: String?
    public var selectedPrefixIndex: Int
    public var selectedContinuationIndex: Int?

    public init(
        mode: InputSessionMode = .empty,
        rawInput: String = "",
        latestSuggestion: SuggestionResponse? = nil,
        latestSuggestionRawInput: String? = nil,
        selectedPrefixIndex: Int = 0,
        selectedContinuationIndex: Int? = nil
    ) {
        self.mode = mode
        self.rawInput = rawInput
        self.latestSuggestion = latestSuggestion
        self.latestSuggestionRawInput = latestSuggestionRawInput
        self.selectedPrefixIndex = selectedPrefixIndex
        self.selectedContinuationIndex = selectedContinuationIndex
    }
}

public enum InputSessionCandidateSelection: Sendable, Equatable {
    case rawInput
    case prefixCandidate(index: Int)
    case continuationCandidate(index: Int)
}

public enum InputSessionCommitPolicy {
    public static func result(
        for action: InputAction,
        rawInput: String,
        suggestion: SuggestionResponse?,
        suggestionRawInput: String?,
        selectedCandidate: InputSessionCandidateSelection? = nil,
        appBundleID: String? = nil,
        locale: KnowTypeLocale = .mixed,
        traditionalInputEngine: TraditionalInputEngine? = nil,
        runtimePreferences: InputMethodRuntimePreferences = .standard,
        allowsSynchronousFallback: Bool = true
    ) -> InputCommitResult {
        if action == .commitRaw {
            return rawInput.isEmpty ? .noAction : .commit(rawInput)
        }
        guard let suggestion,
              SuggestionPublicationGuard.hasCurrentSuggestion(
                suggestionRawInput: suggestionRawInput,
                currentRawInput: rawInput
              ) else {
            return fallbackResult(
                for: action,
                rawInput: rawInput,
                appBundleID: appBundleID,
                locale: locale,
                traditionalInputEngine: traditionalInputEngine,
                runtimePreferences: runtimePreferences,
                allowsSynchronousFallback: allowsSynchronousFallback
            )
        }

        if let selectedCandidate {
            return result(
                for: action,
                rawInput: rawInput,
                suggestion: suggestion,
                selectedCandidate: selectedCandidate
            )
        }

        return InputCompositionController().handle(
            action: action,
            prefixCandidates: suggestion.prefixCandidates,
            continuationCandidates: suggestion.continuationCandidates,
            originalText: rawInput
        )
    }

    public static func resultForCandidateNumber(
        _ number: Int,
        rawInput: String,
        suggestion: SuggestionResponse?,
        suggestionRawInput: String?
    ) -> InputCommitResult? {
        guard number >= 0,
              let suggestion,
              SuggestionPublicationGuard.hasCurrentSuggestion(
                suggestionRawInput: suggestionRawInput,
                currentRawInput: rawInput
              ) else {
            return nil
        }

        if number == 0 {
            guard !rawInput.isEmpty,
                  !suggestion.prefixCandidates.isEmpty else {
                return nil
            }
            return .commit(rawInput)
        }

        let prefixIndex = number - 1
        guard suggestion.prefixCandidates.indices.contains(prefixIndex) else {
            return nil
        }
        return .commit(suggestion.prefixCandidates[prefixIndex].text)
    }

    private static func fallbackResult(
        for action: InputAction,
        rawInput: String,
        appBundleID: String?,
        locale: KnowTypeLocale,
        traditionalInputEngine: TraditionalInputEngine?,
        runtimePreferences: InputMethodRuntimePreferences,
        allowsSynchronousFallback: Bool
    ) -> InputCommitResult {
        guard !rawInput.isEmpty else {
            return .noAction
        }

        switch action {
        case .space, .tab:
            guard allowsSynchronousFallback,
                  let traditionalInputEngine else {
                return .noAction
            }
            let context = InputContext(
                rawInput: rawInput,
                appBundleID: appBundleID,
                locale: locale
            )
            let suggestion = SessionSuggestionPipeline.localSuggestions(
                for: context,
                includeFallbackContinuations: true,
                traditionalInputEngine: traditionalInputEngine,
                runtimePreferences: runtimePreferences
            )
            return InputCompositionController().handle(
                action: action,
                prefixCandidates: suggestion.prefixCandidates,
                continuationCandidates: suggestion.continuationCandidates,
                originalText: rawInput
            )
        case .optionNumber, .toggleSymbolMode, .toggleTextMode, .toggleSymbolWidth, .commitRaw:
            return .noAction
        }
    }

    private static func result(
        for action: InputAction,
        rawInput: String,
        suggestion: SuggestionResponse,
        selectedCandidate: InputSessionCandidateSelection
    ) -> InputCommitResult {
        switch selectedCandidate {
        case .rawInput:
            switch action {
            case .space, .tab, .commitRaw:
                return .commit(rawInput)
            case .optionNumber, .toggleSymbolMode, .toggleTextMode, .toggleSymbolWidth:
                return .noAction
            }
        case .prefixCandidate(let index):
            guard suggestion.prefixCandidates.indices.contains(index) else {
                return .noAction
            }
            if index != 0 {
                switch action {
                case .space, .tab, .optionNumber:
                    return .commit(suggestion.prefixCandidates[index].text)
                case .toggleSymbolMode, .toggleTextMode, .toggleSymbolWidth:
                    return .noAction
                case .commitRaw:
                    return .commit(rawInput)
                }
            }
            if action == .commitRaw {
                return .commit(rawInput)
            }
            return InputCompositionController().handle(
                action: action,
                prefixCandidates: [suggestion.prefixCandidates[index]],
                continuationCandidates: suggestion.continuationCandidates,
                originalText: rawInput
            )
        case .continuationCandidate(let index):
            guard suggestion.continuationCandidates.indices.contains(index) else {
                return .noAction
            }
            switch action {
            case .space, .tab, .optionNumber:
                return InputCompositionController().handle(
                    action: .optionNumber(index + 1),
                    prefixCandidates: suggestion.prefixCandidates,
                    continuationCandidates: suggestion.continuationCandidates,
                    originalText: rawInput
                )
            case .toggleSymbolMode, .toggleTextMode, .toggleSymbolWidth:
                return .noAction
            case .commitRaw:
                return .commit(rawInput)
            }
        }
    }
}

public actor InputSessionController {
    public typealias SuggestionLoader = @Sendable (InputContext) async -> SuggestionResponse

    public private(set) var state: InputSessionState

    private let suggestionLoader: SuggestionLoader
    private let protectedSuggestionLoader: SuggestionLoader
    private let compositionController: InputCompositionController
    private var updateGeneration: UInt64 = 0

    public init(
        provider: (any LLMProvider)? = nil,
        traditionalInputEngine: TraditionalInputEngine = InputMethodLexiconRuntime.defaultEngine(),
        runtimePreferences: InputMethodRuntimePreferences = .standard
    ) {
        let pipeline = SessionSuggestionPipeline(
            provider: provider,
            traditionalInputEngine: traditionalInputEngine,
            runtimePreferences: runtimePreferences
        )
        let protectedPipeline = SessionSuggestionPipeline(
            provider: nil,
            traditionalInputEngine: traditionalInputEngine,
            runtimePreferences: runtimePreferences
        )
        self.init(
            suggestionLoader: { context in
                await pipeline.suggestions(for: context)
            },
            protectedSuggestionLoader: { context in
                await protectedPipeline.suggestions(for: context)
            }
        )
    }

    init(
        suggestionLoader: @escaping SuggestionLoader,
        protectedSuggestionLoader: SuggestionLoader? = nil,
        initialState: InputSessionState = InputSessionState(),
        compositionController: InputCompositionController = InputCompositionController()
    ) {
        self.state = initialState
        self.suggestionLoader = suggestionLoader
        self.protectedSuggestionLoader = protectedSuggestionLoader ?? suggestionLoader
        self.compositionController = compositionController
    }

    @discardableResult
    public func update(
        rawInput: String,
        appBundleID: String? = nil,
        locale: KnowTypeLocale = .mixed,
        userSelectionHistory: [String] = []
    ) async -> SuggestionResponse {
        let context = InputContext(
            rawInput: rawInput,
            appBundleID: appBundleID,
            locale: locale,
            userSelectionHistory: userSelectionHistory
        )
        let isLevelZero = TextProtection.requiresNoCorrection(rawInput, appBundleID: appBundleID)
        let loader = isLevelZero
            ? protectedSuggestionLoader
            : suggestionLoader
        updateGeneration &+= 1
        let generation = updateGeneration
        state.rawInput = rawInput
        state.mode = pendingMode(rawInput: rawInput, isLevelZero: isLevelZero)
        state.latestSuggestion = nil
        state.latestSuggestionRawInput = nil
        state.selectedPrefixIndex = 0
        state.selectedContinuationIndex = nil
        let loadedSuggestion = await loader(context)
        // The actor is reentrant while awaiting provider-backed suggestions; older completions must not publish stale state.
        guard generation == updateGeneration else {
            return state.latestSuggestion ?? loadedSuggestion
        }

        var suggestion = loadedSuggestion
        if isLevelZero {
            suggestion.continuationCandidates = []
        }

        state.rawInput = rawInput
        state.latestSuggestion = suggestion
        state.latestSuggestionRawInput = rawInput
        state.selectedPrefixIndex = 0
        state.selectedContinuationIndex = nil
        state.mode = mode(
            rawInput: rawInput,
            suggestion: suggestion,
            isLevelZero: isLevelZero
        )

        return suggestion
    }

    @discardableResult
    public func selectPrefix(index: Int) -> Bool {
        guard let suggestion = state.latestSuggestion,
              suggestion.prefixCandidates.indices.contains(index) else {
            return false
        }

        state.selectedPrefixIndex = index
        return true
    }

    @discardableResult
    public func selectContinuation(index: Int) -> Bool {
        guard let suggestion = state.latestSuggestion,
              suggestion.continuationCandidates.indices.contains(index) else {
            return false
        }

        state.selectedContinuationIndex = index
        return true
    }

    public func handle(action: InputAction) -> InputCommitResult {
        if action == .commitRaw {
            return state.rawInput.isEmpty ? .noAction : .commit(state.rawInput)
        }
        guard let suggestion = state.latestSuggestion,
              state.latestSuggestionRawInput == state.rawInput,
              let prefix = selectedPrefix(in: suggestion),
              !prefix.text.isEmpty else {
            return .noAction
        }

        let result: InputCommitResult
        switch action {
        case .space, .tab, .toggleSymbolMode, .toggleTextMode, .toggleSymbolWidth:
            result = compositionController.handle(
                action: action,
                prefixCandidates: [prefix],
                continuationCandidates: selectedContinuationCandidates(in: suggestion),
                originalText: state.rawInput
            )
        case .optionNumber(let number):
            guard number > 0 else {
                return .noAction
            }
            if state.selectedPrefixIndex != 0 {
                return .commit(prefix.text)
            }
            let index = number - 1
            guard suggestion.continuationCandidates.indices.contains(index) else {
                return .noAction
            }
            state.selectedContinuationIndex = index
            result = compositionController.handle(
                action: .tab,
                prefixCandidates: [prefix],
                continuationCandidates: [suggestion.continuationCandidates[index]],
                originalText: state.rawInput
            )
        case .commitRaw:
            result = state.rawInput.isEmpty ? .noAction : .commit(state.rawInput)
        }

        return result
    }

    public func reset() {
        updateGeneration &+= 1
        state = InputSessionState()
    }

    public var candidatePanelViewModel: CandidatePanelViewModel {
        guard let suggestion = state.latestSuggestion else {
            return CandidatePanelViewModel(
                rawInput: state.rawInput,
                prefixCandidates: [],
                continuationCandidates: []
            )
        }

        return CandidatePanelViewModel(
            rawInput: state.rawInput,
            prefixCandidates: suggestion.prefixCandidates,
            continuationCandidates: suggestion.continuationCandidates
        )
    }

    private func selectedPrefix(in suggestion: SuggestionResponse) -> CorrectionCandidate? {
        guard suggestion.prefixCandidates.indices.contains(state.selectedPrefixIndex) else {
            return suggestion.prefixCandidates.first
        }
        return suggestion.prefixCandidates[state.selectedPrefixIndex]
    }

    private func selectedContinuationCandidates(in suggestion: SuggestionResponse) -> [ContinuationCandidate] {
        guard state.selectedPrefixIndex == 0 else {
            return []
        }
        if let index = state.selectedContinuationIndex,
           suggestion.continuationCandidates.indices.contains(index) {
            return [suggestion.continuationCandidates[index]]
        }
        return suggestion.continuationCandidates
    }

    private func pendingMode(rawInput: String, isLevelZero: Bool) -> InputSessionMode {
        guard !rawInput.isEmpty else {
            return .empty
        }
        return isLevelZero ? .ascii : .aiPending
    }

    private func mode(
        rawInput: String,
        suggestion: SuggestionResponse,
        isLevelZero: Bool
    ) -> InputSessionMode {
        guard !rawInput.isEmpty else {
            return .empty
        }
        if isLevelZero {
            return .ascii
        }
        let hasCandidates = !suggestion.prefixCandidates.isEmpty
            || !suggestion.continuationCandidates.isEmpty
        return hasCandidates ? .candidate : .composing
    }
}
