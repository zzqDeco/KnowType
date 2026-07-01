# Input Turn Sequencing Runtime Refactor

Status: Active

## Summary

Extract the remaining order-sensitive input turn side-effect sequencing from
`InputControllerCoordinator` into `InputTurnSequencingRuntime`.

This is a value-only refactor. The coordinator still executes Rime, host
writing, candidate-panel publication, AI/lexical side effects, and event
publication. The new runtime makes the required order explicit for commit,
native conversion, lifecycle finish, and direct passthrough paths.

## Implementation Notes

- Add `InputTurnSequencingRuntime` with `InputTurnToken`,
  `InputTurnEffectSequence`, and `InputTurnEffect` value types.
- Keep `InputCommitDecisionRuntime` responsible for choosing what action wins,
  and `InputCommitApplicationRuntime` responsible for commit result/context
  construction.
- Make coordinator paths execute ordered effect sequences instead of embedding
  commit, insert, reset, panel hide, and lifecycle event ordering inline.
- Preserve candidate-panel frame generation and stale gates in
  `InputCandidatePanelPublicationRuntime`; turn sequencing does not replace
  panel-frame ordering.

## Validation

- `swift test --quiet --filter InputTurnSequencingRuntimeTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputControllerCoordinatorRefactorRegressionTests`
- `swift test --quiet --filter InputCommitApplicationRuntimeTests`
- `swift test --quiet --filter InputCompositionLifecycleRuntimeTests`
- `swift test --quiet --filter InputCandidatePanelPublicationRuntimeTests`
- `swift test --quiet --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`

## Acceptance

- User-visible behavior remains unchanged for commit, reset, deactivate, close,
  native partial commit, direct passthrough, post-insert verification, and
  candidate-panel hide/show ordering.
- The new runtime can be tested without host clients, Rime engine instances,
  AppKit panels, AI providers, lexical stores, or event buses.
