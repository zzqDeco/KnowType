# ProviderRuntimeRegistry

## Responsibility

- Own the process-level provider revision, generation, opaque fingerprint, and
  provider lease used by recommendation and context-memory runtimes.
- Share the process-level `ProviderRequestGate` with recommendation and digest;
  reject stale generations while allowing already-started transport to finish
  under the gate's max-one-in-flight lease.

## Boundaries

- Profile persistence and the cross-process revision signal belong to
  `KnowTypeProviders`.
- Recommendation prompts, response sanitization, and context snapshot policy
  stay in their existing AI runtimes.
- The registry must never run from the ordinary key hot path or expose endpoint,
  model, header, profile name, or secret values in diagnostics.

## Behavior Notes

- The distributed revision signal invalidates active leases immediately.
- Every eligible AI dispatch checks the file revision as a missed-signal
  fallback. Operation completion and guarded persistence check it again before
  accepting provider work; ineligible recommendation and protected-only pending
  digest paths do not.
- A generation change invalidates the old gate generation, clears structured-
  output capability state, and fences late results. It does not reset the
  digest's last successful commit time. Per-generation recommendation runtimes
  supply fresh cache and health state. The registry creates one actor-owned
  transition with an explicit target generation before awaiting gate
  invalidation. It keeps the latest accepted/pending revision monotonic and
  publishes the target generation, a provider-less provisional lease, and that
  revision before clearing the transition or waking waiters. A runtime load can
  fill that provisional lease in the same generation. Repeated signals for one
  revision are ignored; higher revisions merge into a monotonic pending target
  while a transition is active and then form a later transition. Every await
  return rechecks the transition token and the generation, revision, and lease
  before accepting state, so stale disk reads cannot overwrite a newer signal. Started
  provider operations are not cancelled by a revision change; explicit caller
  cancellation and hard timeout may request cancellation, while the gate
  remains leased until resistant work actually ends. A caller timeout records
  the timeout cooldown immediately, and a late transport success does not erase
  that failure state. Only the task owning a real gate attempt records its
  timeout; a cancellation-marked late error releases the lease without
  recording a second provider failure.
- `perform(using:)` refreshes disk revision and checks generation before
  accepting either success or failure. `commitIfCurrent(using:)` repeats the
  refresh before persistence, so missed notifications still produce only a
  stale drop.
- Diagnostics contain revision, generation, configured state, and only the
  first 12 hexadecimal characters of the SHA-256 fingerprint.
- The shared gate persists cooldown state by default under `~/.knowtype` using
  bounded atomic mode-0600 storage. It contains only the privacy-safe identity
  hash, cooldown deadline, failure class, and a bounded failure count; it never
  stores in-flight state, endpoint, model, prompt, input, output, or credentials.
  Expired, successful, invalidated, and superseded-generation entries are
  removed; malformed state is safely ignored. Writes use stable ordering,
  bounded entry trimming, and a strict 64 KiB encoded limit. Cooldown waiters
  are actor-owned and invalidation wakes them immediately instead of sleeping an
  old deadline. Test-created gates are in-memory unless a temporary persistence
  URL is explicitly supplied. Failure counts clamp at 16 in memory and on disk,
  so additional failures keep the maximum cooldown recoverable instead of
  deleting the persisted entry.

## Tests

- `ProviderRuntimeRegistryTests`
- `AIContextMemoryRuntimeTests`
- `InputAIRecommendationRuntimeTests`
