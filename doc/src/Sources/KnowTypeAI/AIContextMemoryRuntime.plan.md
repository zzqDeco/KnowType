# AIContextMemoryRuntime

## Responsibility

- Record sanitized committed typing events and serialize process-wide context
  digest work.
- Claim a pending JSONL prefix, request one digest, update the generated section
  of `ENV.md`, and archive exactly the claimed events.

## Boundaries

- Provider generation and cancellation belong to `ProviderRuntimeRegistry`.
- Provider request mapping and response normalization stay in
  `KnowTypeProviders`.
- The runtime does not record marked text and does not send protected-only
  batches to a provider.

## Behavior Notes

- Production injects one actor into every `KnowTypeInputController`, so
  `digestInFlight`, success time, and failure time are process-wide.
- Provider revision fallback occurs only after batch/interval/protected gates
  make a digest eligible.
- Generation changes cancel old transport and reset provider-dependent interval
  state. Stale responses cannot write `ENV.md` or archive events.
- Final persistence holds both the provider-generation guard and the pending
  snapshot file claim. Events appended after the claimed prefix remain pending.
- Failed and empty digests retain the minimum retry interval. Protected-only
  batches archive locally without provider or provider-profile reads.

## Tests

- `AIContextMemoryRuntimeTests`
- `ProviderRuntimeRegistryTests`
