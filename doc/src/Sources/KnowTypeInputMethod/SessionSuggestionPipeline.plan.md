# SessionSuggestionPipeline

## Responsibility

`SessionSuggestionPipeline` builds session-level `SuggestionResponse` values from
local correction, optional provider-backed continuation, and runtime input-method
preferences.

It is the testable suggestion boundary used by `InputSessionController` and
legacy/MVP acceptance tests. The production IMK hot path is Rime-first and must
not call this pipeline synchronously from `InputControllerCoordinator`.

## Boundaries

- Product correction, prefix locking, and privacy rules stay in `KnowTypeCore`.
- Provider protocol mapping and response normalization stay in
  `KnowTypeProviders`.
- IMK callback handling, host writes, and candidate panel state stay in
  `InputControllerCoordinator`.
- Rime composition and synchronous production conversion stay in
  `RimeConversionEngine`.

## Behavior Notes

- `suggestions(for:)` can ask a configured provider for continuation only after
  local correction produces a locked prefix and the runtime privacy gates allow
  cloud continuation.
- `prefixSuggestions(for:)` intentionally returns prefix candidates only.
- `localSuggestions(...)` is reserved for tests and stale-suggestion fallback
  paths outside the IMK hot path; hot-path tests and scripts reject references
  from `InputControllerCoordinator`.
- The old `InputMethodPipeline` name was removed instead of kept as a
  deprecated compatibility alias so new work does not treat it as a current
  production input path.

## Tests

- `MVPAcceptanceTests`
- `InputSessionControllerTests`
- `InputMethodLexiconRuntimeTests`
- `InputHotPathPerformanceTests`
