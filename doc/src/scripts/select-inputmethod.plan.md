# scripts/select-inputmethod.sh

## Responsibility

Requests selection of the KnowType input source through
`knowtype-inputsource-tool` and optionally verifies helper-local selection.

## Boundaries

- Selection is scoped to macOS input context and is not proof of real typing in
  a frontmost app.
- Diagnostics remain the source of read-only install status.

## Behavior Notes

- Use after activating the target app when selection should apply there.
- `--require-selected` makes helper-local selection a hard gate.
- A successful helper selection still requires a manual typing probe.

## Tests

- `scripts/smoke-inputmethod-install.sh`
- Manual local IME acceptance
