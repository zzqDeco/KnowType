# InputCandidatePanelPublicationRuntime

## Responsibility

`InputCandidatePanelPublicationRuntime` owns candidate-panel publication for the
IMK coordinator.

It holds `CandidatePanelState`, the `CandidatePanelPresenter`, panel-render
task generation, candidate-frame presentation generation, delayed re-anchor
generation, visibility decisions, and privacy-safe panel diagnostics.

## Boundaries

- It may update candidate-panel state and call `CandidatePanelPresenter`.
- It is the only owner of `CandidatePanelFrame.presentationGeneration`.
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
- Every visible, hidden, stale-update, and layout-impossible publication crosses
  the host boundary as a `CandidatePanelFrame` with a monotonic presentation
  generation.
- Asynchronous publication applies only when raw input, raw revision, and
  composition id still match the scheduled snapshot.
- Empty raw input and stale suggestion snapshots hide the panel with explicit
  visibility reasons.
- Anchor source `.none` publishes an undisplayable panel frame rather than using
  the explicit hide path, preserving the existing layout-impossible behavior.
- Delayed re-anchor applies only to the latest same-raw-input,
  same-composition active snapshot.
- Hidden frames cancel pending panel-render work and delayed re-anchor work, so
  old visible frames cannot revive the panel after commit, reset, deactivate, or
  close.
- Selection helpers mutate visible panel rows but leave Rime/native commit and
  highlight semantics in `InputControllerCoordinator`.

## Tests

- `InputCandidatePanelPublicationRuntimeTests`
- `CandidatePanelStateTests`
- `CandidatePanelRendererTests`
- `InputControllerCoordinatorTests`
- `InputHotPathPerformanceTests`
- `swift test`
