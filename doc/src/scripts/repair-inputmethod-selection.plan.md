# scripts/repair-inputmethod-selection.sh

## Responsibility

Repairs common local Text Input Source and LaunchServices state problems for the
development input method bundle.

## Boundaries

- This is local developer-machine repair tooling, not product runtime logic.
- It must not change unrelated input sources beyond the documented KnowType
  cleanup steps.

## Behavior Notes

- The script replaces only scoped KnowType rows in Text Input Source preferences
  through `knowtype-inputsource-tool repair-preferences`: HIToolbox/history keep
  `.Hans`, `com.apple.inputsources` keeps the System Settings-compatible parent
  anchor plus `.Hans`, and unrelated sources are preserved. It also unregisters
  stale bundle records, restarts menu agents, and relaunches the installed app.
- It is used after diagnostics indicate stale local state, before falling back
  to logout.

## Tests

- `scripts/smoke-inputmethod-install.sh`
- Manual local acceptance after repair
