# Context Digest Cumulative Request Budget

Status: Active

## Summary

- Bound cumulative Context Digest provider work after the existing per-request
  event and byte limits proved insufficient under a persistent backlog.
- Preserve long provider recovery instructions so a 429 cannot turn an
  hours-long service cooldown into repeated 15-minute attempts.

## Scope

- Parse a standard `Retry-After` header first and fall back to a bounded,
  structured JSON 429 body containing a finite numeric `reset_seconds`,
  `reset_time`, `retry_after`, or `retry_after_seconds` value.
- Extend the shared provider gate's rate-limit handling without changing auth,
  transport, timeout, 5xx, invalid-output, or local-commit backoff.
- Persist successful Context Digest timestamps in the existing schedule file
  and enforce one success per 6 hours, four successes per rolling 24 hours,
  and a 24-hour maximum age for below-batch pending data.
- Keep the existing 50-event/48-KiB digest claim and pending/archive bounds.
- Do not change prompts, realtime continuation triggers, provider adapters,
  settings, Rime, candidate behavior, installation, release, or user data.

## Implementation

- Normalize valid 429 recovery hints to 15 seconds through 7 days. The header
  wins over the body; malformed, oversized, string-valued, boolean, negative,
  current/past absolute reset times, or non-finite body values do not produce a
  hint. Raw 429 bodies are not propagated into diagnostics or generic provider
  errors.
- Use a dedicated no-hint 429 sequence of 15 minutes, 30 minutes, 1 hour,
  2 hours, 4 hours, 8 hours, 16 hours, and 24 hours, capped at 24 hours.
  Its optional persisted counter survives cooldown expiry and restart; old gate
  JSON without the counter starts from the first tier. Transport, auth, timeout,
  hinted 429, and other failure classes reset this dedicated sequence without
  changing their existing backoff calculation.
  Availability waiters sleep to the real deadline and still wake on
  cancellation or generation invalidation. Persisted and in-memory cooldowns
  are clamped to 7 days before waiter conversion, whose nanosecond conversion
  is explicitly saturating.
- Store a bounded list of successful digest timestamps in
  `ENV.digest-schedule.json`. Missing lists decode as empty for old schedule
  files; a legacy `lastSuccessfulDigestAt` remains a minimum-interval anchor.
  Loading sorts and exactly deduplicates the finite storage-bounded list without
  applying a startup-relative rolling cutoff. Eligibility and deferral normalize
  a temporary current-window copy, so ordinary forward-clock work ignores stale
  anchors while ordinary schedule writes preserve them for a supported
  completion-time rollback. Live success or claim recovery replaces actor state
  with completion-relative history bounded to `maximumDigestsPerWindow`.
  A bounded system-clock rollback retains future-relative success anchors until
  their original rolling-window expiry, in process and after restart; dates
  beyond the existing schedule bound are still treated as corrupt.
  Only a committed or locally recovered successful digest consumes this
  budget. Registry-backed live success samples wall time inside the final
  `commitIfCurrent` operation after generation/revision waits; direct-provider
  success invokes the same persistence closure. A bounded rollback advances the
  latest prior anchor by its smallest representable `Date` successor, while
  keeping the result at or below the existing completion-relative future bound.
  History normalization merges the retained list with the prior last-success
  anchor only while it is inside the completion-relative rolling window and
  future bound. When that prior anchor is within the schedule's `<1 ms` semantic
  tolerance of the retained history's latest entry, the retained entry already
  represents it; other anchors, including the current success, retain exact
  identity. History is then sorted and exactly deduplicated. Live success and
  completed-claim recovery include the current anchor and keep the newest bounded
  `maximumDigestsPerWindow` slots. Receipt, rolling history, last success,
  recovery pending-tail bound/fallback, and both persisted and in-memory
  eligibility use that same value, so request latency does not shorten either
  the 6-hour interval or rolling window. If the prior anchor is
  already at the upper bound, the closure fails before claim, ENV, archive,
  receipt, or schedule-success mutation. Pending data and existing budget slots
  remain intact for the local commit-failure cooldown and missing-claim recovery
  path. The receipt records the exact success timestamp before archive creation
  or pending-prefix removal; a receipt-write failure leaves the claimed prefix
  pending and unarchived. Recovery never treats a receipt as archive proof: it
  validates claim/ENV and processed/pending facts, ensures the receipt before
  any pending-prefix archive, and reuses its timestamp for archive/schedule
  recovery. A missing receipt uses bounded recovery time, including a legacy
  valid archive without a receipt.
  Receipt timestamps use the same bounded
  future-anchor rule as the schedule during a clock rollback. A legacy receipt
  has no claim-linked timestamp, so schedule time and pending count cannot prove
  that they describe the same success. Recovery therefore charges the bounded
  recovery time and upgrades the receipt. Existing schedule history is retained;
  if it already represented the same success, the one conservative extra slot
  expires with the rolling window. Later claim-cleanup retries reuse the upgraded
  timestamp and cannot add further slots. Provider and transport failures remain
  owned by the shared gate.
