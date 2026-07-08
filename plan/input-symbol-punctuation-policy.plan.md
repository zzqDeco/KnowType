# Input Symbol Punctuation Policy

## Summary

Fix the Chinese punctuation path so Chinese input mode no longer feels like an
implicit full-width symbol mode. KnowType already stores text mode,
punctuation style, and symbol width as separate state; this slice makes the
local punctuation transformer and Settings copy match that model.
This follows Rime's mature split between `ascii_punct` and `full_shape` rather
than treating Chinese punctuation as a full-width symbol switch.

## Scope

- Narrow local Chinese punctuation mapping in the input-method target.
- Change built-in code-app defaults to Chinese text input with English
  punctuation and half-width symbols, while preserving saved user preferences.
- Clarify Settings copy so users see "punctuation style" and "character width"
  as separate controls.
- Update source notes, README shortcut docs, and regression tests.

Non-goals: no Rime schema changes, AI changes, candidate ranking changes,
installer changes, or preference migration that overwrites saved user choices.

## Implementation

- `InputSymbolTransformer` treats all ASCII symbol keys as symbol input, but
  maps only Chinese sentence punctuation, Chinese brackets, book-title marks,
  and `/` to Chinese punctuation in half-width mode.
- Code/path/operator symbols such as `-`, `_`, `+`, `=`, `\`, `@`, `#`, `$`,
  `%`, `^`, `&`, `*`, `|`, `~`, `` ` ``, `{`, and `}` stay ASCII unless the
  explicit full-width setting is enabled.
- `InputModePreferences.standard.codeAppState` uses English punctuation and
  half-width symbols. Non-terminal code apps still inherit the normal Chinese
  text mode, so composition can start immediately while idle symbols stay
  code-friendly.
- Saved `input.codeApp.*` preferences continue to win over the built-in
  defaults.

## Test Plan

- `swift test --quiet --filter InputSymbolModeTests`
- `swift test --quiet --filter InputModePreferencesTests`
- `swift test --quiet --filter InputModePreferencesViewModelTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test`
- `git diff --check`

Manual acceptance:

- In TextEdit or Chrome, `nihao,` commits the Rime candidate plus `，`.
- In TextEdit or Chrome, `- _ + = @ #` remain ASCII in half-width mode.
- In Codex, VS Code, or Xcode, Chinese composition still starts on letters, but
  idle `/`, `{}`, `-`, and `_` remain ASCII.
- When full-width symbols are explicitly enabled, ASCII symbols become
  full-width as expected.

## Assumptions

- `/` remains the normal Chinese dunhao entry in non-code Chinese punctuation.
- Code-app English punctuation defaults apply only when no saved user
  preference exists or after reset-to-defaults.
