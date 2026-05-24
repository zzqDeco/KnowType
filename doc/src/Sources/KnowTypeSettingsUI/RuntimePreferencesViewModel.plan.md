# RuntimePreferencesViewModel

## Responsibility

`RuntimePreferencesViewModel` edits candidate layout, page size, and continuation runtime preferences. It still preserves the legacy input-scheme field through the shared model for compatibility, but the Rime-only settings UI no longer exposes that control.

## Boundaries

- Preference definitions live in `KnowTypeCore`.
- Runtime application belongs to the input method at startup and new composition
  boundaries.

## Behavior Notes

- Defaults preserve production behavior: Rime full-pinyin schema, adaptive
  candidate layout, cloud continuation enabled, local fallback enabled, medium
  continuation length, and six continuation candidates.
- Adaptive layout can cap effective page size even when older settings store a
  larger value.

## Tests

- `RuntimePreferencesViewModelTests`
- `InputMethodRuntimePreferencesTests`
