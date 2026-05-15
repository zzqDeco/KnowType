# Provider Failure Continuation Fallback

## Goal

Keep provider-backed AI behavior honest in the MVP: when a provider is configured, continuation rows must come from that provider only. A failed provider request or an unusable provider response should not be replaced with fixed local fallback text that looks like AI output.

## Behavior

- `PrefixContinuationEngine` still returns deterministic local fallback continuations when no provider is configured.
- When a provider is configured, `PrefixContinuationEngine` sends the continuation request and sanitizes provider candidates as before.
- If the provider throws, returns no candidates, or returns candidates that are blank / prefix-only / rejected by prefix-lock sanitization, the continuation list is empty.
- The input method already publishes local prefix candidates before the async provider request. With this policy, provider failure leaves those traditional prefix candidates visible and does not block `Space` prefix commit.
- Level 0 privacy behavior is unchanged: protected input still calls no provider and returns no continuations.

## Verification

```bash
swift test --filter PrefixContinuationEngineTests
swift test --filter InputSessionControllerTests
swift test
git diff --check
```
