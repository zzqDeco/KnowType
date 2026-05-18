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

## Tests

- `ProviderAdapterTests`
