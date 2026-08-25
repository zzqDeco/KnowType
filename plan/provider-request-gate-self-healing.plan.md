# Provider Request Gate Self-Healing

## Summary

- Fix Issue #217 so a running input-method process can recover after the
  provider request-gate state becomes readable or writable again.
- Keep persistence failures fail-closed without requiring an input-method
  restart and without turning recovery into repeated hot-path disk work.

## Scope

- Give `ProviderRequestGate` one shared persistence-recovery state machine with
  bounded retry deadlines and Provider generation-triggered revalidation.
- Remove process-lifetime persistence-blocked latches from recommendation and
  Context Digest runtimes.
- Preserve valid persisted cooldowns, started-transport ownership, generation
  fencing, bounded Context Digest storage, and privacy-safe diagnostics.
- Do not change provider protocols, gate persistence schema, prompt content,
  public SwiftPM APIs, settings, or input-event behavior.

## Implementation

- Persistence read/decode failures recover by reloading the bounded mode-0600
  gate file; write/replace/permission failures recover by retrying the desired
  in-memory state.
- Failed recovery uses actor-owned exponential backoff from 5 through 60
  seconds. Preflight calls before the deadline return the same blocked result
  without reading or writing the file.
- The first new Provider generation may force one immediate revalidation. It
  does not clear the blocked state, an active cooldown, or a started transport.
- A started transport completing during backoff updates the desired in-memory
  rewrite without issuing an early persistence operation; stale generation
  invalidations cannot force a probe.
- Generation invalidation records in-memory clear tombstones so stale persisted
  cooldowns cannot reappear after a later recovery.
- Recommendation reports `AI 状态异常，正在重试` while blocked. Context Digest
  appends within its existing limits and schedules one gate-recovery deadline
  without repeatedly decoding pending JSONL, claim metadata, or ENV.
- Unified-log transition events contain only stage, generation, a shortened
  identity hash, operation, failure count, and retry duration.

## Test Plan

- Cover bounded no-I/O backoff, deadline and generation recovery, corrupt-file
  replacement/removal, transient read and write failures, cooldown retention,
  and stale-state non-resurrection in `ProviderRuntimeRegistryTests`.
- Cover same-instance recommendation and Context Digest recovery, no repeated
  context reads while blocked, event preservation, and privacy-safe diagnostics.
- Run focused AI tests, `swift test`, `./scripts/perf-input-hotpath.sh`, and
  `git diff --check`.

## Assumptions

- The existing gate JSON schema remains valid and requires no migration.
- A missing state file is safe empty-state evidence; directories, unreadable
  paths, malformed data, and uncertain replacements remain fail-closed.
- Recovery availability is bounded by the 5–60 second backoff unless a genuinely
  new Provider generation triggers the one immediate probe.
