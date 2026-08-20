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
  provider lease.
- Persisted claims are recovered locally before the first post-restart append,
  so compaction cannot remove a claimed prefix. Unverifiable claims block the
  append and provider dispatch.
- Persisted schedule dates must have valid ordering and a bounded future
  deadline. Invalid state is replaced with a fresh minimum-interval delay.
- Deadline conversion clamps finite positive durations before producing
  nanoseconds.

## Tests

- `AIContextMemoryRuntimeTests` covers stale-generation reruns, semantic schedule
  repair, first-record claim recovery, and cancellation-resistant timeout flow.
