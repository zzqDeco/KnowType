# ProviderConfiguration

## Responsibility

`ProviderConfiguration` is the resolved runtime configuration passed into
provider adapters.

## Boundaries

- It is built from profiles and secrets before adapter creation.
- It should not persist secrets or UI draft state.

## Behavior Notes

- Endpoint normalization handles base URLs with or without trailing `/v1`.
- Timeout, model, headers, base URL, API key, and custom HTTP mapping are
  resolved before the adapter runs.

## Tests

- `ProviderProfileTests`
- `ProviderAdapterTests`
