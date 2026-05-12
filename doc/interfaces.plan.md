# KnowType Interfaces

## LLMRequest

```text
LLMRequest {
  task: correction | continuation | polish
  locked_prefix?: string
  raw_input?: string
  locale: zh-CN | en-US | mixed
  app_context?: string
  max_candidates: number
  length_level?: short | medium | long
  output_schema: json
}
```

Swift uses camelCase property names while provider payloads may serialize them through adapter-specific bodies.

## LLMResponse

```text
LLMResponse {
  candidates: [
    { text: string, confidence?: number, reason?: string }
  ]
}
```

## Provider Kinds

- `openai_chat`
- `openai_responses`
- `anthropic_messages`
- `gemini_native`
- `ollama_native`
- `custom_http`

## Provider Profiles

Provider profiles are stored separately from API keys:

```text
ProviderProfile {
  id
  displayName
  kind
  baseURL
  model
  timeoutSeconds
  headers
  secretName?
  customBodyTemplate?
  customResponsePath?
  isDefault
}
```

`secretName` resolves through `SecretStore`. The macOS implementation uses Keychain; tests and non-UI code can use read-only dictionary-backed stores.

## Candidate Types

- `CorrectionCandidate`: prefix candidate with correction level and protected ranges.
- `LockedPrefix`: selected immutable prefix.
- `ContinuationCandidate`: text after the locked prefix only.
- `SuggestionResponse`: complete UI-facing suggestion state.

## Shortcut Contract

- `Space` -> commit prefix.
- `Tab` -> commit prefix plus first continuation.
- `Option + number` -> commit prefix plus the continuation shown with that shortcut. `Tab` owns the first continuation; `Option + 1` starts at the second continuation.
- `Option + R` -> request polish for original text.
