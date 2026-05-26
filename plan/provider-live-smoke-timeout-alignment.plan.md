# Provider Live Smoke Timeout Alignment Plan

## Summary

- Align provider live smoke transport timeout with the product AI runtime budget.
- Prevent local `CLIProxyAPI` responses in the 5-10 second range from being reported as transport failures when KnowType would still accept them.

## Scope

- Update only env-gated provider live smoke tests and plan documentation.
- Do not change product AI trigger policy, provider defaults, model selection, prompts, or runtime hard timeout.

## Implementation

- Add explicit live smoke constants for the provider transport timeout (`12s`) and expected runtime budget (`10s`).
- Keep `ProviderConfiguration.timeoutSeconds` in the live smoke higher than the runtime budget so the test can distinguish slow model responses from network timeout.
- Measure continuation live smoke elapsed time and fail with separate messages for provider/transport failure, runtime budget overrun, empty candidates, sanitizer rejection, and prefix repetition.

## Test Plan

- `swift test --quiet --filter ProviderLiveSmokeTests`
- `KNOWTYPE_PROVIDER_LIVE_SMOKE=1 swift test --quiet --filter ProviderLiveSmokeTests`
- `swift test --quiet`
- `git diff --check`

## Assumptions

- `AIRecommendationRuntime.Defaults.hardTimeoutMilliseconds` remains `10_000`.
- Provider profile defaults remain `timeoutSeconds = 20`; the `12s` value is test-only.
