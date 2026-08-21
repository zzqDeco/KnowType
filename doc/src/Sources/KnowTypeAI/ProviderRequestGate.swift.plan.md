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
  blocked state. New attempts remain blocked across generation invalidation;
  non-persistent gate instances are unaffected.
- An internal value-only preflight reports available, busy, cooldown,
  stale-generation, or persistence-blocked without acquiring an attempt. It
  lets callers stop before document projection or digest snapshot decoding.

## Tests

- `ProviderRuntimeRegistryTests` covers admission-to-transport cancellation,
  pre-transport timeout and generation-invalidation rejection,
  timeout/completion interleaving, single-failure ownership, started-transport
  generation fencing, fail-closed persistence, value-only preflight, and
  waiter release.
