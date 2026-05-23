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
- It extracts usable output text and passes it through shared response
  normalization.
- Requests prefer `text.format.type=json_schema` with `strict=true`.
- If an OpenAI-compatible Responses runtime rejects only `json_schema`, fallback
  retries once with `text.format.type=json_object`.
- If the runtime rejects the Responses `text` field itself, fallback retries once
  without `text.format` and relies on the prompt plus strict local decoding.

## Tests

- `ProviderAdapterTests`