- Load and validate the persisted digest schedule before record-first claim
  recovery. A blocked schedule prevents both recovery and append, so local
  recovery always extends the durable rolling history instead of replacing it
  from an empty actor state. Recovery normalization also merges the actor's
  last-success anchor under the same semantic canonicalization, window/bound
  filter, exact deduplication, and newest-slot runtime bound.
- Treat a successfully written conservative schedule repair as a deadline gate,
  including after restart. Before that deadline both record and process return
  without claim or pending reads, append, provider work, or schedule overwrite;
  the existing deadline task wakes the runtime, clears the expired marker, and
  permits normal claim recovery. A failed repair write remains fail-closed.
- After recovery normalizes bounded clock-rollback history, its latest timestamp
  is the single success anchor for in-memory cadence and persisted
  `lastSuccessfulDigestAt`. A future-relative success therefore keeps its
  original minimum-interval deadline and remains semantically valid after the
  next restart.
- Evaluate pending count/age and successful cadence before decoding a JSONL
  digest snapshot. The existing inventory tracks the oldest retained decoded
  event timestamp, so a post-claim tail does not inherit the archived prefix's
  age. A successful prefix with a pending tail schedules no earlier than the
  next 6-hour window instead of a 10-minute catch-up.
- Keep diagnostics content-free: generation, event/byte counts, successful
  budget count, normalized deferral reason, and cooldown seconds only.
- Context Digest uses a generation-aware gate waiter only for provider
  cooldown or in-flight ownership. Ordinary 6-hour and rolling-budget
  eligibility continue to use the runtime's cadence deadline.
- Persisted-claim recovery preflights gate persistence before reading claim
  metadata. A blocked gate schedules the existing retry without claim metadata,
  digest-snapshot JSONL, or ENV reads and resumes normal local recovery after
  persistence is repaired.
  Its registry-backed append-only fallback first obtains a usable provider
  lease and applies the current generation. A missing or disabled provider
  returns before JSONL creation or append; an available provider retains the
  existing prefix-protected bounded append without starting a network request
  or cancelling the gate-persistence retry scheduled by the blocked preflight.
  Recovery is revalidated after the lease await: a newly installed claim
  backoff drops the event without applying the lease, completed recovery reuses
  the lease through normal append and scheduling, and only a still-current
  blocked episode uses fallback append. No stale retry deadline is restored.
  Direct-provider fallback behavior is unchanged.

## Test Plan

- Provider tests cover header/body precedence, an 85-hour body hint,
  current/past absolute reset times, malformed and oversized bodies, and the
  7-day clamp.
- Gate tests cover an 85-hour persisted hint, restart recovery, the complete
  no-hint 429 sequence across cooldown expiry and restart, reset after an
  intervening failure or valid hint, old persistence JSON, unchanged non-429
  backoff, and bounded recovery from a distant-future persisted deadline without
  unsafe sleep conversion.
- Context tests cover receipt-write failure before archive, persisted-receipt
  archive failure across restart, completion-time
  receipt/history/last-success/tail/deadline anchoring with a suspended provider
  and guarded-commit wait, the 6-hour interval, sampling after registry revision
  refresh, four-per-24-hour rolling budget, restoration of dispatch- or
  startup-window-pruned anchors after in-flight rollback, including four
  completion-window anchors and recovery, runtime-budget
  trimming after rollback restoration and schedule-write recovery without
  double-counting a semantically equivalent prior anchor,
  saturated-anchor failure before claim or success-state mutation, 24-hour
  maximum pending age,
  old-schedule decoding,
  restart persistence,
  no tail catch-up, immediate scheduling to a fresh long 429 deadline, no
  snapshot decode during that cooldown, generation-change wake without new
  input, exact one-slot claim recovery across schedule/receipt/cleanup
  failures, bounded-future receipt recovery after clock rollback with below-batch
  pending age anchored to the recovered success, conservative
  legacy receipt charging with a stale same-count schedule, one-time charging
  when the schedule already contains the success, legacy recovery without a
  schedule, record-first recovery preserving existing rolling history before
  append, bounded-future legacy recovery remaining valid across another restart,
  conservative repair gating on record and process paths across restart, zero
  claim and snapshot reads before the repair deadline, post-deadline legacy
  recovery, zero claim reads while gate persistence is blocked, resumed claim
  recovery after repair, missing and disabled registry providers retaining no
  fallback event, usable registry fallback append without provider transport,
  automatic persisted-claim recovery after that fallback without new input,
  lease-wait claim backoff remaining fail-closed, recovered-during-lease events
  receiving normal processing or a deadline without another input,
  and realtime recommendation independence from the digest success budget.
- GitHub Actions must run the focused suites, full `swift test`, and
  `./scripts/perf-input-hotpath.sh`. This writer runs only `git diff --check`
  locally.

## Assumptions

- The rolling window is based on the bounded monotonic timestamp sampled inside
  the final persistence operation after provider completion and registry waits;
  failed provider or local commit attempts do not consume a success slot.
- Existing pending JSONL is retained and continues to use the current
  500-event/1-MiB hard limit and 450-event/768-KiB compaction target.
- Realtime recommendation and Context Digest share provider health and
  in-flight ownership, but only Context Digest reads the digest success budget.
