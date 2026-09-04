# AIContextMemoryRuntime.swift

## Responsibility

- Own the single process-wide Context Digest state machine, provider lease
  fencing, bounded pending-prefix claims, and persistent cumulative success
  scheduling.

## Boundaries

- It does not own provider protocol encoding, input-method UI, or cross-process
  digest locking.
- `TypingEventStore` owns JSONL bounds and archive evidence;
  `EnvironmentDocumentStore` owns ENV and recovery metadata files.

## Behavior Notes

- Calls arriving during an active digest set one coalesced rerun. The rerun is
  scheduled only after the active digest clears and uses the then-current
  provider lease. If a busy-gate availability waiter is already installed, it
  remains the single wake source and the coalesced signal does not replace it.
- Registry-backed claim creation, ENV replacement, final-anchor receipt,
  archive, and schedule persistence start in that order inside one synchronous
  current-lease guard. Work that is stale before the guard creates no claim.
- Persisted claims are recovered locally before the first post-restart append,
  so compaction cannot remove a claimed prefix. Unverifiable claims block the
  append and provider dispatch. A validated processed archive permits cleanup
  only when pending is missing, provably different, or exactly archived;
  truncated and unreadable pending evidence remains blocked.
- The record-first path loads and semantically validates the persisted schedule
  before entering claim recovery. A blocked schedule prevents recovery and
  append, ensuring recovery adds its success to the durable rolling history
  rather than overwriting that history from an empty actor state.
- A successfully persisted conservative schedule repair is also an active work
  gate until its deadline. Record and process paths arrange the deadline wake
  and return before claim reads, pending snapshots, append, or provider work.
  Loading that repaired schedule after restart restores the same gate. At the
  deadline the marker clears and normal bounded claim recovery resumes; failure
  to persist the repair remains permanently fail-closed for that runtime.
- Initial claim recovery registers an actor-owned single-flight token before
  its first cross-actor await. Concurrent record and process callers wait for
  the same result; only the current owner mutates recovery, cleanup, or gate
  retry state, and reset supersedes an older token.
- The first blocked recovery installs one bounded 60-second actor deadline.
  Records during that backoff return before recovery reads or append, and the
  deadline permits one retry before another bounded backoff. Successful or
  missing-claim recovery clears the latch.
- Gate persistence is preflighted before persisted-claim metadata, digest
  snapshot, or ENV reads; a blocked result installs one deadline at the shared
  gate's retry time. Its registry-backed append-only fallback obtains a usable
  provider lease and applies its generation before `appendBounded`; a missing
  or disabled provider returns before JSONL creation or append. An available
  provider permits only the existing prefix-protected bounded append and starts
  no network request. That fallback-specific generation application preserves
  the gate retry deadline installed by the blocked preflight, so recovery still
  runs without another record or manual process call. Direct-provider fallback
  behavior is unchanged. Claim, digest snapshot, and ENV reads remain blocked.
  After the registry await, record rechecks a newly installed claim-recovery
  backoff before applying the lease, then reruns persisted-claim preparation. A
  still-blocked episode preserves only its current gate retry and appends; a
  recovered episode reuses the loaded lease in the normal append-and-process
  path so the new backlog receives an eligibility deadline. An older retry is
  never reinstalled.
  Outside this fallback path, a new Provider generation can cancel the old
  deadline and immediately revalidate the shared gate.
- Digest eligibility is evaluated from the path-shared inventory and persisted
  schedule before JSONL snapshot decoding. Production requires 50 pending
  events or a 24-hour pending age, at least 6 hours since the last successful
  digest, and fewer than four successful digests in the preceding rolling
  24 hours. Each request still claims at most the oldest 50 events or 48 KiB.
- Only a committed digest success or locally recovered completed claim appends
  a successful timestamp. Failures and 429 attempts consume provider-gate
  backoff but do not consume the digest success budget. Registry-backed success
  samples `completionNow` inside the synchronous `commitIfCurrent` operation,
  after provider completion and all generation/revision waits; direct-provider
  success invokes the same persistence closure directly. The sample is used
  when it exceeds every prior success anchor. After a bounded clock rollback,
  the prior anchor's smallest `Date` successor is used instead. The anchor must
  not exceed `completionNow + maximumScheduleAnchorOffset`. Completion-relative
  success history merges the retained timestamps with the prior last-success
  anchor only while that anchor remains inside the budget window and future
  bound. A prior anchor within the schedule's `<1 ms` semantic tolerance of the
  retained history's latest timestamp is the same represented prior success and
  is not added again; every other anchor, including a current `nextUp` success,
  retains exact identity. History is then sorted and exactly deduplicated. After
  including the current anchor, live success and recovery keep the newest bounded
  `maximumDigestsPerWindow` timestamps. The final anchor drives successful
  history, archive receipt, persisted last success, recovery pending-tail
  timestamp bounding/fallback, persisted next eligibility, and in-memory success
  scheduling. Entry `now` remains the eligibility, deferral, and failure/cooldown time. A
  successful claim with a pending tail schedules the next 6-hour window and
  cannot immediately catch up the backlog.
- If the latest prior anchor already equals that completion-relative upper
  bound, no distinct successor can be represented under the existing schema.
  The persistence closure fails before saving a claim or mutating ENV, archive,
  receipt, or schedule success state. The pending prefix and prior budget slots
  remain intact, and the failure uses the existing local commit-failure cooldown
  and missing-claim recovery path.
