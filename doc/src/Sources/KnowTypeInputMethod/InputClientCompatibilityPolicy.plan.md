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
- Code and terminal-style hosts use `asciiPassthrough` while idle unless the
  active input mode is Chinese.
- During active Chinese composition, compatibility hosts use
  `commitOnlyComposition`: KnowType updates its internal buffer and candidate
  panel, then commits with `insertText` without calling `setMarkedText`.
- Missing clients use `disabled`, allowing printable idle input to return
  unhandled rather than being swallowed.
- Override keys use `input.client.<bundle id>.writeMode` in the shared
  `com.knowtype.preferences` defaults domain.

## Tests

- `InputClientCompatibilityPolicyTests`
- `InputControllerCoordinatorTests`
- `InputSymbolModeTests`
