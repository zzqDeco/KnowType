# Input Suggestion State Runtime Refactor

## Summary

- Extract current suggestion state from `InputControllerCoordinator` into
  `InputSuggestionStateRuntime`.
- Retire confirmed-unused async local-candidate remnants so the Rime-only
  product path has one synchronous suggestion state owner.

## Scope

- Add `InputSuggestionStateRuntime` under `Sources/KnowTypeInputMethod`.
- Move `lastSuggestion` / `lastSuggestionRawInput` storage, current-suggestion
  checks, commit snapshot reads, and no-provider fallback continuation cleanup
  out of the coordinator.
- Remove the retired `suggestionTask`, `suggestionGeneration`,
  `refreshSuggestion`, `InputTaskKind.localCandidates`, and `InputGeneration`
  remnants.
- Do not change Rime, candidate-panel publication, AI recommendation, host
  writes, input mode policy, or provider behavior.

## Implementation

- The runtime stores a `SuggestionResponse?` and the raw input that produced it.
- Commit snapshots preserve the current commit-policy shape and keep
  `usesPendingFallback` set to `false`.
- Provider-known fallback cleanup only removes continuation candidates from a
  resolved-composition fallback suggestion whose locked prefix uses the
  `composition-buffer` candidate id.
- The coordinator continues constructing Rime-backed suggestions and panel
  publication contexts, but reads/writes suggestion state through the runtime.
- Hot-path performance tests guard against reintroducing `suggestionTask` or
  `.localCandidates` into the coordinator path.

## Test Plan

- `swift test --quiet --filter InputSuggestionStateRuntimeTests`
- `swift test --quiet --filter SuggestionPublicationGuardTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputAIRecommendationRuntimeTests`
- `swift test --quiet --filter InputCandidatePanelPublicationRuntimeTests`
- `swift test --quiet --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`

## Assumptions

- This is a pure refactor and cleanup PR.
- The retired local converter and async local suggestion task stay disabled.
- `InputSessionCommitPolicy`, Rime/native navigation, AI scheduling,
  candidate-panel publication, and host write behavior stay unchanged.
