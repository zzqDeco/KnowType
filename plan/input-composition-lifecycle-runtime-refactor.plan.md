# Input Composition Lifecycle Runtime Refactor

Status: Delivered

## Summary

Extract pure composition begin and finish lifecycle planning from
`InputControllerCoordinator` into `InputCompositionLifecycleRuntime`.

This is a pure refactor. It does not change key handling, Rime conversion, host
writes, candidate-panel publication, AI recommendation or learning, lexical
side effects, input-mode policy, or install tooling.

## Scope

- Move lifecycle finish reasons and reason-to-panel mapping into
  `InputCompositionLifecycleRuntime`.
- Move first composition begin trace-once state out of the coordinator.
- Keep the coordinator as the side-effect order owner for begin and finish
  paths.
- Keep `InputCommitApplicationRuntime` focused on commit-result plans and
  commit side-effect contexts.
- Add focused lifecycle runtime tests and update source notes plus plan indexes.

## Non-Goals

- Do not split `refreshComposition`, host composition writes, candidate-panel
  publication, Rime conversion, AI runtime, lexical runtime, or input source
  installation.
- Do not change `InputCompositionStateRuntime` state semantics.
- Do not change user-visible composition, commit, reset, deactivate, close, or
  native-ended behavior.

## Validation

- `swift test --quiet --filter InputCompositionLifecycleRuntimeTests`
- `swift test --quiet --filter InputCommitApplicationRuntimeTests`
- `swift test --quiet --filter InputCompositionStateRuntimeTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputClientCompositionWriterTests`
- `swift test --quiet --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`

## Assumptions

- Lifecycle plans are value-only outputs; the coordinator remains responsible
  for all host, Rime, panel, AI, lexical, preference, and event side effects.
- Finish plans are built from the pre-reset composition snapshot.
- First composition begin tracing stays privacy-safe and emits metadata only.
