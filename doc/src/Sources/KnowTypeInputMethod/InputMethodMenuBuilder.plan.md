# InputMethodMenuBuilder

`InputMethodMenuBuilder` defines the testable structure of KnowType's
InputMethodKit menu.

## Responsibility

- Build the native input-method menu descriptors used by
  `KnowTypeInputController.menu()`.
- Keep ordinary menu shortcuts empty so input-method commands do not steal
  typing keys.
- Persist the localized AI continuation toggle through
  `InputMethodRuntimePreferenceStore`.

## Behavior Notes

- Menu order follows mature IMK input methods: common toggle, current mode
  status, data/diagnostic folder entries, then the localized KnowType settings
  item and About.
- The mode-status item is read-only and reports text mode, punctuation style,
  and character width at menu-open time.
- Menu titles resolve through `SettingsLocalization`, so the default visible
  menu copy is Simplified Chinese while explicit English resources remain
  available.
- The settings item is bound to `showPreferences:` and remains the primary
  settings entry point.

## Tests

- `InputMethodMenuBuilderTests`
