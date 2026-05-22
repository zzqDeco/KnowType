# LLMOutputContract

## Responsibility

`LLMOutputContract` owns the provider-facing JSON Schema used for AI provider
outputs.

## Boundaries

- It defines shape only; semantic prefix-lock validation remains in
  `PrefixContinuationEngine`.
- Candidate tasks share the `candidates` array contract.
- `contextDigest` uses a dedicated markdown object and is normalized only after
  strict decoding.

## Behavior Notes

- OpenAI adapters use the contract for strict `json_schema` requests.
- Gemini and Anthropic adapters use the same schema through their native schema
  hint fields.
- Unsupported schema fields fall back to JSON mode or prompt-only JSON with a
  diagnostic marker.

## Tests

- `ProviderAdapterTests`
