import Foundation
import KnowTypeCore

public struct InputSessionState: Sendable, Equatable {
    public var rawInput: String
    public var latestSuggestion: SuggestionResponse?
    public var selectedPrefixIndex: Int
    public var selectedContinuationIndex: Int?
    public var polishRequested: Bool

    public init(
        rawInput: String = "",
        latestSuggestion: SuggestionResponse? = nil,
        selectedPrefixIndex: Int = 0,
        selectedContinuationIndex: Int? = nil,
        polishRequested: Bool = false
    ) {
        self.rawInput = rawInput
        self.latestSuggestion = latestSuggestion
        self.selectedPrefixIndex = selectedPrefixIndex
        self.selectedContinuationIndex = selectedContinuationIndex
        self.polishRequested = polishRequested
    }
}

public actor InputSessionController {
    public typealias SuggestionLoader = @Sendable (InputContext) async -> SuggestionResponse

    public private(set) var state: InputSessionState

    private let suggestionLoader: SuggestionLoader
    private let protectedSuggestionLoader: SuggestionLoader
    private let compositionController: InputCompositionController
    private var updateGeneration: UInt64 = 0

    public init(provider: (any LLMProvider)? = nil) {
        let pipeline = InputMethodPipeline(provider: provider)
        let protectedPipeline = InputMethodPipeline(provider: nil)
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
        locale: KnowTypeLocale = .mixed
    ) async -> SuggestionResponse {
        let context = InputContext(
            rawInput: rawInput,
            appBundleID: appBundleID,
            locale: locale
        )
        let isLevelZero = TextProtection.requiresNoCorrection(rawInput, appBundleID: appBundleID)
        let loader = isLevelZero
            ? protectedSuggestionLoader
            : suggestionLoader
        updateGeneration &+= 1
        let generation = updateGeneration
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
        state.selectedPrefixIndex = 0
        state.selectedContinuationIndex = nil
        state.polishRequested = false

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
        guard let suggestion = state.latestSuggestion,
              let prefix = selectedPrefix(in: suggestion),
              !prefix.text.isEmpty else {
            return .noAction
        }

        let result: InputCommitResult
        switch action {
        case .space, .tab, .optionR:
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
            let index = number
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
        }

        if case .polishRequested = result {
            state.polishRequested = true
        }

        return result
    }

    @discardableResult
    public func requestPolish(rawInput: String) -> InputCommitResult {
        guard !rawInput.isEmpty else {
            return .noAction
        }
        state.rawInput = rawInput
        state.polishRequested = true
        return .polishRequested(rawInput)
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
        if let index = state.selectedContinuationIndex,
           suggestion.continuationCandidates.indices.contains(index) {
            return [suggestion.continuationCandidates[index]]
        }
        return suggestion.continuationCandidates
    }
}
