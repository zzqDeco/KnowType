# InputClientWriteCoordinator

## Responsibility

`InputClientWriteCoordinator` centralizes the low-level IMK client write calls
and privacy-safe write diagnostics used by `InputClientCompositionWriter`.

## Boundaries

- It performs `insertText`, typed marked-text `setMarkedText`, and write
  tracing only.
- It does not decide key handling, host compatibility mode, candidate content,
  owned marked-text lifecycle, or composition lifecycle.
- It must never log user text.

## Behavior Notes

- All ordinary write paths use `NSRange(location: NSNotFound, length:
  NSNotFound)` as the replacement range. Host-reported `markedRange` remains
  diagnostic and geometry input, not a trusted replacement range.
- `KNOWTYPE_CLIENT_WRITE_DEBUG=1` logs write kind, composition id, raw length,
  bundle id, write mode, handled/pass-through state, and reason through
  `InputDebugDiagnostics`. It intentionally does not log replacement ranges or
  user text.
- Commit-only placeholder writes use the distinct write kind supplied by
  `InputClientCompositionWriter`, so host compatibility diagnostics can
  distinguish them from raw inline preedit writes without logging user text.
- The writer preserves the marked-text carrier supplied by its caller. Inline
  preedit and commit-only placeholders are `NSAttributedString` payloads with
  marked attributes.

## Tests

- `InputClientCompositionWriterTests`
- `InputControllerCoordinatorTests`
