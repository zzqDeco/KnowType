# Input Symbol Punctuation Policy

Status: Absorbed by
[input-mode-punctuation-linkage.plan.md](input-mode-punctuation-linkage.plan.md)
and [rime-mode-option-sync.plan.md](rime-mode-option-sync.plan.md).

## Summary

Fix the Chinese punctuation path so Chinese input mode no longer feels like an
implicit full-width symbol mode. KnowType already stores text mode,
punctuation style, and symbol width as separate state; this slice makes the
local punctuation transformer and Settings copy match that model.
This follows Rime's mature split between `ascii_punct` and `full_shape` rather
than treating Chinese punctuation as a full-width symbol switch.

## Scope

- Narrow local Chinese punctuation mapping in the input-method target.
- Keep host compatibility independent from the process-global text,
  punctuation, and width state.
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
- Legacy default/code-app fields remain readable but do not influence the
  process runtime.

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
- Switching among TextEdit, Codex, VS Code, Xcode, and Terminal preserves the
  current process-global mode.
- When full width is enabled, printable ASCII and normal space become
  full-width characters in every app.

## Assumptions

- `/` remains the normal Chinese dunhao entry in non-code Chinese punctuation.
- Host carrier overrides do not change input mode.
