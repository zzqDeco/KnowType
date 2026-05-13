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

`secretName` resolves through `SecretStore`. The macOS implementation uses Keychain under the `KnowType` service; tests and non-UI code can use in-memory or read-only dictionary-backed stores.

Default file-backed profile storage writes `providers.json` under the user's Application Support `KnowType` directory. This file stores provider metadata, configured headers, and secret names. API key values represented by `secretName` must move through `SecretStore`; custom header values are persisted as configured and should not contain secrets in the MVP.

Settings UI code should treat `ProviderProfile` as the persistence boundary for provider profiles. It may create profiles, edit profiles, and select defaults, but API key values must move through `SecretStore` instead of the profile file.

## Provider Factory

Runtime provider loading uses:

```text
ProviderFactory.makeProvider(configuration:httpClient:) -> LLMProvider
```

The factory maps `ProviderKind` to one adapter and keeps provider-specific request and response shapes inside `KnowTypeProviders`.

`ProviderProfilesViewModel` owns settings-app draft validation and persistence. It rejects empty names, invalid non-HTTP(S) or hostless base URLs, missing models for non-custom providers, non-positive timeouts, incomplete custom HTTP templates, and blank cloud-provider API keys when no existing non-empty `SecretStore` entry can be reused. Custom HTTP profiles can be saved without an API key, but a non-blank entered key is stored as a profile-scoped secret. Draft saves stage the updated profile list, persist the staged profile file, apply any required secret write or delete, roll the profile file back if the secret mutation fails, and publish the new `profiles` value only after both stores succeed. Secret deletion is skipped while another saved profile still references the same `secretName`.

## Candidate Types

- `CorrectionCandidate`: prefix candidate with correction level and protected ranges.
- `LockedPrefix`: selected immutable prefix.
- `ContinuationCandidate`: text after the locked prefix only.
- `SuggestionResponse`: complete UI-facing suggestion state.

Input-method candidate presentation maps `SuggestionResponse` into compact macOS-style candidate rows:

- raw input is shown only before any prefix or continuation suggestion exists
- prefix candidates are first-class candidates
- continuation candidates are selectable candidates but still commit as `locked prefix + continuation`
- fallback local breadth is six medium candidates for both correction alternatives and continuations where available
- when a provider is configured, the immediate local pass may omit fallback continuations until the provider-backed suggestion publishes

## Shortcut Contract

- `Space` -> commit prefix.
- `Tab` -> commit prefix plus first continuation.
- `Option + number` -> commit prefix plus the continuation shown with that shortcut. `Option + 1` matches the first continuation, which is also available through `Tab` and displayed as `⇥`.
- `Option + R` -> request polish for original text.

## Level 0 Contract

Level 0 input must not call cloud providers. The session controller routes protected input through a no-provider pipeline, clears continuation candidates, and preserves the protected text for commit.

Level 0 includes URL-like input, email-like input, file paths, command-like input, code-like snippets, and protected Terminal, iTerm, and Xcode contexts.
