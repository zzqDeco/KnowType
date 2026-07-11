# OpenAIResponsesProvider

## Responsibility

`OpenAIResponsesProvider` adapts OpenAI Responses API requests into the shared
provider interface.

## Boundaries

- Responses API output item shapes stay in this adapter.
- Callers should not distinguish chat versus responses providers after
  normalization.

## Behavior Notes

- The adapter maps task-specific prompts into a non-streaming Responses request.
- It requires completed output, skips reasoning and other non-message items,
  traverses every message and `output_text` content item, and decodes the
  concatenated text once.
- Any refusal, incomplete response, or incomplete message is rejected before
  structured decoding, even if an earlier text item looks parseable.
- Requests prefer `text.format.type=json_schema` with `strict=true`.
- If an OpenAI-compatible Responses runtime rejects only `json_schema`, fallback
  retries once with `text.format.type=json_object`.
- If the runtime rejects the Responses `text` field itself, fallback retries once
  without `text.format` and relies on the prompt plus strict local decoding.

## Tests

- `ProviderAdapterTests`
