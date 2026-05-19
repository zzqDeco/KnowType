# scripts/repair-inputmethod-selection.sh

## Responsibility

Repairs common local Text Input Source and LaunchServices state problems for the
development input method bundle.

## Boundaries

- This is local developer-machine repair tooling, not product runtime logic.
- It must not change unrelated input sources beyond the documented KnowType
  cleanup steps.

## Behavior Notes

- The script backs up Text Input Source preferences, removes duplicate KnowType
  rows, unregisters stale bundle records, restarts menu agents, and relaunches
  the installed app.
- It is used after diagnostics indicate stale local state, before falling back
  to logout.

## Tests

- `scripts/smoke-inputmethod-install.sh`
- Manual local acceptance after repair
