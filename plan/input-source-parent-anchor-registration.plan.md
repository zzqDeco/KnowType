# Input Source Parent Anchor Registration

## Status

Active

## Summary

KnowType keeps the macOS Text Input Source hierarchy from the layer-model work:

- `com.knowtype.inputmethod.KnowType` is the non-selectable parent / IMK server identity.
- `com.knowtype.inputmethod.KnowType.Hans` is the single user-visible, select-capable input mode.

This fix changes the enabled-state contract. The parent is a required enabled anchor, not a second menu item. Enabled preferences should contain parent plus `.Hans`; selected and history preferences should contain only `.Hans`.

## Scope

This plan covers registration, enablement, preference repair, diagnostics, scripts, and documentation. It does not change input-source IDs, Rime, AI, candidate panel behavior, input hot paths, or user data.

## Behavior

- `tsVisibleInputModeOrderedArrayKey` still contains only `.Hans`.
- Parent localized names stay container-like: `KnowType Input Method` / `知键输入法容器`.
- `knowtype-inputsource-tool bootstrap` registers the installed bundle when needed, waits for parent and `.Hans`, then enables both through TIS.
- `knowtype-inputsource-tool select` enables parent and `.Hans` before calling `TISSelectInputSource(.Hans)`.
- `repair-preferences --add-active` writes parent plus `.Hans` to enabled lists, writes only `.Hans` to history when `--include-history` is present, and removes legacy `.Mode`. `--include-selected` is only used by explicit selection repair so default install/rollback do not rewrite selected preferences.
- `scripts/repair-inputmethod-selection.sh` continues refresh and diagnostics even when helper-local selection returns `paramErr/-50`.
- Diagnostics are healthy when parent is enabled and non-selectable, `.Hans` is enabled and select-capable, and the visible KnowType mode count is one.
- Parent in enabled preferences is normal; parent in selected/history remains stale.

## Rationale

Apple Text Input Source Services requires the parent input method to be enabled before an input mode can be selected. Mature IMK input methods such as Squirrel, McBopomofo, and Mozc use a parent input method with visible modes; the user selects the visible mode, while the parent can exist as an enabled anchor.

## Validation

- Static tests cover Info.plist visible mode shape, parent/mode enable calls, preference repair shape, and diagnostics wording.
- Script smoke checks run without installing or selecting a real input source.
- Manual acceptance should show exactly one user-selectable `KnowType` / `知键` menu item, while helper status reports the parent enabled and non-selectable.
