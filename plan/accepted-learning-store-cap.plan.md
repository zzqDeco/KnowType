# Accepted Learning Store Capacity Cap

## Delivered Behavior

- Added a sliding-window capacity cap to `AIAcceptedLearningStore`
  (`defaultMaxRecordCount = 500`, configurable via `maxRecordCount` on `init`
  and `inMemory`, clamped to at least `1`) so in-memory records and
  `rebuildSummary()` remain bounded instead of growing `O(N)` over full history.
- Updated `AIAcceptedLearningStore.init` (and external-clear reload) to retain
  only the most recent `maxRecordCount` records and compact
  `accepted-ai-learning.jsonl` on disk under the interprocess file lock when
  historical records exceed capacity, while keeping within-capacity and
  missing-history cold starts read-only.
- Updated `AIAcceptedLearningStore.append(_:)` and `rebuildSummary()` to reload
  locked on-disk history before compacting or rebuilding summaries, fast-path
  append when within `maxRecordCount`, emit zero-count summary invalidation
  events for fully evicted schemas, and persist SHA-256 digests of evicted
  commit text variants (`accepted-ai-learning.evicted-commits.json`, bounded to
  4,096 digests) so `AIAcceptedLearningMaintenance.clear(confirm:)` can still
  scrub evicted accepted commits from `LEXICAL_PROFILE.md` without retaining raw
  evicted commit text on disk.
- Updated `AIAcceptedLearningMaintenance` (`status`, `rebuild`, `clear`, and
  `maxRecordCount` mutation clamping) and `README.md` / `README_CN.md` to
  enforce and document the 500-record window and evicted-commit digest ledger.
- Documented the current-state contract in
  `doc/interfaces.plan.md` and
  `doc/src/Sources/KnowTypeAI/AIAcceptedLearning.plan.md`.

## Verification

- `swift test --filter AIAcceptedLearningTests`
- Verified in `Tests/KnowTypeAITests/AIAcceptedLearningTests.swift` that:
  - Appending beyond `maxRecordCount` retains only the latest `maxRecordCount`
    records in memory and on disk after reload, including across two store
    instances sharing the same `historyURL`.
  - Initializing from an oversized JSONL file acquires the file lock, trims to
    the latest `maxRecordCount` records, and compacts the file on disk.
  - `rebuildSummary()` reflects only the retained sliding window of records,
    emits invalidation events for fully evicted schemas, and maintenance
    `rebuild` / `clear` honor the window and scrub evicted commits.

## Docs Absorbed By

- `README.md`
- `README_CN.md`
- `doc/interfaces.plan.md`
- `doc/src/Sources/KnowTypeAI/AIAcceptedLearning.plan.md`

## Retirement Criteria

- Retire this record once the bounded `AIAcceptedLearningStore` sliding-window
  retention is indexed in `doc/src/README.md` and `plan/README.md` and has
  remained stable across subsequent AI memory maintenance work.
