# Accepted Learning Store Capacity Cap

## Delivered Behavior

- Added a sliding-window capacity cap to `AIAcceptedLearningStore`
  (`defaultMaxRecordCount = 500`, configurable via `maxRecordCount` on `init`
  and `inMemory`, clamped to at least `1`) so in-memory records and
  `rebuildSummary()` remain bounded instead of growing `O(N)` over full history.
- Updated `AIAcceptedLearningStore.init` (and external-clear reload) to retain
  only the most recent `maxRecordCount` records, compact
  `accepted-ai-learning.jsonl` on disk under the interprocess file lock when
  historical records exceed capacity, refresh an existing markdown mirror when
  `maxRecordCount` changes, retry deferred startup compaction/mirror repair on
  subsequent reads if startup persistence fails transiently, and keep
  missing-history or already-consistent within-capacity cold starts read-only.
- Updated `AIAcceptedLearningStore.append(_:)` and `rebuildSummary()` to reload
  locked on-disk history before compacting or rebuilding summaries, fast-path
  append when within `maxRecordCount`, synchronize live peer stores and detect
  on-disk history signature changes so `snapshot(schemaID:)` and observers are
  invalidated immediately when a schema is evicted by another store's
  compaction, and persist SHA-256 digests of evicted commit text variants
  (`accepted-ai-learning.evicted-commits.json`, bounded to 4,096 digests during
  normal compaction and temporarily retaining active-record digests alongside
  them if a clear retry is pending) so
  `AIAcceptedLearningMaintenance.clear(confirm:)` can still scrub evicted
  accepted commits from `LEXICAL_PROFILE.md` without retaining raw evicted
  commit text on disk.
- Updated `AIAcceptedLearningStore.renderMarkdown(_:maxRecordCount:)` and
  `AIAcceptedLearningMaintenance` (`status`, `rebuild`, `clear`, and
  `maxRecordCount` mutation clamping) plus `README.md` / `README_CN.md` to
  report and enforce the configured sliding-window capacity and evicted-commit
  digest ledger.
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

## Integrity Follow-Up

Status: Active. Candidate implementation and regression tests are prepared;
functional verification is CI-only and has not been run locally for this
follow-up. Shared README, interface, architecture, and index updates belong to
the coordinator's later serial integration step.

- Failed clear pins its complete scrub input in the existing clear marker's
  optional `pendingEvictedCommitEntries` array before deleting history. A later
  clear reloads these entries even after more accepts rotate the ordinary
  eviction ledger back to 4,096 entries. Successful lexical JSON/markdown scrub
  and ledger cleanup precede removal of the pending marker field. Existing
  schema-version-1 markers without the field remain readable.
- Append's failure exit delivers already-applied peer invalidations once,
  outside both locks, including nonempty surviving schemas. Metadata-current
  snapshots do not need to repeat those events. No provider or runtime
  production behavior is changed.
- Runtime refuses a partial JSONL decode, preventing append, delayed rebuild,
  and startup cap from silently dropping nonblank undecodable rows.
  Maintenance rebuild reports `undecodableHistoryRows` before rewriting data;
  status remains diagnostic and explicitly confirmed clear remains destructive.
  Restoring fully decodable history permits normal bounded compaction again.

Added CI regression coverage:

- Failed lexical-profile write, 501 further long accepts and ledger rotation,
  clear retry, and lexical-profile/learning-store reload without old commits.
- Peer-compacted within-capacity history followed by both noncompacting and
  compacting local encode failures, with reentrant observer reads, no duplicate
  invalidations, and surviving-schema lexical-profile refresh.
- Append, startup cap, and maintenance rebuild preserve original history bytes
  for malformed rows and a complete future-shaped row whose `acceptedText`
  type cannot decode (not merely an unknown extra key). Explicit repair recovers
  ordinary cap behavior; confirmed clear's destructive exception is covered.

Recommended CI selectors (do not substitute for the workflow's full suite):

- `swift test --filter AIAcceptedLearningTests`
- `swift test --filter AIAcceptedLearningStoreTests`
- `swift test --filter LexicalProfileRuntimeTests`

The existing `.github/workflows/ci.yml` runs unfiltered `swift test`, both
install/profile smoke variants, and the input hot-path performance smoke. No
workflow changes or local functional runs are part of this candidate.

## Docs Absorbed By

- `README.md`
- `README_CN.md`
- `doc/interfaces.plan.md`
- `doc/src/Sources/KnowTypeAI/AIAcceptedLearning.plan.md`

## Retirement Criteria

- Retire this record once the bounded `AIAcceptedLearningStore` sliding-window
  retention is indexed in `doc/src/README.md` and `plan/README.md` and has
  remained stable across subsequent AI memory maintenance work.
