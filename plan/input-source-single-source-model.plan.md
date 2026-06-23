# Input Source Single Source Model

## Status

Active

## Summary

KnowType now uses a single non-mode-enabled macOS Text Input Source. The user-selectable input source id is `com.knowtype.inputmethod.KnowType`, which is also the bundle/IMK identity. The older `com.knowtype.inputmethod.KnowType.Hans` and `.Mode` records are legacy cleanup targets only.

## Scope

This plan covers input-source declaration, helper behavior, install/repair/select scripts, diagnostics, tests, and documentation. It does not change Rime, AI, candidate panels, user language data, provider profiles, bundle id, or the IMK connection name.

## Behavior

- `Resources/InputMethod/Info.plist` declares `TISInputSourceID = com.knowtype.inputmethod.KnowType` and does not declare `ComponentInputModeDict`.
- `InfoPlist.strings` localizes only the single active source as `KnowType` / `知键`.
- `KnowTypeInputSourceIDs.activeMode` is equal to `KnowTypeInputSourceIDs.parent`; `.Hans` and `.Mode` are listed as legacy cleanup ids.
- `knowtype-inputsource-tool bootstrap` registers and enables the single active source. `select` selects that same source.
- `repair-preferences --add-active` writes one `Keyboard Input Method` row for the active source and removes legacy `.Hans` / `.Mode` rows from enabled, selected, history, and third-party preference arrays.
- Diagnostics are healthy when the single input source is found, enabled, select-capable, and de-duplicated to one active registration. Legacy `.Hans` / `.Mode` cache rows are reported separately.
- Install and rollback still avoid launching the input-method host; if macOS prelaunches the host, cold-start runtime boundaries keep user data lazy.

## Validation

- Static tests assert `Info.plist` has no `ComponentInputModeDict`, shell and Swift IDs match, and localization no longer exposes `.Hans`.
- Helper/script tests assert bootstrap, repair, diagnose, install, rollback, and select target the single source and treat `.Hans` / `.Mode` as legacy.
- Manual acceptance should show exactly one `KnowType` / `知键` in System Settings and the menu bar after repair/cache refresh.
