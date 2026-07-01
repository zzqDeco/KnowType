# Input Source Menu Visible Mode Registration

## Status

Active

## Summary

KnowType returns to the mature macOS InputMethodKit registration model: `com.knowtype.inputmethod.KnowType` is the non-selectable parent input method, and `com.knowtype.inputmethod.KnowType.Hans` is the only visible user-selectable input mode. This replaces the parent-only single-source model because local acceptance showed that System Settings could list it while the menu bar still did not expose a switchable KnowType item.

## Scope

This plan covers input-source declaration, TIS registration/enable/selection tooling, install/repair/select scripts, diagnostics, tests, and documentation. It does not change Rime, AI, candidate panels, user language data, provider profiles, the bundle id, or the IMK connection name.

## Behavior

- `Resources/InputMethod/Info.plist` declares `ComponentInputModeDict` with exactly one visible `.Hans` input mode and keeps the parent `TISInputSourceID` unchanged.
- `InfoPlist.strings` gives the parent a container name and gives `.Hans` the user-visible `KnowType` / `知键` name.
- `KnowTypeInputSourceIDs.activeMode` is `.Hans`; `.Mode` is the legacy cleanup id. Parent-only selected/history rows from the single-source model are stale and must be migrated to `.Hans`.
- Default install registers and enables parent plus `.Hans` from the installed app CLI context, then uses helper preference repair without rewriting selected preferences.
- Install preflight rejects parent-only bundles and older component-mode bundles whose menu-visible input mode list is missing, has more than one entry, or is not exactly the current `.Hans` id, including `--from-bundle`, `--from-release-zip`, and DMG payload sources.
- Explicit repair cleans stale LaunchServices records, disables `.Mode`, restores enabled parent plus `.Hans`, refreshes menu agents, and rewrites selected preferences only after installed app selection reports `.Hans` as the current source, not merely after a zero select status.
- Rollback derives the active mode from the restored bundle before helper preference repair. Parent-only backups from the single-source experiment are rejected instead of being repaired with the current `.Hans` id.

## Validation

- Static tests assert one visible `.Hans` mode, distinct parent/mode localized names, and aligned Swift/shell/plist IDs.
- Helper/script tests assert parent enablement, `.Hans` selection, parent-only selected/history cleanup, and no return to the single-source model.
- Manual acceptance requires both System Settings and the menu bar to show exactly one user-selectable `KnowType` / `知键`, and typing in a real app after selection must work.
