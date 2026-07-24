# InputActiveSessionRuntime

## Responsibility

`InputActiveSessionRuntime` is the sole owner of active text or symbol
composition state. It exposes immutable snapshots and value-only transition
plans for the coordinator.

## Boundaries

- `ActiveInputSession` is exactly one of `none`, `text`, or `symbol`.
- Text state delegates storage mechanics to `InputCompositionStateRuntime`.
- Symbol state owns trigger, immutable candidates, selection, monotonic id,
  revision, page size, captured host identity/ranges, and lifecycle policies.
- The runtime does not call Rime, host clients, marked-text writers, panels, AI,
  learning stores, preferences, or diagnostics.

## Behavior Notes

- A symbol session cannot begin until text composition has completed.
- Arrow and page navigation clamp while still returning an update plan; revision
  advances only when the selected index changes.
- Repeating the same trigger cycles selection. Visible numbers select and
  commit; invalid numbers and other printable intents commit the current symbol
  and request one replay.
- Host shortcuts cancel and remain unhandled. Escape and Backspace cancel and
  are handled.
- Valid click/focus/commit lifecycle events commit. Missing-client focus,
  reset, close, and input-mode generation changes cancel.
- No transition plan contains host text, Provider data, or AI output.

## Tests

- `InputActiveSessionRuntimeTests`
- `InputControllerCoordinatorTests`

