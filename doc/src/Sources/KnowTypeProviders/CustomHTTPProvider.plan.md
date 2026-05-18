# CustomHTTPProvider

## Responsibility

`CustomHTTPProvider` supports user-defined local or proxy endpoints through a
body template and response path.

## Boundaries

- It is an adapter for advanced configuration, not a place for product prompt
  policy.
- Custom endpoint response shapes must normalize into `LLMResponse`.

## Behavior Notes

- Profile validation requires a body template and response path.
- API keys are optional so local proxy endpoints can run without secrets.
- Custom headers are persisted as configured; users should not place bearer
  tokens in headers for the MVP.

## Tests

- `ProviderAdapterTests`
- `ProviderProfileTests`
