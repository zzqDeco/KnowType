# Accepted Learning Store Capacity Cap

## Delivered Behavior

- Added a sliding-window capacity cap to `AIAcceptedLearningStore`
  (`defaultMaxRecordCount = 500`, configurable via `maxRecordCount` on `init`
  and `inMemory`, clamped to at least `1`) so in-memory records and
  `rebuildSummary()` remain bounded instead of growing `O(N)` over full history.
- Updated `AIAcceptedLearningStore.init` (and external-clear reload) to retain
  only the most recent `maxRecordCount` records and compact
  `accepted-ai-learning.jsonl` on disk when historical records exceed capacity,
  while keeping within-capacity and missing-history cold starts read-only.
- Updated `AIAcceptedLearningStore.append(_:)` to fast-path append when within
  `maxRecordCount` and atomically rewrite the compacted JSONL history when
  appending exceeds `maxRecordCount`.
- Documented the current-state contract in
  `doc/src/Sources/KnowTypeAI/AIAcceptedLearning.swift.plan.md`.

## Verification

- `swift test --filter AIAcceptedLearningTests`
- Verified in `Tests/KnowTypeAITests/AIAcceptedLearningTests.swift` that:
  - Appending beyond `maxRecordCount` retains only the latest `maxRecordCount`
    records in memory and on disk after reload.
  - Initializing from an oversized JSONL file trims to the latest
    `maxRecordCount` records and compacts the file on disk.
  - `rebuildSummary()` reflects only the retained sliding window of records and
    evicts stale terms, commits, and schema summaries.

## Docs Absorbed By

- `doc/src/Sources/KnowTypeAI/AIAcceptedLearning.swift.plan.md`

## Retirement Criteria

- Retire this record once the bounded `AIAcceptedLearningStore` sliding-window
  retention is indexed in `doc/src/README.md` and `plan/README.md` and has
  remained stable across subsequent AI memory maintenance work.
