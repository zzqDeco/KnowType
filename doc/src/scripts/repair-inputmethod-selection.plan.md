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
  through `knowtype-inputsource-tool repair-preferences --include-selected`:
  enabled preferences keep the non-selectable parent anchor plus the single
  user-selectable `.Hans` mode, while HIToolbox selected/history preferences
  keep only `.Hans`.
  Legacy `.Mode` rows and stale selected/history parent rows are removed from
  user preference targets. It also unregisters stale bundle records, restarts
  menu agents, and uses helper `purge-legacy` plus `bootstrap --select`; it does
  not launch the installed input-method host and continues refresh/diagnostics
  if helper-local selection returns `paramErr/-50`.
- It is used after diagnostics indicate stale local state, before falling back
  to logout.

## Tests

- `scripts/smoke-inputmethod-install.sh`
- Manual local acceptance after repair
