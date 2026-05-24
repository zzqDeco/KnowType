# LLMOutputContract

## Responsibility

`LLMOutputContract` owns the provider-facing JSON Schema used for AI provider
outputs.

## Boundaries

- It defines shape only; semantic prefix-lock validation remains in
  `PrefixContinuationEngine`.
- Candidate tasks share the `candidates` array contract. Continuation keeps the
  same `text`, `confidence`, and `reason` fields; it does not add a required
  base-selection field because Rime hints are contextual, not confirmed input.
- `contextDigest` uses a dedicated markdown object and is normalized only after
  strict decoding.

## Behavior Notes

- OpenAI adapters use the contract for strict `json_schema` requests.
- Gemini and Anthropic adapters use the same schema through their native schema
  hint fields.
- Unsupported schema fields fall back to JSON mode or prompt-only JSON with a
  diagnostic marker.
- Fallback detection requires both a structured-output field marker and a
  capability-style error marker, so unrelated 400/422 errors such as unsupported
  models are not cached as schema failures.
- Fallback capability is scoped by provider, base URL, model, API-key
  fingerprint, and header-value fingerprints. Raw secrets are not written into
  the cache key.

## Tests

- `ProviderAdapterTests`
