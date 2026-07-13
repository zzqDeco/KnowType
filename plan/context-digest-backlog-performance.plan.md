# Context Digest Backlog Performance

## Summary

- Bound Context Digest background work so provider failures cannot make each
  later typing event rescan an ever-growing pending JSONL file.
- Preserve provider-generation hot reload, process-wide single-flight, pending
  prefix claims, and user-owned notes in `ENV.md`.

## Scope

- Add a process-local `TypingEventInventory` keyed by normalized pending-file
  path, bounded digest snapshots, pending compaction, processed archive
  retention, and store test seams.
- Reorder `AIContextMemoryRuntime` gates so batch, interval, protected-only, and
  failure-cooldown decisions happen before snapshot decoding.
- Add privacy-safe diagnostics for truncation, backlog trimming, cooldown
  deferral, and archive pruning.
- Keep the current JSONL format, Context Digest prompt, `ENV.md` format, public
  store API, and 50-event/600-second scheduling defaults.
- Candidate anchoring, Rime startup, continuation prompts, and input-source
  behavior are outside this change.

## Implementation

- `rawInput` and `committedText` are limited to 2,048 Unicode scalars before
  persistence. Pending data is capped at 500 events or 1 MiB; overflow keeps
  the newest data and compacts to at most 450 events and 768 KiB.
- A digest claims the oldest prefix containing at most 50 events or 256 KiB,
  with one-event progress for an oversized record. Appends update inventory in
  constant time; a full inventory scan occurs only on first access or file
  metadata mismatch.
- Registry-backed recording applies provider generation before append. A
  changed generation clears the prior failure cooldown, while the same
  generation returns from cooldown before reading a digest snapshot.
- Protected-only eligible data archives locally without provider-profile reads.
  Empty and failed provider responses retain pending data and enter the same
  600-second cooldown.
- Successful provider-guarded persistence updates only the generated `ENV.md`
  section, archives exactly the claimed prefix, and then best-effort prunes
  processed files to 7 days, 100 files, and 10 MiB.
- Diagnostics contain only generation, counts, bytes, dropped/deleted counts,
  truncation lengths, and cooldown duration. They never contain event text,
  provider output, endpoint configuration, or credentials.

## Test Plan

- Verify no digest snapshot decode for events 1 through 49, one bounded decode
  at event 50, and no repeat decode during failure cooldown while 100 more
  events append.
- Verify transport and empty-response cooldowns, provider-generation recovery,
  process-wide single-flight, and preservation of appends after a claimed
  prefix.
- Verify protected-only local archive, 500-event and 1 MiB compaction, Unicode
  scalar truncation, 50-event/256 KiB requests, restart inventory recovery,
  corrupt lines, and processed archive age/count/byte retention.
- Run `swift test --filter AIContextMemoryRuntimeTests`,
  `swift test --filter ProviderRuntimeRegistryTests`, `swift test`,
  `./scripts/perf-input-hotpath.sh`, and `git diff --check`.

## Assumptions

- Pending Context Digest events are derived learning data, so overflow may drop
  the oldest records while retaining the newest 500-event window.
- Existing pending JSONL files require no migration and enter the new bounds on
  first real record.
- Existing processed history is not touched during startup or install; pruning
  begins only after a later successful digest.
