# ResponseNormalizer

## Responsibility

`ResponseNormalizer` converts provider text into normalized `LLMResponse`
candidate lists.

## Boundaries

- It handles provider-output cleanup, not HTTP transport.
- It must not weaken core prefix-lock enforcement.

## Behavior Notes

- Providers may return JSON, plain text, full sentences, repeated prefixes, or
  blank text.
- Continuation candidates must be usable by `PrefixContinuationEngine`
  sanitization before display.
- Empty usable output should surface as no candidates or a diagnostic failure
  depending on caller context.

## Tests

- `ProviderAdapterTests`
- `PrefixContinuationEngineTests`
