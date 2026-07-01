import Foundation
import KnowTypeCore
import KnowTypeProviders

public struct SessionSuggestionPipeline: Sendable {
    public static let defaultMaxPrefixCandidates = 6
    public static let defaultMaxContinuationCandidates = 6
    public static let interactiveQueryOptions = TraditionalInputQueryOptions.interactive

    private let correctionEngine: CorrectionEngine
    private let continuationEngine: PrefixContinuationEngine
    private let runtimePreferences: InputMethodRuntimePreferences
    private let hasProvider: Bool

    public init(
        provider: (any LLMProvider)? = nil,
        traditionalInputEngine: TraditionalInputEngine = InputMethodLexiconRuntime.defaultEngine(),
        runtimePreferences: InputMethodRuntimePreferences = .standard
    ) {
        self.runtimePreferences = runtimePreferences
        self.hasProvider = provider != nil
        self.correctionEngine = CorrectionEngine(
            cloudProvider: provider,
            traditionalInputEngine: traditionalInputEngine
        )
        self.continuationEngine = PrefixContinuationEngine(provider: provider)
    }

    public func suggestions(for context: InputContext) async -> SuggestionResponse {
        let start = ContinuousClock.now
        let prefixes = await correctionEngine.correct(
            context,
            queryOptions: Self.interactiveQueryOptions
        )
        let locked = prefixes.first.map {
            LockedPrefix(
                text: $0.text,
                rawInput: context.rawInput,
                candidateID: $0.source,
                protectedRanges: $0.protectedRanges
            )
        }
        let continuations = await continuationCandidates(
            for: locked,
            context: context
        )
        let elapsed = start.duration(to: .now)
        let milliseconds = Int(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000)
        return SuggestionResponse(
            prefixCandidates: prefixes,
            lockedPrefix: locked,
            continuationCandidates: continuations,
            latencyMs: milliseconds
        )
    }

    public func prefixSuggestions(for context: InputContext) async -> SuggestionResponse {
        let start = ContinuousClock.now
        let prefixes = await correctionEngine.correct(
            context,
            queryOptions: Self.interactiveQueryOptions
        )
        let locked = prefixes.first.map {
            LockedPrefix(
                text: $0.text,
                rawInput: context.rawInput,
                candidateID: $0.source,
                protectedRanges: $0.protectedRanges
            )
        }
        let elapsed = start.duration(to: .now)
        let milliseconds = Int(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000)
        return SuggestionResponse(
            prefixCandidates: prefixes,
            lockedPrefix: locked,
            continuationCandidates: [],
            latencyMs: milliseconds
        )
    }

    private func continuationCandidates(
        for locked: LockedPrefix?,
        context: InputContext
    ) async -> [ContinuationCandidate] {
        guard let locked else {
            return []
        }

        if hasProvider {
            guard runtimePreferences.cloudContinuationEnabled,
                  !TextProtection.containsSecretLikeContent(locked.text),
                  !TextProtection.containsSecretLikeContent(context.rawInput) else {
                return []
            }
            return await continuationEngine.continuations(
                for: locked,
                context: context,
                lengthLevel: runtimePreferences.continuationLengthLevel,
                maxCandidates: runtimePreferences.maxContinuationCandidates
            )
        }

        guard runtimePreferences.localContinuationEnabledWhenNoProvider,
              !TextProtection.requiresNoCorrection(locked.text, appBundleID: context.appBundleID),
              !TextProtection.requiresNoCorrection(context.rawInput, appBundleID: context.appBundleID) else {
            return []
        }
        return continuationEngine.fallbackContinuations(
            for: locked.text,
            lengthLevel: runtimePreferences.continuationLengthLevel,
            maxCandidates: runtimePreferences.maxContinuationCandidates
        )
    }

    public static func localSuggestions(
        for context: InputContext,
        includeFallbackContinuations: Bool = true,
        traditionalInputEngine: TraditionalInputEngine = InputMethodLexiconRuntime.defaultEngine(),
        runtimePreferences: InputMethodRuntimePreferences = .standard
    ) -> SuggestionResponse {
        let correctionEngine = CorrectionEngine(traditionalInputEngine: traditionalInputEngine)
        let continuationEngine = PrefixContinuationEngine()
        let prefixes = correctionEngine.localCorrect(
            context,
            queryOptions: Self.interactiveQueryOptions
        )
        let locked = prefixes.first.map {
            LockedPrefix(
                text: $0.text,
                rawInput: context.rawInput,
                candidateID: $0.source,
                protectedRanges: $0.protectedRanges
            )
        }
        let continuations: [ContinuationCandidate]
        if includeFallbackContinuations,
           runtimePreferences.localContinuationEnabledWhenNoProvider,
           let locked,
           !TextProtection.requiresNoCorrection(locked.text, appBundleID: context.appBundleID),
           !TextProtection.requiresNoCorrection(context.rawInput, appBundleID: context.appBundleID) {
            continuations = continuationEngine.fallbackContinuations(
                for: locked.text,
                lengthLevel: runtimePreferences.continuationLengthLevel,
                maxCandidates: runtimePreferences.maxContinuationCandidates
            )
        } else {
            continuations = []
        }
        return SuggestionResponse(
            prefixCandidates: prefixes,
            lockedPrefix: locked,
            continuationCandidates: continuations,
            latencyMs: 0
        )
    }
}
