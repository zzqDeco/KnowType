# Input Method Main-Thread Performance

## Summary

KnowType must not run large-lexicon pinyin decoding or runtime lexicon loading directly inside IMK key handling. The production input path now publishes raw marked text immediately, shows a raw/pending candidate panel state, and resolves correction candidates asynchronously. This keeps front-end typing responsive even when the installed runtime lexicon is large.

## Delivered Changes

- `KnowTypeInputController` starts with the bundled seed `TraditionalInputEngine` and lets `InputControllerCoordinator` warm the runtime lexicon in the background.
- `InputControllerCoordinator` separates production async suggestion refresh from the synchronous local suggestion path kept for deterministic unit tests.
- Candidate augmentation, including segmented candidate generation, runs off the keydown path with an interactive query budget.
- Stale async publications are rejected by raw input, composition id, composition buffer, and generation checks.
- `InputSessionCommitPolicy` can skip broad synchronous fallback generation while production suggestions are pending; Space and punctuation commits use a bounded local fallback so the first commit key is not swallowed and raw pinyin is not inserted prematurely.
- Runtime lexicon reloads carry a generation token so cancellation and controller close prevent late MainActor engine swaps.
- `TraditionalInputEngine` exposes `TraditionalInputQueryOptions` and caps tokenization paths, parse states, candidate count, segment candidates, and partial-match fanout for interactive use.
- `CorrectionEngine` skips cloud-gating pinyin analysis when no cloud provider is configured and short-circuits direct English spelling fixes such as `latnecy -> latency`.

## Test Plan

- `TraditionalInputPerformanceTests` covers interactive budget responsiveness with a large synthetic lexicon and direct English spelling correction.
- `InputControllerCoordinatorTests/testAsyncAppendPublishesRawCompositionBeforeCandidatesArrive` verifies key handling publishes raw marked text before candidates arrive.
- `InputControllerCoordinatorTests/testAsyncPendingSpaceUsesLocalCommitFallback` and `testAsyncPendingPunctuationUsesLocalCommitFallback` verify pending async suggestions still commit local Chinese candidates.
- `InputSessionControllerTests/testCommitPolicyCanAvoidSynchronousFallbackWhileSuggestionIsPending` verifies pending production suggestions do not force synchronous fallback generation.
- Full gate: `swift test` and `git diff --check`.
