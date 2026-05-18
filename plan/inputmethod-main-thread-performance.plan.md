# Input Method Main-Thread Performance

## Summary

KnowType must not run large-lexicon pinyin decoding or runtime lexicon loading directly inside IMK key handling. The production input path now publishes raw marked text immediately, shows an immediate local prefix-only candidate snapshot, and refreshes provider-backed continuation rows asynchronously. This keeps front-end typing responsive even when the installed runtime lexicon is large.

## Delivered Changes

- `KnowTypeInputController` starts from `InputMethodLexiconRuntime.initialEngineState()`: seed-only when no runtime resources exist, cached/prewarmed runtime engine when available, and installed runtime lexicons preserved before the first composition when needed.
- `KnowTypeInputMethodApp` prewarms the default runtime lexicon engine on a utility task after launch.
- `InputControllerCoordinator` separates production async suggestion refresh from the synchronous local suggestion path kept for deterministic unit tests.
- Candidate augmentation, including segmented candidate generation, runs off the keydown path with an interactive query budget.
- Stale async publications are rejected by raw input, composition id, composition buffer, and generation checks.
- `InputSessionCommitPolicy` can skip broad synchronous fallback generation while production suggestions are pending; Space commits the visible local prefix snapshot rather than a hidden fallback candidate.
- Pending Space, Tab, raw shortcuts, and punctuation keep local behavior while async suggestions load. Space and punctuation after partial segment selection apply the best remaining local segment before committing when that fully resolves the composition; punctuation rolls back the fallback mutation when only a partial tail can be applied.
- Fully resolved segmented compositions keep local fallback continuations when no provider is configured.
- Runtime lexicon reloads carry a generation token so cancellation and controller close prevent late MainActor engine swaps.
- `TraditionalInputEngine` exposes `TraditionalInputQueryOptions` and caps tokenization paths, parse states, candidate count, segment candidates, and partial-match fanout for interactive use.
- `CorrectionEngine` skips cloud-gating pinyin analysis when no cloud provider is configured and short-circuits direct English spelling fixes such as `latnecy -> latency`.

## Test Plan

- `TraditionalInputPerformanceTests` covers interactive budget responsiveness with a large synthetic lexicon and direct English spelling correction.
- `InputControllerCoordinatorTests/testAsyncAppendPublishesMarkedTextAndImmediateLocalCandidates` verifies key handling publishes raw marked text plus immediate local prefix candidates.
- `InputControllerCoordinatorTests/testAsyncPendingSpaceCommitsVisibleLocalPrefix` and `testAsyncPendingPunctuationUsesLocalCommitFallback` verify pending async suggestions commit visible local candidates.
- `InputControllerCoordinatorTests/testAsyncPendingSpaceAppliesRemainingSegmentBeforeCommit`, `testAsyncPendingPunctuationAppliesRemainingSegmentBeforeCommit`, and `testFullyResolvedSegmentSelectionKeepsLocalContinuationsWithoutProvider` cover segmented pending commit regressions.
- `InputControllerCoordinatorTests/testAsyncPendingTabCommitsVisiblePrefixWithoutHiddenContinuation`, `testAsyncPendingPunctuationDoesNotApplyPartialFallbackSegment`, and `testAsyncPendingRawShortcutCommitsRawInput` cover the latest Codex review regressions around pending Tab, punctuation, and raw shortcuts.
- `InputMethodLexiconRuntimeTests/testInitialEngineStatePreservesInstalledRuntimeLexicon` verifies the first controller engine state includes installed runtime resources.
- `InputSessionControllerTests/testCommitPolicyCanAvoidSynchronousFallbackWhileSuggestionIsPending` verifies pending production suggestions do not force synchronous fallback generation.
- Full gate: `swift test` and `git diff --check`.
