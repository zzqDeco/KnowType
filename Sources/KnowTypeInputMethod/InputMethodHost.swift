import Foundation
import KnowTypeCore
import KnowTypeProviders

public struct InputMethodPipeline: Sendable {
    public static let defaultMaxPrefixCandidates = 6
    public static let defaultMaxContinuationCandidates = 6

    private let correctionEngine: CorrectionEngine
    private let continuationEngine: PrefixContinuationEngine

    public init(
        provider: (any LLMProvider)? = nil,
        traditionalInputEngine: TraditionalInputEngine = InputMethodLexiconRuntime.defaultEngine()
    ) {
        self.correctionEngine = CorrectionEngine(
            cloudProvider: provider,
            traditionalInputEngine: traditionalInputEngine
        )
        self.continuationEngine = PrefixContinuationEngine(provider: provider)
    }

    public func suggestions(for context: InputContext) async -> SuggestionResponse {
        let start = ContinuousClock.now
        let prefixes = await correctionEngine.correct(context)
        let locked = prefixes.first.map {
            LockedPrefix(
                text: $0.text,
                rawInput: context.rawInput,
                candidateID: $0.source,
                protectedRanges: $0.protectedRanges
            )
        }
        let continuations: [ContinuationCandidate]
        if let locked {
            continuations = await continuationEngine.continuations(
                for: locked,
                context: context,
                lengthLevel: .medium,
                maxCandidates: Self.defaultMaxContinuationCandidates
            )
        } else {
            continuations = []
        }
        let elapsed = start.duration(to: .now)
        let milliseconds = Int(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000)
        return SuggestionResponse(
            prefixCandidates: prefixes,
            lockedPrefix: locked,
            continuationCandidates: continuations,
            latencyMs: milliseconds
        )
    }

    public static func localSuggestions(
        for context: InputContext,
        includeFallbackContinuations: Bool = true,
        traditionalInputEngine: TraditionalInputEngine = InputMethodLexiconRuntime.defaultEngine()
    ) -> SuggestionResponse {
        let correctionEngine = CorrectionEngine(traditionalInputEngine: traditionalInputEngine)
        let continuationEngine = PrefixContinuationEngine()
        let prefixes = correctionEngine.localCorrect(context)
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
           let locked,
           !TextProtection.requiresNoCorrection(locked.text, appBundleID: context.appBundleID),
           !TextProtection.requiresNoCorrection(context.rawInput, appBundleID: context.appBundleID) {
            continuations = continuationEngine.fallbackContinuations(
                for: locked.text,
                lengthLevel: .medium,
                maxCandidates: Self.defaultMaxContinuationCandidates
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

#if canImport(InputMethodKit)
import AppKit
import InputMethodKit

public final class KnowTypeIMKServerBootstrap {
    public let server: IMKServer?

    public init(name: String = "KnowType", bundleIdentifier: String) {
        self.server = IMKServer(name: name, bundleIdentifier: bundleIdentifier)
    }
}
#endif
