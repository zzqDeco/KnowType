# ProviderRequestGate.swift

## Responsibility

- Own one in-flight provider attempt per privacy-safe identity hash, generation
  fencing, failure classification, cooldown persistence, and availability
  wakeups.

## Boundaries

- It never persists provider identity, configuration, credentials, input, or
  output, and it does not release a lease at caller-visible timeout.

## Behavior Notes

- Every admitted dispatch receives a non-reusable attempt id. Timeout failure is
  atomically recorded for that id before timeout is visible to the caller.
- Late success, cancellation, or error can release only its own attempt. A
  timeout-marked late result preserves the existing cooldown and cannot count a
  second failure or mutate a newer attempt.
- Generation invalidation wakes waiters while stale transport remains fenced
  until its actual completion.
- With persistence enabled, permission, bounded-read, decode, encoding,
  atomic-write, replacement, or final-permission failure enters an actor-owned
  blocked state. New attempts remain blocked across generation invalidation;
  non-persistent gate instances are unaffected.

## Tests

- `ProviderRuntimeRegistryTests` covers timeout/completion interleaving,
  single-failure ownership, generation invalidation, fail-closed persistence,
  and waiter release.
