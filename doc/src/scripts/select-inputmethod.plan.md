# scripts/select-inputmethod.sh

## Responsibility

Requests selection of the KnowType input source through the installed
`KnowTypeInputMethodApp` command-line activation path, then optionally runs the
read-only diagnostic.

## Boundaries

- Selection is scoped to macOS input context and is not proof of real typing in
  a frontmost app.
- Diagnostics remain the source of read-only install status.

## Behavior Notes

- Use after activating the target app when selection should apply there.
- `--require-selected` makes the follow-up diagnostic's selected-source check a
  hard gate.
- Without `--require-selected`, the installed app selection request is
  best-effort: a `TISSelectInputSource` success continues to diagnostics even
  when that helper-local context still reports another current source.
- A successful selection preflight still requires a manual typing probe.

## Tests

- `scripts/smoke-inputmethod-install.sh`
- Manual local IME acceptance
