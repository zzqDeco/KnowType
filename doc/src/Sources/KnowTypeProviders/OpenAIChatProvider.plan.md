# OpenAIChatProvider

## Responsibility

`OpenAIChatProvider` adapts OpenAI-compatible `/v1/chat/completions` endpoints.

## Boundaries

- OpenAI-compatible chat request and response fields do not leave the provider
  layer.
- Model discovery is coordinated by `ProviderModelDiscovery`, not by callers.

## Behavior Notes

- Local OpenAI-compatible runtimes may use a blank model so discovery can select
  a completion-capable model.
- Remote OpenAI-compatible profiles require an explicit model ID.
- The adapter builds non-streaming requests and normalizes text into
  `LLMResponse`.

## Tests

- `ProviderAdapterTests`
- Env-gated `ProviderLiveSmokeTests`
