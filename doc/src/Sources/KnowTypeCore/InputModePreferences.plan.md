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
  JetBrains-style bundle identifiers for punctuation and symbol-width defaults.
  This is independent from host marked-text carrier selection.
- Terminal-style apps, including Terminal, iTerm, MacVim, and Emacs-style
  bundles, keep the code-app ASCII text default. Editor, Codex, Electron, and
  JetBrains-style apps inherit the normal text-mode default so Chinese
  composition can start immediately while still using code-app punctuation and
  symbol-width defaults. The built-in code-app punctuation default is English
  and symbol width remains half-width unless saved preferences override it.
- The ASCII text pipeline remains available when the active session switches
  through the session-local text-mode toggle.

## Tests

- `InputModePreferencesTests`
- `InputModePreferencesViewModelTests`
- `InputSymbolModeTests`
