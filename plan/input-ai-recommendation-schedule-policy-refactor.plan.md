# Input AI Recommendation Schedule Policy Refactor

## Summary

- Extract real-time AI recommendation schedule eligibility from
  `InputControllerCoordinator` into `InputAIRecommendationSchedulePolicy`.
- Keep asynchronous request creation, cancellation, patch application, and panel
  updates in the coordinator for this slice.

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
- `InputControllerCoordinator.scheduleAIRecommendation` asks the policy once,
  handles skipped decisions by recording diagnostics and refreshing the panel,
  and leaves request construction plus task lifecycle unchanged.

## Test Plan

- `swift test --quiet --filter InputAIRecommendationSchedulePolicyTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`

## Assumptions

- This PR is behavior-preserving.
- The next AI refactor can consider extracting task lifecycle and patch-apply
  state after this pure policy boundary is in place.
