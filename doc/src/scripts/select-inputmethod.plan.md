# scripts/select-inputmethod.sh

## Responsibility

Requests selection of the KnowType input source through
`knowtype-inputsource-tool`, then optionally runs the read-only diagnostic.

## Boundaries

- Selection is scoped to macOS input context and is not proof of real typing in
  a frontmost app.
- Diagnostics remain the source of read-only install status.

## Behavior Notes

- Use after activating the target app when selection should apply there.
- `--require-selected` makes the follow-up diagnostic's selected-source check a
  hard gate.
- Without `--require-selected`, the helper selection request is
  best-effort: a `TISSelectInputSource` success continues to diagnostics even
  when that helper-local context still reports another current source.
- The helper bootstraps registration and enablement before requesting selection;
  the script never executes the installed IMK app as a maintenance process.
- Bootstrap selects the best enabled/select-capable `.Hans` record when stale
  duplicate TIS rows exist, and receives `--require-selected` only for the
  script's corresponding strict mode.
- A successful selection preflight still requires a manual typing probe.

## Tests

- `scripts/smoke-inputmethod-install.sh`
- Manual local IME acceptance
