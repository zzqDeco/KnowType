# InputModePreferences

## Responsibility

`InputModePreferences` defines persisted input-mode defaults shared by settings
and the input-method runtime.

## Boundaries

- It stores preference data and policy defaults only; IMK key handling stays in
  `KnowTypeInputMethod`.
- It does not decide candidate rows, provider eligibility, or Level 0
  protection.

## Behavior Notes

- Normal-app and code-app defaults are stored in the shared
  `com.knowtype.preferences` defaults domain.
- Text mode, punctuation language, and symbol width are separate fields.
- Code-style app defaults include terminal, editor, Codex, Electron, and
  JetBrains-style bundle identifiers. They use ASCII text mode with Chinese
  punctuation and half-width symbols.
- The Chinese text pipeline remains available when the active session switches
  to Chinese text mode.

## Tests

- `InputModePreferencesTests`
- `InputModePreferencesViewModelTests`
- `InputSymbolModeTests`
