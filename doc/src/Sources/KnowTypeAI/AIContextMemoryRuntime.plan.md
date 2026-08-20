# AIContextMemoryRuntime

## Responsibility

- Record sanitized committed typing events only while a usable provider lease is
  available, and serialize process-wide context digest work.
- Claim a pending JSONL prefix, request one digest, update the generated section
  of `ENV.md`, and archive exactly the claimed events.
- Keep append, retry, request, and archive costs bounded while a provider is
  unavailable for an extended period.

## Boundaries

- Provider generation and shared request gating belong to
  `ProviderRuntimeRegistry` and `ProviderRequestGate`; started transports are
  tracked rather than cancelled by new input.
- Provider request mapping and response normalization stay in
  `KnowTypeProviders`.
- The runtime does not record marked text and does not send protected-only
  batches to a provider.
- `TypingEventStore` keeps the JSONL persistence and atomic prefix-claim
  boundary. Its process-local inventory is shared by normalized path and is
  rebuilt only when file metadata no longer matches.

## Behavior Notes

- Production injects one actor into every `KnowTypeInputController`, so
  `digestInFlight`, success time, and failure time are process-wide.
- Registry-backed recording obtains a usable provider lease before appending an
  event, applies generation changes before append, and reuses that lease for an
  immediately eligible digest. Batch, interval, protected-only, and unchanged
  generation cooldown gates use inventory before any digest snapshot decode.
- One actor-owned deadline task wakes batch, interval, and provider-cooldown
  deadlines. A successful commit starts a 600-second minimum interval that a
  batch of 50 cannot bypass; provider generation changes do not reset it.
- Stale responses cannot write `ENV.md` or archive events. Shared gate cooldown
  and max-one-in-flight identity state apply equally to recommendation and
  digest.
- Final persistence holds both the provider-generation guard and the pending
  snapshot file claim. While transport is in flight, backlog compaction retains
  that exact claim plus the newest bounded tail. Events appended after the
  claimed prefix remain pending.
- Failed and empty digests retain the minimum retry interval while still
  checking for a changed provider revision. Protected-only pending batches
  archive locally without provider or provider-profile reads; a protected-only
  bounded prefix in a mixed backlog is also archived without a provider call.
- Raw input and locked prefix over 4 KiB skip AI without semantic truncation.
  Pending JSONL keeps at most 500 events or 1 MiB and compacts to the newest
  450 events/768 KiB after overflow. Existing oversized files are compacted
  through a bounded suffix read before inventory decoding. A provider request
  contains at most 50 oldest events or 48 KiB, plus 64 KiB logical and 96 KiB
  HTTP-body limits; blank, malformed, and oversized legacy prefixes are
  recovered locally instead of being sent.
- A successful digest prunes `processed/` best-effort to 7 days, 100 files, and
  10 MiB. Startup, install, protected-only archive, and failed digests do not
  trigger historical cleanup.
- `context_event_truncated`, `context_backlog_trimmed`,
  `context_digest_deferred`, and `context_archive_pruned` diagnostics contain
  counts and durations only, never event or provider text.
- A privacy-safe claim records only prefix hash, byte/event counts, generated
  section hash, and provider generation. ENV-success/archive-failure recovery
  archives that exact prefix and leaves appended tail bytes pending.

## Tests

- `AIContextMemoryRuntimeTests`
- `ProviderRuntimeRegistryTests`
