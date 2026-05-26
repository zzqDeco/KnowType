# ProviderModelDiscovery

## Responsibility

`ProviderModelDiscovery` discovers usable local OpenAI-compatible models when a
profile intentionally leaves the model blank.

## Boundaries

- Discovery is for local OpenAI-compatible runtime convenience.
- Remote profiles still require explicit model IDs.
- Adapter callers should receive a resolved `ProviderConfiguration`.

## Behavior Notes

- Discovery skips obvious non-completion model IDs such as image or embedding
  models.
- Failure to discover a model should surface as a provider configuration or
  diagnostic failure rather than a silent fallback.
- Env-gated provider live smoke keeps discovery coverage separate from
  continuation runtime-budget coverage. Continuation smoke uses an explicit
  model so model-list ordering does not decide product-path latency.

## Tests

- `ProviderProfileTests`
- Env-gated `ProviderLiveSmokeTests`