- Before archive creation or claimed-prefix removal, a successful digest writes
  a receipt containing its exact success timestamp. Receipt failure leaves the
  prefix pending and no processed archive. Recovery treats a receipt only as a
  timestamp: it first validates claim/ENV and processed/pending facts, then
  validates or creates the receipt before any pending-prefix archive and reuses
  that timestamp for the schedule. A missing receipt uses bounded recovery time,
  including a legacy valid archive without a receipt. Schedule-write, archive,
  receipt-cleanup, and claim-cleanup failures therefore reuse one timestamp instead of
  consuming another rolling-budget slot on each restart. Receipt timestamps use
  the schedule's bounded future-anchor semantics when the clock moves backward;
  non-finite or farther-future values block recovery. A legacy receipt lacks a
  claim-linked success timestamp, and matching schedule/tail counts cannot
  distinguish the current commit from a stale prior schedule. Recovery therefore
  records bounded recovery time and upgrades the receipt while retaining any
  existing history. This can conservatively occupy one extra rolling-window slot
  when the schedule already recorded the same success, but repeated cleanup
  recovery reuses the upgraded timestamp and cannot add another slot.
- Schedule loading accepts legacy JSON without the successful timestamp list,
  using `lastSuccessfulDigestAt` as its existing cadence anchor. Corrupt
  schedule repair retains its conservative deadline across runtime rebuilds.
  A finite storage-bounded timestamp list is sorted and exactly deduplicated but
  is not filtered against startup time. Each eligibility/deferral calculation
  instead normalizes a temporary current-window copy, while ordinary schedule
  writes preserve the loaded list. Live success or claim recovery replaces actor
  state with completion-relative history bounded to the runtime maximum.
  Live completion and recovery both merge that actor anchor under the same
  prior-anchor semantic canonicalization, rolling-window/future-bound filter,
  exact deduplication, and newest-slot runtime bound.
  A clock rollback within the existing schedule-anchor bound keeps original
  successful timestamps and therefore their original rolling-window expiry,
  both in process and after restart; farther future anchors remain invalid. The
  normalized history's latest timestamp is the single anchor used for
  `lastDigestAt`, the next cadence deadline, and persisted
  `lastSuccessfulDigestAt`, so a bounded future anchor remains semantically
  valid through recovery and another restart.
- Cadence deadline tasks sleep to the real eligibility deadline. Provider
  cooldown and busy states instead install the shared gate's
  generation-aware availability waiter while retaining the real deadline for
  diagnostics and tests. Multi-day 429 waits therefore wake immediately when
  the Provider generation changes, even without a new typing event; ordinary
  6-hour eligibility never becomes a gate waiter.
- Persisted schedule dates must have valid ordering and a bounded future
  deadline. Three absent time anchors are valid only when the persisted pending
  count is zero; a positive persisted pending count without an anchor is
  replaced with a conservative cadence deadline.
- A live digest claim remains an append/compaction protection until both the
  actor's digest flow and the matching gate attempt finish. Caller timeout or
  cancellation therefore cannot expose its exact prefix while a
  cancellation-resistant transport still owns the gate lease. A record,
  manual, or deadline wake that reaches the live-claim guard latches one
  pending re-evaluation. After both owners finish, one actor-owned full
  `processIfNeeded` pass runs when pending events remain, rechecking interval,
  cooldown, gate, and generation eligibility. No blocked wake means no
  post-completion rerun.
- Deadline conversion bounds only against `UInt64` nanosecond capacity; it does
  not impose a shorter periodic wake interval.

## Tests

- `AIContextMemoryRuntimeTests` covers guarded claim creation, timeout claim
  protection through compaction, anchorless schedule repair, busy-waiter
  coalescing, processed-archive recovery states, semantic schedule repair,
  bounded blocked-recovery retries, disk-free gate backoff and same-instance
  recovery, first-record claim recovery single-flight interleavings,
  cancellation-resistant timeout flow, and claim-blocked wake resumption after
  real transport completion. Cadence and recovery tests additionally cover
  receipt-write failure before archive, persisted-receipt archive failure across
  restart, completion-time receipt/history/deadline anchoring after a suspended
  provider and guarded commit wait, sampling after registry revision refresh,
  restoration of dispatch- or startup-window-pruned anchors after in-flight
  clock rollback, including four completion-window anchors and recovery,
  runtime-budget trimming after rollback
  restoration without double-counting a semantically equivalent prior anchor,
  saturated-anchor failure before success mutation, 6-hour and rolling-day
  limits, 24-hour pending age, restart persistence, tail deferral,
  direct scheduling to a fresh multi-day 429 deadline, long-cooldown no-decode
  behavior, generation-change wake without new input, exact one-slot recovery
  across schedule/receipt/cleanup failures, runtime-bound schedule-write
  recovery history, bounded-future receipt recovery with pending age anchored to
  the recovered success,
  conservative legacy recovery against stale same-count and already-recorded
  schedules, one-time charging across repeated cleanup failure, no-schedule
  legacy recovery, record-first history preservation before append,
  bounded-future legacy recovery across an additional restart, bounded clock
  rollback across restart, conservative schedule-repair gating for record and
  process paths across restart, zero claim and snapshot reads before the repair
  deadline, post-deadline legacy recovery, zero claim reads during
  gate-persistence blockage with post-repair recovery, registry-provider
  availability gating for fallback retention, append-only fallback without
  transport, and realtime recommendation independence.
