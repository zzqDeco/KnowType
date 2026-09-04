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
  event, including the gate-persistence-blocked append-only fallback, and
  applies generation changes before append. A missing or disabled provider
  leaves no new JSONL event; an available fallback lease preserves bounded
  prefix-protected append without starting a provider request or cancelling the
  current blocked preflight's gate-persistence retry deadline. The actor
  revalidates recovery after the lease await: a new claim backoff remains
  fail-closed, while completed recovery routes the event through normal
  scheduling instead of fallback return. The normal path
  reuses its lease for an immediately eligible digest. Batch, interval,
  protected-only, and unchanged generation cooldown gates use inventory before
  any digest snapshot decode.
- One actor-owned deadline task wakes batch, interval, provider-cooldown, and
  shared-gate availability events. The first below-batch pending event records
  a forced deadline. Registry-backed success samples wall time inside the final
  `commitIfCurrent` operation after its generation/revision waits; direct-provider
  success runs the same synchronous persistence closure. The sample, or the
  prior anchor's smallest representable successor after clock rollback, becomes
  the bounded monotonic success anchor. That anchor, not request start, begins
  the configured successful-commit interval that a full batch cannot bypass;
  provider generation changes do not reset it.
  Gate-busy state suppresses additional snapshot decode until the one
  cancellable availability waiter wakes, is invalidated, or is cancelled.
- Stale responses cannot write `ENV.md` or archive events. Shared gate cooldown
  and max-one-in-flight identity state apply equally to recommendation and
  digest. The caller-visible hard timeout wraps gate execution; it returns
  immediately while cancellation-resistant provider work keeps the identity
  lease until actual completion. The single-flight attempt owner records a hard
  timeout once; cancellation-marked late failures only release that lease.
- Direct provider-injected runtimes derive their gate identity from
  `provider.providerName` by default, matching direct recommendation runtimes;
  registry-backed runtimes continue to use the generation fingerprint.
- Final persistence holds both the provider-generation guard and the pending
  snapshot file claim. While transport is in flight, backlog compaction retains
  that exact claim plus the newest bounded tail. Events appended after the
  claimed prefix remain pending.
- Failed and empty digests use the shared gate's 60-second exponential retry
  (429 `Retry-After` is clamped to 15 seconds through 15 minutes), which is
  separate from the 600-second successful-commit interval. Protected-only pending batches
  archive locally without provider or provider-profile reads; a protected-only
  bounded prefix in a mixed backlog is also archived without a provider call.
  Neither path advances the provider-success timestamp; any unprotected tail is
  scheduled by the normal pending rules.
- Raw input and locked prefix over 4 KiB skip AI without semantic truncation.
  Pending JSONL keeps at most 500 events or 1 MiB and compacts to the newest
  450 events/768 KiB after overflow. Existing oversized files are compacted
  through a bounded suffix read before inventory decoding. A provider request
  contains at most 50 oldest events or 48 KiB, plus 64 KiB logical and 96 KiB
  HTTP-body limits; blank, malformed, and oversized legacy prefixes are
  recovered locally instead of being sent. If a local archive leaves a tail,
  inventory is rechecked and the single eligible deadline is rearmed without
  waiting for another input event.
- Every successful local archive, whether produced by a provider commit,
  protected-only handling, an invalid/unsendable prefix, an oversized line, or
  persisted claim recovery, invokes the store's best-effort `processed/`
  retention prune while the existing file lock is held. The targets remain 7
  days, 100 files, and 10 MiB, but the current archive is protected from every
  deletion criterion; failed older-file cleanup may therefore leave the
  directory temporarily over target. Startup, initialization, installation,
  and provider failures that produce no archive do not scan or rewrite
  historical archives.
- `context_event_truncated`, `context_backlog_trimmed`,
  `context_digest_deferred`, and `context_archive_pruned` diagnostics contain
  counts and durations only, never event or provider text.
- A privacy-safe claim records only prefix hash, byte/event counts, generated
  section hash, and provider generation. ENV-success/archive-failure recovery
  reads and validates only the claimed byte/event prefix, ensures the
  final-anchor receipt, archives that exact prefix, and leaves appended tail
  bytes pending. Live success also writes the receipt before archive creation or
  prefix removal, so receipt failure leaves the prefix pending and unarchived.
  The receipt is timestamp evidence, not archive proof: only a deterministic
  processed archive with matching byte count and SHA-256 proves completion;
  missing, oversized, or same-size corrupt archive evidence remains blocked. A
  matching ENV with a changed claim prefix still fails closed without another
  provider request. A claim written before ENV replacement also remains blocked when its
  generated hash is absent, so restart cannot redispatch that prefix. Corrupt
  schedule state is replaced with a conservative minimum-interval delay; if
  that state cannot be persisted, processing stays blocked.
  When no receipt exists, recovery persists bounded recovery time before any
  archive, including for a legacy already-valid archive.
  Timestamp/count schedule state survives runtime or process rebuild and is
  written before claim cleanup. Schedule load sorts and exactly deduplicates the
  storage-bounded success history without applying a startup-relative rolling
  cutoff. Eligibility and deferral use a temporary now-relative copy; ordinary
  schedule writes preserve the loaded anchors until live success or claim
  recovery replaces them with completion-relative bounded history. Receipt
  time, successful history, last success, pending-tail bound/fallback, and
  persisted/in-memory next deadline share the final success anchor. Its strict
  monotonicity keeps each committed digest as a distinct rolling-budget slot
  while the existing future-anchor bound keeps the schedule restart-valid. The
  prior last-success anchor is restored into
  normalized history only inside the completion-relative rolling window and
  future bound. If it is within the schedule's `<1 ms` semantic tolerance of the
  retained history's latest entry, that entry already represents the prior
  success; other anchors retain exact identity. Sorting and deduplication apply
  equally during recovery. Live success and completed-claim recovery then keep
  the newest runtime-budget slots after including the current anchor. When the
  prior anchor already equals the completion-relative upper bound, success
  persistence fails before claim, ENV, archive, receipt, or schedule-success
  mutation. Pending events and existing
  budget slots remain intact while the normal local commit-failure cooldown path
  handles recovery. Successful commits rearm the one deadline task when a tail
  remains; an empty store cancels it.

## Tests

- `AIContextMemoryRuntimeTests`
- `ProviderRuntimeRegistryTests`
