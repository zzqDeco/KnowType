# Input Method Main-Thread Performance

## Summary

KnowType must not run large-lexicon pinyin decoding or runtime lexicon loading directly inside IMK key handling. The production input path now publishes raw marked text immediately, shows a raw/pending candidate panel state, and resolves correction candidates asynchronously. This keeps front-end typing responsive even when the installed runtime lexicon is large.

## Delivered Changes

- `KnowTypeInputController` starts with the bundled seed `TraditionalInputEngine` and lets `InputControllerCoordinator` warm the runtime lexicon in the background.
- `InputControllerCoordinator` separates production async suggestion refresh from the synchronous local suggestion path kept for deterministic unit tests.
- Candidate augmentation, including segmented candidate generation, runs off the keydown path with an interactive query budget.
- Stale async publications are rejected by raw input, composition id, composition buffer, and generation checks.
- `InputSessionCommitPolicy` can skip synchronous fallback generation while production suggestions are pending, returning no action instead of blocking the UI.
- `TraditionalInputEngine` exposes `TraditionalInputQueryOptions` and caps tokenization paths, parse states, candidate count, segment candidates, and partial-match fanout for interactive use.
- `CorrectionEngine` skips cloud-gating pinyin analysis when no cloud provider is configured and short-circuits direct English spelling fixes such as `latnecy -> latency`.

## Test Plan

- `TraditionalInputPerformanceTests` covers interactive budget responsiveness with a large synthetic lexicon and direct English spelling correction.
- `InputControllerCoordinatorTests/testAsyncAppendPublishesRawCompositionBeforeCandidatesArrive` verifies key handling publishes raw marked text before candidates arrive.
- `InputSessionControllerTests/testCommitPolicyCanAvoidSynchronousFallbackWhileSuggestionIsPending` verifies pending production suggestions do not force synchronous fallback generation.
- Full gate: `swift test` and `git diff --check`.
