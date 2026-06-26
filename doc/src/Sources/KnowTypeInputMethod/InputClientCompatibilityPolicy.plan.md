# InputClientCompatibilityPolicy

## Responsibility

`InputClientCompatibilityPolicy` maps the focused host app, current
`InputModeState`, composition activity, and client availability to an
`InputClientWriteMode`.

## Boundaries

- It decides write mode only. Key mapping, composition state, candidate rows,
  and host writes stay in `InputControllerCoordinator`.
- It must not inspect or log user text.
- Per-host overrides are read from UserDefaults, but no settings UI is owned
  here.

## Behavior Notes

- Unknown hosts use `inlineComposition` so standard AppKit clients keep marked
  text behavior.
- Compatibility hosts use `asciiPassthrough` while idle only when the active
  input mode is ASCII. Terminal-style hosts start in ASCII mode; editor, Codex,
  Electron, and JetBrains-style hosts start in Chinese mode so composition and
  candidate rows can begin immediately.
- During active Chinese composition, compatibility hosts use
  `commitOnlyComposition`: KnowType writes a full-width-space marked-text
  placeholder to keep the host composition and candidate anchor alive without
  exposing raw pinyin, then commits with `insertText`.
- `Option + /` is the supported session-local path for switching compatibility
  hosts between Chinese commit-only composition and idle ASCII passthrough.
- Missing clients use `disabled`, allowing printable idle input to return
  unhandled rather than being swallowed.
- Override keys use `input.client.<bundle id>.writeMode` in the shared
  `com.knowtype.preferences` defaults domain.

## Tests

- `InputClientCompatibilityPolicyTests`
- `InputControllerCoordinatorTests`
- `InputSymbolModeTests`
