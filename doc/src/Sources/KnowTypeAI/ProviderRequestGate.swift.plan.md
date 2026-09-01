# ProviderRequestGate.swift

## Responsibility

- Own one in-flight provider attempt per privacy-safe identity hash, generation
  fencing, failure classification, cooldown persistence, and availability
  wakeups.

## Boundaries

- It never persists provider identity, configuration, credentials, input, or
  output, and it does not release a started-transport lease at caller-visible
  timeout.

## Behavior Notes

- Every admitted dispatch receives a non-reusable attempt id. Timeout failure is
  atomically recorded for that id before timeout is visible to the caller.
- The actor associates each active attempt id and generation with the exact
  phase fence and exactly-once completion callback used by its operation task.
  Generation invalidation atomically aborts an admitted attempt, clears only
  that id, wakes waiters, and runs completion without cooldown. A started or
  started-timeout-owned transport retains the active lease until its real
  stale-fenced completion. Registry invalidation supplies an explicit target
  generation; phase/state mutation and waiter wake are linearized before an
  aborted attempt's asynchronous completion callback runs.
- `beginTransport` succeeds only from the admitted phase. If timeout ownership
  wins first, the gate records cooldown, releases that matching attempt, wakes
  waiters, and runs attempt completion without starting the provider. If
  transport already started, timeout records once while the lease remains until
  the real operation completes.
- Caller cancellation after admission but before transport registration aborts
  only that attempt, wakes availability waiters, and creates no failure or
  cooldown. Once transport starts, its attempt remains owned until the real
  operation reaches its fenced completion path.
- Late success, cancellation, or error can release only its own attempt. A
  timeout-marked late result preserves the existing cooldown and cannot count a
  second failure or mutate a newer attempt.
- Generation invalidation wakes waiters while stale transport remains fenced
  until its actual completion.
- A missing persistence file is treated as an empty gate state on first load;
  Cocoa no-such-file errors, POSIX `ENOENT`, and nested underlying `ENOENT`
  are accepted, while other read, permission, corrupt, or write failures stay
  fail-closed.
- With persistence enabled, permission, bounded-read, decode, encoding,
  atomic-write, replacement, or final-permission failure enters an actor-owned
  blocked state. New attempts remain fail-closed while a 5-to-60-second retry
  deadline is active; preflight performs no persistence I/O during that window.
- Recovery reloads state after read/decode failures or rewrites the desired
  in-memory state after mutation failures. The first new Provider generation
  may force one probe, while stale invalidations cannot bypass the deadline.
  Neither path can erase an active cooldown or started transport. A started
  transport that finishes during backoff updates the desired in-memory rewrite
  without touching disk. In-memory clear tombstones prevent invalidated
  persisted cooldowns from being resurrected after a later recovery.
  Non-persistent gate instances are unaffected.
- An internal value-only preflight reports available, busy, cooldown,
  stale-generation, or persistence-blocked without acquiring an attempt. It
  lets callers stop before document projection or digest snapshot decoding.
- A valid 429 recovery hint is honored from 15 seconds through 7 days. Without
  a hint, only rate limiting uses the bounded sequence 15 minutes, 30 minutes,
  1 hour, 2 hours, 4 hours, 8 hours, 16 hours, and 24 hours, then remains capped
  at 24 hours. The no-hint sequence has an optional persisted counter that
  survives cooldown expiry and process restart; persistence written before the
  counter existed decodes as zero. Any valid hint or intervening auth,
  transport, timeout, 5xx, invalid-output, or local-commit failure resets that
  dedicated counter while retaining the existing behavior of its own backoff.
- Availability waiters sleep until the real cooldown deadline instead of
  waking every 15 minutes. Cancellation and generation invalidation still
  resume them immediately, and persisted deadlines retain the same behavior
  after process restart.
- Persisted and in-memory cooldown deadlines are bounded to the production
  7-day maximum before admission or waiter creation. An anomalous finite
  distant-future persisted deadline is rewritten to that bound; malformed or
  non-finite state remains fail-closed. Deadline-to-nanosecond conversion is
  explicit and saturating, so corrupt magnitudes cannot trap the process.
- Blocked, probing, and recovered transitions use privacy-safe unified logs with
  no provider endpoint, model, input, output, or credential content.

## Tests

- `ProviderRuntimeRegistryTests` covers admission-to-transport cancellation,
  pre-transport timeout and generation-invalidation rejection,
  timeout/completion interleaving, single-failure ownership, started-transport
  generation fencing, fail-closed persistence, disk-free recovery backoff,
  deadline and generation recovery, cooldown retention, stale-state
  non-resurrection, value-only preflight, 429 hint/fallback schedules, dedicated
  no-hint sequence persistence and reset, old-JSON compatibility,
  distant-future bounding, safe waiter conversion, and waiter release.
