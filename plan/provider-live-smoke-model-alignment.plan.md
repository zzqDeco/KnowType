# Provider Live Smoke Model Alignment Plan

## Summary

- Align env-gated provider live smoke with the product model path used in local
  acceptance.
- Keep model discovery covered as its own smoke, but do not let continuation
  runtime-budget validation inherit the first model returned by `/v1/models`.

## Scope

- Update only `ProviderLiveSmokeTests` and documentation.
- Do not change product runtime timeout, prompts, trigger policy, provider
  profile defaults, or settings UI.

## Implementation

- Add `KNOWTYPE_PROVIDER_LIVE_MODEL` as the explicit live-smoke model override.
- Resolve continuation live-smoke model in this order: environment override,
  local default OpenAI-compatible provider profile, then built-in fallback
  `gpt-5.3-codex-spark`.
- Keep the discovery smoke using a blank model and `/v1/models`.
- Make the continuation smoke use the resolved explicit model and assert that it
  calls only `/v1/chat/completions`.
- Include the effective model, model source, and override hint in transport,
  runtime-budget, and invalid-continuation failures.

## Test Plan

- `swift test --quiet --filter ProviderLiveSmokeTests`
- `KNOWTYPE_PROVIDER_LIVE_SMOKE=1 swift test --quiet --filter ProviderLiveSmokeTests`
- `swift test --quiet`
- `./scripts/smoke-inputmethod-install.sh`
- `./scripts/perf-input-hotpath.sh`
- `git diff --check`

## Assumptions

- Product AI runtime hard timeout remains `10_000ms`.
- Model list order is not a reliable product acceptance signal.
- Local acceptance currently expects `gpt-5.3-codex-spark`, but the environment
  override keeps the smoke usable for other local OpenAI-compatible runtimes.
