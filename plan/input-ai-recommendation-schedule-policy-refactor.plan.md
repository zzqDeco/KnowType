# Input AI Recommendation Schedule Policy Refactor

## Summary

- Extract real-time AI recommendation schedule eligibility from
  `InputControllerCoordinator` into `InputAIRecommendationSchedulePolicy`.
- Keep the policy pure; asynchronous request creation, cancellation, patch
  validation, and lifecycle diagnostics now live in
  `InputAIRecommendationRuntime`.

## Scope

- Add a pure policy type under `Sources/KnowTypeInputMethod`.
- Move the existing schedule/skip decision branches for stable input, trigger
  length, secret-like text, runtime preference, and provider availability into
  the policy.
- Add focused policy tests.
- Update source notes and current-state docs for the new boundary.

## Implementation

- `InputAIRecommendationScheduleContext` carries only value data needed for the
  decision.
- `InputAIRecommendationScheduleDecision` returns `.schedule` or `.skip` with
  the exact `AIRecommendationState`, diagnostic stage, and reason the coordinator
  should publish.
- `InputAIRecommendationRuntime` asks the policy once before starting provider
  work, records skipped decisions, and returns the skipped AI state to the
  coordinator for candidate-panel refresh.

## Test Plan

- `swift test --quiet --filter InputAIRecommendationSchedulePolicyTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`

## Assumptions

- This PR is behavior-preserving.
- Task lifecycle and patch-apply state have moved to
  `InputAIRecommendationRuntime`; keep this policy limited to value decisions.
