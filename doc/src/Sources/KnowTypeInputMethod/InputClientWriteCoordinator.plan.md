# InputClientWriteCoordinator

## Responsibility

`InputClientWriteCoordinator` centralizes IMK client writes and privacy-safe
write diagnostics for `InputControllerCoordinator`.

## Boundaries

- It performs `insertText`, `setMarkedText`, and write-decision tracing only.
- It does not decide key handling, host compatibility mode, candidate content,
  or composition lifecycle.
- It must never log user text.

## Behavior Notes

- All ordinary write paths use `NSRange(location: NSNotFound, length:
  NSNotFound)` as the replacement range. Host-reported `markedRange` remains
  diagnostic and geometry input, not a trusted replacement range.
- `KNOWTYPE_CLIENT_WRITE_DEBUG=1` logs write kind, composition id, raw length,
  bundle id, write mode, handled/pass-through state, selected range, reported
  marked range, chosen replacement range, and reason.
- Commit-only placeholder writes use a distinct write kind so host compatibility
  diagnostics can distinguish them from raw inline preedit writes without
  logging user text.

## Tests

- `InputControllerCoordinatorTests`
