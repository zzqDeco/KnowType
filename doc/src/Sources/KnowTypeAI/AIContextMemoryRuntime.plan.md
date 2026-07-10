# AIContextMemoryRuntime

## Responsibility

- Record sanitized committed typing events only while a usable provider lease is
  available, and serialize process-wide context digest work.
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
- Registry-backed recording obtains a usable provider lease before appending an
  event and reuses that lease for an immediately eligible digest. Existing
  pending snapshots check the disk revision only after batch, interval, and
  protected-only gates make a digest eligible.
- Generation changes cancel old transport and reset provider-dependent interval
  state before failure cooldown is applied. Stale responses cannot write
  `ENV.md` or archive events.
- Final persistence holds both the provider-generation guard and the pending
  snapshot file claim. Events appended after the claimed prefix remain pending.
- Failed and empty digests retain the minimum retry interval while still
  checking for a changed provider revision. Protected-only pending batches
  archive locally without provider or provider-profile reads.

## Tests

- `AIContextMemoryRuntimeTests`
- `ProviderRuntimeRegistryTests`
