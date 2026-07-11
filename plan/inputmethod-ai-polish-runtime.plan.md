# Input Method AI Polish Runtime

Status: Active

## Summary

- Connect `Option + R` to a real explicit-polish provider request and candidate
  overlay.
- Keep rewriting isolated from prefix-locked continuation and require explicit
  acceptance before any host commit.

## Scope

- Add `InputAIPolishRuntime`, polish candidate state/rows, coordinator keyboard
  and accessibility handling, lifecycle cancellation, and polish commit
  classification.
- Reuse `ProviderRuntimeRegistry.shared` and existing provider adapters with
  `task: polish`.
- Do not change ordinary recommendation privacy policy, provider adapters, or
  PR #196 candidate-panel interaction guards.

## Implementation

- Gate dispatch on an active nonempty composition, protected-app/Level 0 policy,
  and secret-like detection before leasing a provider.
- Bind state to request id, composition id, raw revision, and provider
  generation; stale results and stale acceptance leases do not commit.
- Present pending and unavailable rows as disabled status rows and ready output
  as dedicated `polishCandidate` selections.
- Cancel on new input, Escape, composition finish, reset, deactivate, close, or
  provider-generation mismatch.
- Commit accepted polish as `AITypingCommitKind.polish` without context-memory
  typing events, continuation learning, feedback-span learning, lexical
  learning, or prefix-selection learning. Record only privacy-safe polish
  diagnostics.

## Test Plan

- Cover one-call dispatch and request mapping, strict privacy gating,
  pending/error state, composition/provider stale drops, explicit keyboard and
  accessibility acceptance, cancellation, learning isolation, and nonblocking
  dispatch.
- Run focused tests, full `swift test`, and `git diff --check`.

## Assumptions

- Provider structural normalization for `task: polish` is already authoritative.
- Manual acceptance still needs a real installed-build check in protected and
  ordinary host apps after merge.
