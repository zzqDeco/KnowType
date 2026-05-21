# InputMethodMenuBuilder

`InputMethodMenuBuilder` defines the testable structure of KnowType's
InputMethodKit menu.

## Responsibility

- Build the native input-method menu descriptors used by
  `KnowTypeInputController.menu()`.
- Keep ordinary menu shortcuts empty so input-method commands do not steal
  typing keys.
- Persist the `AI Continuation` toggle through
  `InputMethodRuntimePreferenceStore`.

## Behavior Notes

- Menu order follows mature IMK input methods: common toggle, data/diagnostic
  folder entries, then `KnowType Settings...` and About.
- `KnowType Settings...` is bound to `showPreferences:` and remains the primary
  settings entry point.

## Tests

- `InputMethodMenuBuilderTests`
