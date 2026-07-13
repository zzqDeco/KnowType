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
- Placeholder rendering scans the original template once. Replacement text is
  appended verbatim and never rescanned.
- Supported placeholders are `task`, `raw_input`, `locked_prefix`, `locale`,
  `max_candidates`, `length_level`, and `request_json`, wrapped as `{{name}}`.
- Unknown and unclosed placeholders throw `invalidTemplate` before transport.
  `request_json` uses sorted JSON keys for deterministic output.

## Tests

- `ProviderAdapterTests`
- `ProviderProfileTests`
