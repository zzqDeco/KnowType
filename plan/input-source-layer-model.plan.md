# Input Source Layer Model

## Status

Active

## Summary

KnowType separates macOS Text Input Source parent records from the single user-selectable visible input mode.

- `com.knowtype.inputmethod.KnowType` is the non-selectable parent / IMK server identity.
- `com.knowtype.inputmethod.KnowType.Hans` is the visible user input mode.
- User preference repair restores only `.Hans`; parent rows are diagnostic/container state, not healthy enabled/history targets.

## Scope

This plan only covers input-source registration, preferences, diagnostics, scripts, and documentation. It does not change Rime, AI, candidate panel behavior, input hot paths, or user data.

## Behavior

- `tsVisibleInputModeOrderedArrayKey` contains only `.Hans`.
- `.Hans` keeps the user-facing localized name `KnowType` / `知键`.
- The parent record uses a container-style localized name when surfaced by diagnostics: `KnowType Input Method` / `知键输入法容器`.
- `knowtype-inputsource-tool repair-preferences --add-active` removes stale parent and legacy `.Mode` rows from user preference arrays and adds only `.Hans`.
- `--legacy-parent-anchor` is the explicit compatibility escape hatch for macOS builds that prove they still require a parent preference row.
- `status` reports the count of unique enabled and select-capable KnowType IDs across the parent, `.Hans`, and legacy cleanup modes; healthy default state is exactly one. Disabled stale TIS cache records remain visible through `legacy.mode.count` warnings, not the strict visible-mode gate.
- `diagnose-inputmethod.sh --legacy-parent-anchor` is the explicit strict-diagnostic companion for the helper's legacy parent-anchor compatibility fallback.

## Validation

- `Info.plist` and localization tests assert `.Hans` is the only visible input mode and parent display names differ from the user-facing mode.
- Helper tests assert default repair does not re-add the parent row.
- Diagnostics distinguish parent registration from user-selectable mode health.
