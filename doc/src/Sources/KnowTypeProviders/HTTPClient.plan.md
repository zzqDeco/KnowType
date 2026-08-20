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
- Production request construction, headers, timeouts, response decoding, and
  encoded-body budget checks stay in the provider layer.
- A 429 response becomes `ProviderRateLimitError` with only status, bounded
  `Retry-After`, and body byte count. Retry hints are clamped to 15 seconds to
  15 minutes; the shared AI gate applies 60-second exponential fallback when
  absent, capped at 15 minutes. This provider-failure cooldown is distinct
  from Context Digest's 600-second successful-commit interval.
- Adapters validate the logical request before transport and the serialized HTTP
  body after encoding. OpenAI Chat and Responses run aggregate logical-payload
  preflight before model discovery, so local over-limit requests perform neither
  discovery nor completion HTTP. Local budget failures are distinct from
  provider failures.

## Tests

- `ProviderAdapterTests`
- `ProviderLiveSmokeTests` when explicitly enabled by environment
