# scripts/repair-inputmethod-selection.sh

## Responsibility

Repairs common local Text Input Source and LaunchServices state problems for the development input method bundle.

## Boundaries

- This is local developer-machine repair tooling, not product runtime logic.
- It must not change unrelated input sources beyond the documented KnowType cleanup steps.
- It must not launch the installed input-method host as part of repair.

## Behavior Notes

- The script replaces only scoped KnowType rows in Text Input Source preferences through `knowtype-inputsource-tool repair-preferences`.
- The current target is the single user-selectable `com.knowtype.inputmethod.KnowType` input source.
- Legacy `.Hans` and `.Mode` rows are removed from enabled, selected, history, and third-party preference targets.
- Helper-local `bootstrap --select` is used only as a selection preflight. If it verifies the current source changed to KnowType, selected repair places the single KnowType input source first and posts the selected-source notification.
- If selection fails or cannot be verified, the script skips selected repair instead of claiming KnowType is selected.
- The script unregisters stale LaunchServices records, restarts menu agents, and continues refresh/diagnostics if helper-local selection fails.

## Tests

- `scripts/smoke-inputmethod-install.sh`
- Manual local acceptance after repair
