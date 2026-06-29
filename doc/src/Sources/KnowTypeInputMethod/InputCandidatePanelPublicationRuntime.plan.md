# InputCandidatePanelPublicationRuntime

## Responsibility

`InputCandidatePanelPublicationRuntime` owns candidate-panel publication for the
IMK coordinator.

It holds `CandidatePanelState`, the `CandidatePanelPresenter`, panel-render
task generation, delayed re-anchor generation, visibility decisions, and
privacy-safe panel diagnostics.

## Boundaries

- It may update candidate-panel state and call `CandidatePanelPresenter`.
- It may use `InputTaskSupervisor` for `.panelRender` task replacement and
  cancellation.
- It may schedule delayed re-anchor callbacks through `InputControllerHost`.
- It must not access Rime conversion, process keys, choose commit results,
  write marked text, insert text, schedule AI provider requests, or decide host
  carrier modes.
- The coordinator still supplies raw input, composition id, raw revision,
  suggestion snapshots, preferred native highlight, AI slot state, placement,
  preedit display text, and resolved anchor facts.

## Behavior Notes

- Synchronous publication cancels pending panel-render work before applying the
  current state.
- Asynchronous publication applies only when raw input, raw revision, and
  composition id still match the scheduled snapshot.
- Empty raw input and stale suggestion snapshots hide the panel with explicit
  visibility reasons.
- Anchor source `.none` publishes an undisplayable panel frame rather than using
  the explicit hide path, preserving the existing layout-impossible behavior.
- Delayed re-anchor applies only to the latest same-raw-input,
  same-composition active snapshot.
- Selection helpers mutate visible panel rows but leave Rime/native commit and
  highlight semantics in `InputControllerCoordinator`.

## Tests

- `InputCandidatePanelPublicationRuntimeTests`
- `CandidatePanelStateTests`
- `CandidatePanelRendererTests`
- `InputControllerCoordinatorTests`
- `InputHotPathPerformanceTests`
- `swift test`
