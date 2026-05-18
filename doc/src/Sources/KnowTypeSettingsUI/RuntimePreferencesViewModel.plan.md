# RuntimePreferencesViewModel

## Responsibility

`RuntimePreferencesViewModel` edits input scheme, candidate layout, page size,
and continuation runtime preferences.

## Boundaries

- Preference definitions live in `KnowTypeCore`.
- Runtime application belongs to the input method at startup and new composition
  boundaries.

## Behavior Notes

- Defaults preserve production behavior: full pinyin, adaptive candidate layout,
  cloud continuation enabled, local fallback enabled, medium continuation
  length, and six continuation candidates.
- Adaptive layout can cap effective page size even when older settings store a
  larger value.

## Tests

- `RuntimePreferencesViewModelTests`
- `InputMethodRuntimePreferencesTests`
