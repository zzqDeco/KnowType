# InputModePreferencesViewModel

## Responsibility

`InputModePreferencesViewModel` edits the one saved global character-width
default shown in Settings.

## Boundaries

- Runtime Chinese/ASCII and punctuation toggles are ephemeral process state and
  are not Settings fields.
- Persistence models live in `KnowTypeCore`; runtime application belongs to the
  input-method state runtime.

## Behavior Notes

- `setGlobalSymbolWidth` writes through the shared
  `com.knowtype.preferences` defaults domain.
- Reset restores half-width. The next input boundary applies an external width
  change to the shared process runtime without rewriting active text.
- Settings explains the three shortcuts and the text/punctuation linkage but
  does not expose the retired normal-app/code-app mode groups.

## Tests

- `InputModePreferencesViewModelTests`
- `InputModePreferencesTests`
