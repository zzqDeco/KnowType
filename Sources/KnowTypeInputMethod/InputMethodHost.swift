import Foundation
import KnowTypeCore
import KnowTypeProviders

public struct InputMethodPipeline: Sendable {
    private let correctionEngine: CorrectionEngine
    private let continuationEngine: PrefixContinuationEngine

    public init(provider: (any LLMProvider)? = nil) {
        self.correctionEngine = CorrectionEngine(cloudProvider: provider)
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
                maxCandidates: 3
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
