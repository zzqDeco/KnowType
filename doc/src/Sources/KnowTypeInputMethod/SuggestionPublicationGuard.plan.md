# SuggestionPublicationGuard

## Responsibility

`SuggestionPublicationGuard` provides small raw-input freshness checks for
suggestion publication and commit reads.

## Boundaries

- It guards publication timing and current-suggestion checks; it does not
  generate suggestions or store suggestion state.
- Provider request construction stays outside the input-method UI layer.
- `InputSuggestionStateRuntime` owns the actual suggestion snapshot and calls
  this guard when it needs to answer whether a stored suggestion still belongs
  to the current raw input.

## Behavior Notes

- Suggestion snapshots can become stale after the user has typed more input,
  committed, or changed composition.
- Publication checks must preserve the visible local prefix snapshot and avoid
  showing stale continuation rows.

## Tests

- `SuggestionPublicationGuardTests`
- `InputControllerCoordinatorTests`
