# Input Source Layer Model

## Status

Active

## Summary

KnowType separates macOS Text Input Source parent records from the single user-selectable visible input mode.

- `com.knowtype.inputmethod.KnowType` is the non-selectable parent / IMK server identity.
- `com.knowtype.inputmethod.KnowType.Hans` is the visible user input mode.
- User preference repair restores the parent enabled anchor plus `.Hans` in enabled preferences; selected/history preferences remain `.Hans` only.

## Scope

This plan only covers input-source registration, preferences, diagnostics, scripts, and documentation. It does not change Rime, AI, candidate panel behavior, input hot paths, or user data.

## Behavior

- `tsVisibleInputModeOrderedArrayKey` contains only `.Hans`.
- `.Hans` keeps the user-facing localized name `KnowType` / `知键`.
- The parent record uses a container-style localized name when surfaced by diagnostics: `KnowType Input Method` / `知键输入法容器`.
- `knowtype-inputsource-tool repair-preferences --add-active` removes legacy `.Mode` rows, then adds the parent enabled anchor plus `.Hans` to enabled preferences. Explicit selection repair additionally passes `--include-selected` to remove stale selected parent rows and write selected preferences to `.Hans`.
- `--legacy-parent-anchor` is retained as a deprecated compatibility no-op because the parent anchor is now the default enabled-state shape.
- `status` reports the count of unique enabled and select-capable KnowType IDs across the parent, `.Hans`, and legacy cleanup modes; healthy default state is exactly one. Disabled stale TIS cache records remain visible through `legacy.mode.count` warnings, not the strict visible-mode gate.
- Diagnostics treat parent enabled plus non-selectable as healthy; parent in selected/history remains stale.

## Validation

- `Info.plist` and localization tests assert `.Hans` is the only visible input mode and parent display names differ from the user-facing mode.
- Helper tests assert default repair adds the parent enabled anchor without changing selected preferences, and explicit selection repair keeps selected/history on `.Hans` without putting the parent there.
- Diagnostics distinguish parent registration from user-selectable mode health.
