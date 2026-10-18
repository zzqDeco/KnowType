# InputMethod Legacy CompositionBuffer Cleanup And Concurrency Isolation

## Delivered Behavior

- Consolidated `InputCommitDecisionRuntime` around action-specific Rime-only hot-path decision helpers (`decideReturn`, `decideSpace`, `decideTab`, `decideOptionNumber`) and isolated legacy `CompositionBuffer` resolved-segment fallback logic into guard-first private helpers (`resolveLegacySegmentedReturnDecisionIfNeeded`, `resolveLegacySegmentedSpaceDecisionIfNeeded`, `resolveLegacySegmentedTabDecisionIfNeeded`) that immediately return `nil` when `compositionBuffer.hasResolvedSegments` is `false`.
- Consolidated legacy `CompositionBuffer` segment branches in `InputControllerCoordinator` (`commitResolvedText`, `rebuildCandidates`, `legacyResolutionFlags`, `legacyPartialSegmentedSymbolCommitResult`, `legacySegmentedSymbolFallbackCommitResult`, `legacySegmentedSuggestionIfNeeded`) so the Rime-only key and suggestion hot path avoids redundant `SuggestionResponse` reconstruction while preserving compatibility with existing unit tests.
- Hardened and documented the main-thread / `MainActor` concurrency confinement contract across `InputControllerCoordinator`, `InputCommitDecisionRuntime`, `InputActiveSessionRuntime`, `InputAIAcceptanceRuntime`, and `InputClientCompositionWriter`, ensuring asynchronous callbacks hop onto `MainActor` before mutating coordinator state.

## Verification

- `swift test --filter InputCommitDecisionRuntimeTests`
- `swift test --filter InputHotPathPerformanceTests`

## Docs Absorbed By

- `doc/src/Sources/KnowTypeInputMethod/InputControllerCoordinator.swift.plan.md`
- `doc/src/Sources/KnowTypeInputMethod/InputCommitDecisionRuntime.swift.plan.md`

## Retirement Criteria

- Retire this delivered record once the Rime-only hot-path decision helpers and main-thread confinement contracts remain stable across the `#226` refactor milestone and are indexed in the current-state documentation.
