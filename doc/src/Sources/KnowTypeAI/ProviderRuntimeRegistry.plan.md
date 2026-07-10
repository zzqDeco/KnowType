# ProviderRuntimeRegistry

## Responsibility

- Own the process-level provider revision, generation, opaque fingerprint, and
  provider lease used by recommendation and context-memory runtimes.
- Cancel generation-bound operations and reject cancellation-resistant results
  after provider configuration changes.

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
  fallback; ineligible recommendation and protected-only digest paths do not.
- A generation change cancels active operations and clears structured-output
  capability state. Per-generation recommendation runtimes supply fresh cache
  and health state.
- `perform(using:)` checks generation before and after an operation, so a
  transport that ignores cancellation still produces only a stale drop.
- Diagnostics contain revision, generation, configured state, and only the
  first 12 hexadecimal characters of the SHA-256 fingerprint.

## Tests

- `ProviderRuntimeRegistryTests`
- `AIContextMemoryRuntimeTests`
- `InputAIRecommendationRuntimeTests`
