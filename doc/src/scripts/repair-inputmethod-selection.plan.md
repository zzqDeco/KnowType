# scripts/repair-inputmethod-selection.sh

## Responsibility

Repairs common local Text Input Source and LaunchServices state problems for the development input method bundle.

## Boundaries

- This is local developer-machine repair tooling, not product runtime logic.
- It must not change unrelated input sources beyond the documented KnowType cleanup steps.
- It must not launch the installed input-method host as part of repair.

## Behavior Notes

- The script replaces only scoped KnowType rows in Text Input Source preferences through `knowtype-inputsource-tool repair-preferences`.
- The current target is the visible user-selectable `com.knowtype.inputmethod.KnowType.Hans` input mode.
- Legacy `.Mode` rows and parent-only selected/history rows are removed from preference targets.
- The script uses helper `bootstrap` before preference repair so a missing
  `.Hans` registration can be restored without launching the IMK host.
- Helper-local `select` is used as the selection preflight. The script must
  verify `select.current == com.knowtype.inputmethod.KnowType.Hans`; a zero
  `TISSelectInputSource` status alone is not enough to rewrite selected
  preferences.
- If selection fails or cannot be verified, the script skips selected repair instead of claiming KnowType is selected.
- The script unregisters stale LaunchServices records, restarts menu agents, and continues refresh/diagnostics if installed app selection fails.

## Tests

- `scripts/smoke-inputmethod-install.sh`
- Manual local acceptance after repair
