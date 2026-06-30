# Input Native Candidate Navigation Runtime Refactor

Status: Delivered

## Summary

- Extract Rime/native candidate navigation from `InputControllerCoordinator`
  into `InputNativeCandidateNavigationRuntime`.
- Keep behavior unchanged while reducing coordinator responsibility for
  displayed native candidate caching, panel selection mapping, hover highlight,
  numeric current-page selection, paging, boundary paging, and stable native
  index matching.

## Scope

- Add `InputNativeCandidateNavigationRuntime` under
  `Sources/KnowTypeInputMethod`.
- Keep commit policy, host marked-text writes, candidate-panel publication,
  AI recommendation/acceptance, lexical profile refresh, and installation
  tooling in their existing owners.
- Keep `InputCandidateSelection`, `CandidatePanelSelection`, Rime snapshot, and
  shortcut public shapes unchanged.

## Implementation

- The runtime owns displayed input selections and the current selected
  candidate. It maps panel selections back to `InputCandidateSelection` while
  preserving encoded Rime current-page native indexes.
- The runtime calls `KnowTypeConversionEngine.process` only for native
  navigation keys: current-page select, current-page highlight, PageUp, and
  PageDown.
- The runtime returns `InputNativeCandidateNavigationResult` values containing
  handled state, optional conversion results, and presentation effects. The
  coordinator applies those effects, learns final native commits, handles
  conversion results, refreshes candidate-panel state, and performs host writes.
- Space precedence remains in the coordinator: explicit non-Rime rows can win
  before native Space, and selected non-highlighted native rows are selected by
  stable current-page index before generic Rime Space handling.

## Test Plan

- `swift test --quiet --filter InputNativeCandidateNavigationRuntimeTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputCandidatePanelPublicationRuntimeTests`
- `swift test --quiet --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`

## Assumptions

- This is a refactor-only PR.
- The runtime can drive Rime navigation keys, but conversion result side effects
  remain in `InputControllerCoordinator`.
- Native candidate navigation stays separate from candidate-panel publication
  and host/client write state.
