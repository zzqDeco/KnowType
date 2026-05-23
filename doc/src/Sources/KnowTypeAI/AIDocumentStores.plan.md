# AIDocumentStores

## Responsibility

Maintains the local AI context documents under `~/.knowtype`.

## Boundaries

- `EnvironmentDocumentStore` owns `ENV.md` creation, loading, duplicate generated-marker repair, and generated-section replacement.
- Loading repairs duplicate generated markers in memory and attempts to persist the repaired file, but write-back is best-effort so read-only or transient filesystem errors do not disable AI recommendations.
- Generated-section replacement remains a required write operation and should surface errors to callers.
- `CorrectionInstructionStore` owns `CORRECTION.md` creation and loading.

## Tests

- `AIRecommendationRuntimeTests`
