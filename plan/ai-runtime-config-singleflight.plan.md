# Reload AI Providers And Serialize Context Digest

## Summary

- Apply provider profile changes to recommendation and context-digest requests
  without restarting the input-method host.
- Make context digest process-wide single-flight so one pending event snapshot
  causes at most one provider request and one claim-safe persistence commit.

## Scope

- Add a process-level provider runtime registry with revision, generation,
  opaque fingerprint, and provider leases.
- Observe the revision-only cross-process signal from provider profile storage;
  use disk revision fallback only at eligible recommendation or digest dispatch.
- Cancel generation-bound work, rebuild provider-dependent runtimes, and clear
  recommendation cache, provider health, and structured-output capability state.
- Share one context-memory actor across `KnowTypeInputController` instances and
  guard `ENV.md` plus event archive writes with current generation and snapshot
  claims.
- Cover GitHub issues #174 and #180 only. Provider schemas, prompts, input
  ordering, prefix-lock behavior, settings transaction semantics, and
  cross-process digest locking are non-goals.

## Implementation

- `ProviderRuntimeLoader` returns a revisioned runtime load result with a
  SHA-256 fingerprint; no endpoint, model, header, or secret enters diagnostics.
- `ProviderRuntimeRegistry` observes distributed revision updates, checks the
  file revision before eligible dispatch as a missed-notification fallback, and
  cancels all operations leased from an older generation.
- Recommendation runtimes are cached per generation. A stale generation returns
  an internal stale state that `InputAIRecommendationRuntime` drops before any
  UI callback.
- `AIContextMemoryRuntime` owns the process-wide digest gate. Final persistence
  runs under the registry actor while `TypingEventStore` holds the snapshot file
  claim, updates only the generated ENV section, archives only the claimed
  prefix, and preserves later appends.

## Test Plan

- Recommendation and context A-to-B provider switches without restart.
- Cancellation-resistant in-flight requests stale-drop on generation change.
- Two controller references share one digest request for one pending snapshot.
- Context failure interval, protected-only archive, appended-event preservation,
  eligibility-only disk reads, health/capability reset, and privacy-safe
  diagnostics.
- `swift test --filter 'ProviderRuntimeRegistryTests|AIContextMemoryRuntimeTests|InputAIRecommendationRuntimeTests'`
- `swift test`
- `git diff --check`

## Assumptions

- Provider profile revisions are monotonic and the storage signal is posted only
  after canonical metadata is durable.
- Process-wide single-flight is sufficient for the current single IMK host;
  cross-process digest claims remain a separate follow-up if multiple hosts are
  introduced.
