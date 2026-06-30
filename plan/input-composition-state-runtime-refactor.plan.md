# Input Composition State Runtime Refactor

## Summary

- Extract pure composition state from `InputControllerCoordinator` into
  `InputCompositionStateRuntime`.
- Keep behavior unchanged while reducing coordinator ownership of raw input,
  `CompositionBuffer`, composition id/revision, and delete count state.

## Scope

- Add `InputCompositionStateRuntime` under `Sources/KnowTypeInputMethod`.
- Move raw/buffer/id/revision/delete-count mutation behind runtime APIs.
- Keep Rime calls, host writes, candidate-panel publication, AI, lexical
  side effects, input mode policy, and install tooling in existing owners.

## Implementation

- The runtime exposes immutable snapshots and pure mutation results for begin,
  append, delete, segment apply, native raw sync, lifecycle commit text, anchor
  id increment, and lifecycle reset.
- Coordinator continues sequencing side effects: Rime processing, marked text,
  insert, panel hide, AI/lexical recording, anchor reset, and runtime events.
- Commit side-effect recording reads a captured composition snapshot before
  lifecycle reset so raw input, composition id, and delete count stay stable.

## Test Plan

- `swift test --quiet --filter InputCompositionStateRuntimeTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputAIRecommendationRuntimeTests`
- `swift test --quiet --filter InputAIAcceptanceRuntimeTests`
- `swift test --quiet --filter InputCandidatePanelPublicationRuntimeTests`
- `swift test --quiet --filter InputClientCompositionWriterTests`
- `swift test --quiet --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`

## Assumptions

- This is a refactor-only PR.
- `CompositionBuffer` remains the low-level segment buffer.
- `InputControllerCoordinator` still owns all side-effect ordering.
