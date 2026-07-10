# Provider API Contracts And Template Rendering

Status: Active

## Summary

- Update current provider model defaults and harden wire-response handling for
  the OpenAI Responses and Anthropic Messages APIs.
- Make Custom HTTP body rendering deterministic and non-recursive.
- This slice closes GitHub issues #178 and #179 only.

## Scope

- Use `claude-haiku-4-5-20251001` and `gemini-3.5-flash` for new Anthropic and
  Gemini profiles.
- Migrate only the exact retired model IDs on canonical official endpoints, once
  through the provider-file revision transaction.
- Traverse every OpenAI Responses message and `output_text` content item, while
  rejecting refusals and incomplete responses before structured decoding.
- Omit Anthropic sampling parameters from default request bodies and keep
  connection diagnostics on the same completion request builder.
- Tokenize Custom HTTP placeholders once over the original template, reject
  unknown or unclosed placeholders, and serialize `request_json` with sorted
  keys.
- Do not change prompts, prefix-lock sanitization, provider selection, secrets,
  or unrelated Wave 2 issues.

## Implementation

- `ProviderProfileTemplates` owns both current template IDs and the narrow
  revision-aware migration. It requires the matching provider kind, exact
  retired model string, HTTPS official host, provider-specific official path,
  and no query before replacing a saved model. Anthropic accepts root and
  `/v1`; Gemini remains root-only. Runtime and Settings loading invoke the same
  helper.
- `OpenAIResponsesProvider` checks response completion state first, skips
  non-message output such as reasoning, walks all message content, rejects any
  refusal, concatenates all `output_text` items, then performs one strict decode.
- `AnthropicMessagesProvider` builds structured and fallback attempts through
  one request builder containing no `temperature`, `top_p`, or `top_k` fields.
- `CustomHTTPProvider` appends literal and replacement spans during one scan.
  Replacement text is never fed back to the tokenizer.

## Test Plan

- `swift test --filter 'ProviderAdapterTests|ProviderProfileTests|ProviderProfilesViewModelTests'`
- `swift test`
- `git diff --check`
- Check README, plan index, and source-note links resolve to existing files.

## Assumptions

- Compatible OpenAI proxies may continue returning the SDK-style top-level
  `output_text` field only when no raw `output` array is present.
- Custom proxy endpoints retain user-selected model IDs even when those IDs
  match a retired official model.
- Env-gated provider live smoke remains optional and does not require a real key
  during the default test run.
