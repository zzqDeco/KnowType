# InputSuggestionStateRuntime

## Responsibility

`InputSuggestionStateRuntime` owns the current `SuggestionResponse` snapshot and
the raw input that produced it.

## Boundaries

- It stores, clears, invalidates, and reads suggestion state.
- It builds commit snapshots for the existing commit policy shape without
  creating pending fallback continuations.
- It clears resolved-composition no-provider fallback continuations once a real
  provider state is known.
- It does not call Rime, host clients, candidate-panel presenters, AI providers,
  composition buffers, or runtime preferences.

## Behavior Notes

- The runtime treats raw input as state adjacent to the suggestion, because
  `SuggestionResponse` intentionally does not carry its own raw-input identity.
- `commitSnapshot` keeps `usesPendingFallback` as `false`; the retired async
  local-candidate fallback path is not re-enabled.
- No-provider fallback cleanup is intentionally narrow: only a locked prefix
  whose candidate id is `composition-buffer` and whose continuation list is
  non-empty is rewritten.

## Tests

- `InputSuggestionStateRuntimeTests`
- `InputControllerCoordinatorTests`
- `InputHotPathPerformanceTests`
