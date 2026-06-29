# Input Candidate Panel Publication Runtime Refactor

## Summary

- Extract candidate-panel publication lifecycle from
  `InputControllerCoordinator` into `InputCandidatePanelPublicationRuntime`.
- Keep behavior unchanged while reducing coordinator responsibility for panel
  state, presenter calls, async publication generation, delayed re-anchor
  gating, visibility reasons, and panel diagnostics.

## Scope

- Add `InputCandidatePanelPublicationRuntime` under
  `Sources/KnowTypeInputMethod`.
- Keep Rime/native candidate navigation, commit decisions, host marked-text
  writes, AI recommendation scheduling, and provider behavior in their existing
  owners.
- Keep `CandidatePanelRowBuilder`, `CandidatePanelState`,
  `CandidatePanelRenderer`, and `CandidatePanelWindowController` semantics
  unchanged.

## Implementation

- The coordinator builds publication snapshots and requests from raw input,
  composition id, raw revision, suggestion state, native highlight preference,
  AI slot state, runtime preferences, preedit display text, placement
  preference, and anchor facts.
- The publication runtime applies synchronous panel updates, schedules
  asynchronous panel updates behind raw/revision/composition stale guards,
  hides raw-empty and stale-suggestion snapshots, and schedules delayed
  re-anchor callbacks that can republish only matching active compositions.
- Selection helpers for visible panel rows moved to the runtime, while the
  coordinator still maps panel selection into Rime/native selection and commit
  behavior.

## Test Plan

- `swift test --quiet --filter InputCandidatePanelPublicationRuntimeTests`
- `swift test --quiet --filter CandidatePanelStateTests`
- `swift test --quiet --filter CandidatePanelRendererTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`

## Assumptions

- This is a refactor-only PR.
- `InputControllerCoordinator` remains the owner of Rime/native navigation and
  commit semantics because those paths directly interact with conversion-engine
  state.
