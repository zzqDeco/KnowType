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
- Code-style app defaults still keep the Chinese text pipeline available unless
  the user explicitly changes behavior through settings.

## Tests

- `InputModePreferencesTests`
- `InputModePreferencesViewModelTests`
- `InputSymbolModeTests`
