# StructuredResponseNormalizer

## Responsibility

`StructuredResponseNormalizer` is the strict provider-output decoder for the
shared AI output contract.

## Boundaries

- It accepts only JSON objects that match the expected task contract.
- It does not perform line-based text fallback.
- Custom HTTP response paths may point directly at a candidate array, but those
  candidate objects still use the same strict field validation.

## Behavior Notes

- Decode failures are surfaced as `ProviderError.invalidResponse` with a
  `structured_decode_error` reason.
- Context digests decode `{ markdown: string }` before being wrapped into the
  common `LLMResponse` shape.

## Tests

- `ProviderAdapterTests`
