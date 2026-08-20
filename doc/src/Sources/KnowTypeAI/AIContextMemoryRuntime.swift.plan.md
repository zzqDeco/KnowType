# AIContextMemoryRuntime.swift

## Responsibility

- Own the single process-wide Context Digest state machine, provider lease
  fencing, bounded pending-prefix claims, and success-interval scheduling.

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
- Registry-backed claim creation, ENV replacement, archive, receipt, and
  schedule persistence start inside one synchronous current-lease guard. Work
  that is stale before the guard creates no claim.
- Persisted claims are recovered locally before the first post-restart append,
  so compaction cannot remove a claimed prefix. Unverifiable claims block the
  append and provider dispatch. A validated processed archive permits cleanup
  only when pending is missing, provably different, or exactly archived;
  truncated and unreadable pending evidence remains blocked.
- Initial claim recovery registers an actor-owned single-flight token before
  its first cross-actor await. Concurrent record and process callers wait for
  the same result; only the current owner mutates recovery, cleanup, gate latch,
  or retry state, and reset supersedes an older token.
- The first blocked recovery installs one bounded 60-second actor deadline.
  Records during that backoff return before recovery reads or append, and the
  deadline permits one retry before another bounded backoff. Successful or
  missing-claim recovery clears the latch.
- Gate persistence is preflighted before digest snapshot decoding and ENV load;
  a blocked result is latched without an immediate retry.
- Persisted schedule dates must have valid ordering and a bounded future
  deadline. Three absent time anchors are valid only when the persisted pending
  count is zero; a positive persisted pending count without an anchor is
  replaced with a fresh minimum-interval delay.
- A live digest claim remains an append/compaction protection until both the
  actor's digest flow and the matching gate attempt finish. Caller timeout or
  cancellation therefore cannot expose its exact prefix while a
  cancellation-resistant transport still owns the gate lease.
- Deadline conversion clamps finite positive durations before producing
  nanoseconds.

## Tests

- `AIContextMemoryRuntimeTests` covers guarded claim creation, timeout claim
  protection through compaction, anchorless schedule repair, busy-waiter
  coalescing, processed-archive recovery states, semantic schedule repair,
  bounded blocked-recovery retries, gate preflight latching, first-record claim
  recovery single-flight interleavings, and cancellation-resistant timeout
  flow.
