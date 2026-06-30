# InputCompositionLifecycleRuntime

## Responsibility

`InputCompositionLifecycleRuntime` owns pure composition lifecycle decisions for
begin and finish paths.

- Begin plans decide whether the current composition snapshot is idle enough to
  start a new lifecycle.
- The runtime owns first-composition-begin trace-once state and returns whether
  the coordinator should emit the startup timing event.
- Finish plans map lifecycle reasons to candidate-panel visibility reasons,
  preserve the finishing composition id, carry optional lifecycle commit text,
  and decide whether owned marked text should be cleared for composition endings
  without inserted text.

## Boundaries

- The runtime returns plans only. It must not call host clients, Rime, candidate
  panel presenters, AI runtimes, lexical runtimes, preference stores, or the
  event bus.
- `InputCompositionStateRuntime` remains the owner of raw input,
  `CompositionBuffer`, composition id, raw revision, and delete count.
- `InputControllerCoordinator` remains the owner of side-effect order: panel
  hide, commit side effects, host insert or marked-text clear, Rime reset,
  composition-state reset, anchor reset, suggestion invalidation, writer
  lifecycle cleanup, and lifecycle event publication.

## Behavior Notes

- Finish reason raw values remain stable: `commit`, `deactivate`, `close`,
  `reset`, and `native_ended`.
- Composition begin is a no-op while the snapshot has active raw text or
  resolved segments.
- Finish plans use the pre-reset snapshot so `compositionEnded` events and
  lexical side-effect contexts keep the finishing composition id.

## Tests

- `InputCompositionLifecycleRuntimeTests`
- `InputControllerCoordinatorTests`
- `InputCompositionStateRuntimeTests`
- `InputClientCompositionWriterTests`
