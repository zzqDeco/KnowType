# Session Suggestion Pipeline Refactor

## Summary

Rename the legacy-sounding `InputMethodPipeline` boundary to
`SessionSuggestionPipeline` and move it out of `InputMethodHost.swift`.

This is a small project-management refactor: the suggestion logic remains
available where it is still used, but the old name is removed outright instead
of preserved through a defensive type alias.

## Scope

- Add `Sources/KnowTypeInputMethod/SessionSuggestionPipeline.swift`.
- Keep `Sources/KnowTypeInputMethod/InputMethodHost.swift` focused on the IMK
  server bootstrap seam.
- Migrate production, tests, scripts, and docs from `InputMethodPipeline` to
  `SessionSuggestionPipeline`.
- Keep behavior unchanged for correction, continuation, stale-suggestion
  fallback, and test-facing local suggestions.

Non-goals:

- Do not split `InputControllerCoordinator` in this slice.
- Do not change Rime, AI provider behavior, candidate ranking, or host carrier
  compatibility.
- Do not keep a deprecated `InputMethodPipeline` alias.

## Implementation

- Move the existing suggestion-pipeline implementation into the new
  `SessionSuggestionPipeline` type.
- Update `InputSessionController` to construct `SessionSuggestionPipeline`.
- Update hot-path tests and `scripts/perf-input-hotpath.sh` to reject
  `SessionSuggestionPipeline.localSuggestions` in `InputControllerCoordinator`.
- Update source notes and plan indexes so the new boundary is discoverable.

## Test Plan

- `swift test --quiet --filter MVPAcceptanceTests`
- `swift test --quiet --filter InputSessionControllerTests`
- `swift test --quiet --filter InputMethodLexiconRuntimeTests`
- `swift test --quiet --filter InputHotPathPerformanceTests/testCoordinatorSourceKeepsRetiredLocalConversionOutOfHotPath`
- `swift test`
- `git diff --check`

## Assumptions

- `InputMethodPipeline` is not dead logic; it is still used by session-level
  tests and fallback paths, so the correct cleanup is direct rename and boundary
  clarification rather than deleting suggestion generation.
- Removing the old type name without an alias is acceptable because this package
  does not promise source compatibility for that internal boundary.
