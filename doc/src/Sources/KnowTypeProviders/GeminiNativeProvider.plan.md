# GeminiNativeProvider

## Responsibility

`GeminiNativeProvider` adapts Gemini native `generateContent` requests into the
normalized provider interface.

## Boundaries

- Gemini native payload and candidate envelopes stay inside this adapter.
- Core and input-method code must not depend on Gemini-specific fields.

## Behavior Notes

- The adapter maps KnowType prompts into Gemini content parts.
- It extracts text from the provider response and then uses the shared
  normalization path.
- Blank or missing candidate text is treated as unusable provider output.

## Tests

- `ProviderAdapterTests`
