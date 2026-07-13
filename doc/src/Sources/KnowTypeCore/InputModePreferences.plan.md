# InputModePreferences

## Responsibility

`InputModePreferences` persists the global default symbol width used when a new
input-method host process creates its input-mode state machine.

## Boundaries

- Runtime text mode and punctuation mode belong to `InputModeStateMachine` and
  are not persisted across host restarts.
- Host carrier compatibility and bundle matching stay in
  `KnowTypeInputMethod`.
- This model does not decide punctuation output or inspect document text.

## Behavior Notes

- `input.global.symbolWidth` is the active preference key.
- First read migrates by precedence: the new key, then legacy
  `input.default.symbolWidth`, then half-width.
- `defaultState`, `codeAppState`, and their old UserDefaults keys remain
  readable for source and data compatibility, but the production input runtime
  ignores their text and punctuation values.
- Saving writes only the global width key and does not delete or rewrite legacy
  user data.
- Changing the global width updates both legacy state shapes in memory so older
  callers continue to observe a coherent width.

## Tests

- `InputModePreferencesTests`
- `InputModePreferencesViewModelTests`
- `InputModeStateMachineTests`
