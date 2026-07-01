# Input Lexical Commit Runtime Refactor

Status: Delivered

## Summary

- Extract local lexical commit and selection side-effect orchestration from
  `InputControllerCoordinator` into `InputLexicalCommitRuntime`.
- Keep behavior unchanged while reducing coordinator responsibility for recent
  lexical commits, selection-history refresh inputs, lexical context snapshots,
  and commit/selection runtime event payloads.

## Scope

- Add `InputLexicalCommitRuntime` under `Sources/KnowTypeInputMethod`.
- Keep composition lifecycle, host marked-text writes, Rime/native navigation,
  candidate-panel publication, AI recommendation, AI acceptance, and
  installation tooling in their existing owners.
- Keep `InputSelectionHistoryRuntime` and `LexicalProfileRuntime` semantics
  unchanged.

## Implementation

- The runtime owns a bounded recent commit buffer and composes
  `InputSelectionHistoryRuntime` with `LexicalProfileRuntime`.
- The coordinator builds small selection/commit contexts and publishes any
  returned `InputRuntimeEvent` through `InputEventBus`.
- Selection recording preserves protected-input filtering, recent selection
  history, and persistence delegation.
- Commit recording trims text, skips empty commits, records
  `.compositionCommitted`, and schedules lexical refresh with the active schema.
- Lexical context snapshots are requested through the runtime so AI request
  construction receives the same recent commits and recent selection history as
  before.

## Test Plan

- `swift test --quiet --filter InputLexicalCommitRuntimeTests`
- `swift test --quiet --filter InputSelectionHistoryRuntimeTests`
- `swift test --quiet --filter LexicalProfileRuntimeTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputAIRecommendationRuntimeTests`
- `swift test --quiet --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`

## Assumptions

- This is a refactor-only PR.
- `InputRuntimeEvent` shape stays unchanged.
- `InputControllerCoordinator` still owns actual commit application,
  composition lifecycle, host writes, and event-bus publication.
