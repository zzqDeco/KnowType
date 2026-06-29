# Input Selection History Runtime Refactor

## Summary

- Extract the local prefix-selection history responsibilities from
  `InputControllerCoordinator` into a small `InputSelectionHistoryRuntime`.
- Keep behavior unchanged while reducing the coordinator hotspot before further
  input-method refactors.

## Scope

- Add `InputSelectionHistoryRuntime` under `Sources/KnowTypeInputMethod`.
- Move selection trimming, `TextProtection` filtering, recent lexical selection
  cache updates, persistence record calls, flush delegation, and
  `candidateSelected` event construction out of the coordinator.
- Keep Rime interaction, AI scheduling, candidate ordering, host writes, and
  persistence file-format behavior unchanged.

## Implementation

- The coordinator initializes one `InputSelectionHistoryRuntime` with the
  existing `InputControllerUserSelectionHistoryPersisting` boundary and the
  current maximum history size.
- `recordUserSelection` asks the runtime for an optional
  `InputRuntimeEvent.candidateSelected`, publishes it when present, and then
  schedules lexical profile refresh exactly as before.
- `LexicalProfileRuntime` receives only the runtime's in-process
  `recentSelectionHistory`, preserving the existing privacy boundary where a
  fresh process does not inject all persisted selections into AI context.
- `flushUserSelectionHistory` delegates to the runtime.

## Test Plan

- `swift test --quiet --filter InputSelectionHistoryRuntimeTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`

## Assumptions

- This is a refactor-only PR; it does not change ranking, AI prompt context,
  Rime behavior, or user-selection file format.
- `UserSelectionHistoryStore` remains the owner of durable storage and merge
  semantics.
