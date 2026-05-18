# SuggestionRefreshPolicy

## Responsibility

`SuggestionRefreshPolicy` decides when the input method should refresh
suggestions in response to input, settings, lexicon, or async runtime changes.

## Boundaries

- It chooses refresh timing; correction and continuation behavior stay in core
  engines.
- File-system lexicon loading stays in `InputMethodLexiconRuntime`.

## Behavior Notes

- Runtime lexicon changes are picked up at safe boundaries and must not rewrite
  active marked text with stale candidates.
- Pending provider-backed suggestions should not block local marked-text
  publication.

## Tests

- `SuggestionRefreshPolicyTests`
- `InputControllerCoordinatorTests`
- `InputMethodLexiconRuntimeTests`
