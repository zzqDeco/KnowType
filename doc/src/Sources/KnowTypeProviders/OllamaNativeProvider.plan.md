# OllamaNativeProvider

## Responsibility

`OllamaNativeProvider` adapts Ollama `/api/chat` requests into
`LLMProvider.complete`.

## Boundaries

- Ollama-native chat envelopes stay in `KnowTypeProviders`.
- Local Ollama behavior must still normalize into the same `LLMResponse`
  consumed by core and input-method code.

## Behavior Notes

- The adapter disables streaming for the MVP request/response path.
- Local endpoints may omit API keys.
- Response parsing should fail clearly when no usable message content is
  returned.

## Tests

- `ProviderAdapterTests`
