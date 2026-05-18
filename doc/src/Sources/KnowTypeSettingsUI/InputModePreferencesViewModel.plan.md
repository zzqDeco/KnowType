# InputModePreferencesViewModel

## Responsibility

`InputModePreferencesViewModel` edits saved punctuation language and symbol
width defaults for normal apps and code-style apps.

## Boundaries

- Persistence models live in `KnowTypeCore`.
- Runtime application of preferences belongs to the input-method controller and
  session state.

## Behavior Notes

- Edits publish through the shared `com.knowtype.preferences` defaults domain.
- Preferences refresh at new composition or direct-symbol boundaries; active
  marked text should not be rewritten by settings changes.

## Tests

- `InputModePreferencesViewModelTests`
- `InputModePreferencesTests`
