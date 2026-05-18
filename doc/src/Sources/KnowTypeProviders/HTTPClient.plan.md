# HTTPClient

## Responsibility

`HTTPClient` defines the async HTTP abstraction used by provider adapters and
tests.

## Boundaries

- Provider adapters depend on this abstraction instead of hard-coding
  `URLSession`.
- Product logic in `KnowTypeCore` should not depend on HTTP types.

## Behavior Notes

- Mock clients keep adapter tests deterministic and offline.
- Production request construction, headers, timeouts, and response decoding stay
  in the provider layer.

## Tests

- `ProviderAdapterTests`
- `ProviderLiveSmokeTests` when explicitly enabled by environment
