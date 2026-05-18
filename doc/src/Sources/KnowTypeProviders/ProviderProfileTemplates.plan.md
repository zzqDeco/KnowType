# ProviderProfileTemplates

## Responsibility

`ProviderProfileTemplates` owns seeded provider defaults shared by settings and
the input-method runtime.

## Boundaries

- Seeded templates are defaults, not saved user configuration.
- They must not embed API keys.

## Behavior Notes

- The default seeded profile is local OpenAI-compatible at
  `http://127.0.0.1:8317/v1`.
- The model may remain blank for local `/v1/models` discovery.
- Settings and runtime loading should use the same seeded defaults so a fresh
  install behaves consistently.

## Tests

- `ProviderProfileTests`
- `ProviderProfilesViewModelTests`
