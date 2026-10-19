# Learning Integrity And URL Protection

Status: Active

Implementation base: `64aa62dde195b539d2e5540b7736aef9975f1ef3`.
Review remediation base: `b147966d8048507e5255b847d6560acc04418fad`.
The four fixes and regression tests are present for independent review;
CI-only functional validation is pending. This is not a delivery or merge record.

## Summary

- Preserve failed-clear recovery inputs across further accepted-learning
  compaction, and deliver external invalidations even when a local append fails.
- Keep nonblank undecodable history rows recoverable instead of silently
  dropping them during automatic or maintenance rewrites.
- Retain bare `.bar` URL protection without undoing lexical exclusions for
  dotted code tokens such as `foo.bar` and `user.bar`.
- Review these four bounded fixes together; do not expand into a history-store
  redesign, provider/runtime changes, or unrelated earlier review comments.

## Scope

- Implementation: `AIAcceptedLearningStore`,
  `AIAcceptedLearningMaintenance`, and `TextProtection`, with focused AI, core,
  and lexical-profile runtime regression tests. Core code/tests and its module
  notes remain frozen; review remediation is limited to accepted-learning
  persistence ordering and EOF append boundaries.
- Shared documentation: README / README_CN, architecture, interfaces, this
  plan, and its single entry in the plan index. Review follow-up updates only
  affected contracts, with no workflow, setup, or additional index changes.
- Non-goals: new sidecars, full-history retention, cloud/provider policy,
  input-method UI or production runtime edits, installation, release, or
  mixed-old-writer recovery guarantees.

## Implementation

### Failed Clear Recovery

- Keep the ordinary eviction ledger capped at 4,096 entries. Before changing
  the ledger or deleting history, atomically pin required scrub inputs in the
  existing schema-version-1 `accepted-ai-learning.clear.json` marker using
  optional `pendingEvictedCommitEntries: [String]`; no new sidecar is added.
- Retry unions prior pins, the current ledger, and active-record digests.
  Ordinary compaction can rotate the ledger but cannot discard the marker's
  pins. Successful lexical JSON/markdown scrub precedes ledger deletion and
  removal of the pending marker field; failures leave retry inputs available.
- If pin persistence fails, leave ledger/history and other learning files
  unchanged; an unwritable marker cannot create durable recovery state. After
  pin persistence succeeds, later failures must still synchronize peer stores
  with the actual disk records, not assume history was deleted.
- Old markers without the field remain readable. Old maintenance writers do
  not retain the new field when replacing the marker, so pending clears must
  use the current writer; this is not seamless mixed-version write support.

### External Invalidations

- Applied external schema changes remain observable even when subsequent local
  append/compaction fails. Notify outside both the store and file locks.
- Include nonempty surviving schemas as well as zero-count invalidations;
  reentrant snapshot reads and metadata-current reads must not duplicate events.
  The existing lexical-profile observer can then refresh its cached profile.

### Undecodable History

- Require every nonblank accepted-history row to decode before append, startup
  cap, or delayed rebuild. Leave original bytes intact on malformed or
  forward-incompatible complete rows; do not rewrite a decoded subset.
- Maintenance rebuild reports `undecodableHistoryRows` before data rewrites;
  read-only status reports `invalid_history_lines:<count>`. Repairing the data
  restores normal bounded compaction. Blank/whitespace-only rows are ignored.
- Accept complete final JSON without LF and insert a delimiter before the next
  fast append under the file lock. A truncated EOF row, including one without
  LF, remains byte-for-byte unchanged and blocks append instead.
- Explicit confirmed clear remains destructive and may delete undecodable
  rows; it does not claim to interpret unknown row contents.

### Bare `.bar` URLs

- Preserve `reason: "url"`, Level 0 local correction, and range metadata for
  `nic.bar`, `cocktail.bar`, subdomains, mixed case, ports, paths, and
  queries after a path, both standalone and in prose.
- Retain lexical code-prefix exclusions for unschemed, pathless, portless
  `foo.bar` / `user.bar`. Bare dotted calls followed by `(` after optional
  whitespace remain code-protected; explicit schemes, `www.`, paths, and
  ports retain URL precedence. No DNS lookup or host-specific exception.

## Test Plan

- Pending gate: independent review and the existing
  [CI workflow](../.github/workflows/ci.yml), including unfiltered `swift test`,
  build, both install/profile smoke variants, and hot-path performance smoke.
  Do not run tests, builds, performance checks, repro programs, or host-app
  automation locally for this slice. No pass is claimed here.
- CI regression cases: failed lexical write followed by 501 long accepts,
  ledger rotation, clear retry and reload; peer-compacted within-capacity
  history followed by failed append/compaction, reentrant callbacks and
  surviving-schema lexical-profile refresh; byte preservation and recovery for
  append/startup/maintenance using malformed and genuinely incompatible
  complete JSON rows; confirmed clear's destructive exception and legacy-marker
  reading; `.bar` URL ranges, local-protection metadata, and code exclusions.
- Review-remediation regressions: marker-write failure leaves ledger/history
  unchanged; ledger-write failure after a successful pin preserves retry state
  and synchronizes peers; append/reload accepts a complete EOF row without LF,
  while a genuinely truncated EOF row without LF keeps its original bytes.
- Focused CI diagnostic selectors, not a replacement for the full suite:
  `AIAcceptedLearningTests`, `AIAcceptedLearningStoreTests`,
  `LexicalProfileRuntimeTests`, and `KnowTypeCoreTests` via `swift test --filter`.
- Documentation-only local validation: `git diff --check` and static checks
  that relative README/index/plan links resolve to existing files.

## Assumptions

- Current source is authoritative for these contracts. Review remediation does
  not reopen frozen core behavior or pre-existing Markdown scrub-filter policy.
- `.bar` classification is a lexical heuristic, not domain ownership or intent
  detection: otherwise unrecognized `venue.bar` favors a domain, while known
  code prefixes and `nic.bar (details)` favor code-like interpretation.
- Undecodable history blocks learning writes until external repair or explicit
  destructive clear. Retry pins are recovery state, not unbounded ordinary
  eviction storage; old writers can discard that recovery state.
- Keep this plan Active until the coordinator has independent review and
  exact-head CI evidence; no merge, delivery, or release is asserted.
