# SuggestionPublicationGuard

## Responsibility

`SuggestionPublicationGuard` prevents stale async suggestion results from
overwriting newer composition state.

## Boundaries

- It guards publication timing; it does not generate suggestions.
- Provider request construction stays outside the input-method UI layer.

## Behavior Notes

- Async provider-backed continuations can return after the user has typed more
  input, committed, or changed composition.
- Publication checks must preserve the visible local prefix snapshot and avoid
  showing stale continuation rows.

## Tests

- `SuggestionPublicationGuardTests`
- `InputControllerCoordinatorTests`
