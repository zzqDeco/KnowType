# AnthropicMessagesProvider

## Responsibility

`AnthropicMessagesProvider` adapts Anthropic Messages requests into
`LLMProvider.complete`.

## Boundaries

- Anthropic request and response fields stay inside `KnowTypeProviders`.
- Callers receive only normalized `LLMResponse`.

## Behavior Notes

- The adapter builds a non-streaming Messages request from `LLMRequest`.
- It applies authentication and version headers through provider configuration.
- Text extraction must tolerate provider envelope differences but reject blank
  usable output.

## Tests

- `ProviderAdapterTests`
