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
- On a 429 response, the HTTP validation boundary parses finite, non-negative
  delay-seconds plus IMF-fixdate, RFC 850 obsolete-date, and ANSI C asctime-date.
  RFC 850 two-digit years use the injected current time: dates within 50 years
  in the future keep that century, while later dates resolve to the most recent
  past year with the same suffix. The boundary emits either `nil` or a finite
  `Retry-After` hint from 15 seconds through 15 minutes; missing and invalid
  headers remain `nil` for the shared AI gate's fallback.
- `ProviderRateLimitError` remains a source-compatible carrier: its public
  `retryAfterSeconds` property is writable and its initializer preserves the
  supplied value verbatim. Manually constructed errors can therefore carry
  arbitrary hints; the shared AI gate's defensive handling remains separate
  and unchanged. This cooldown is distinct from Context Digest's 600-second
  successful-commit interval.
- Adapters validate the logical request before transport and the serialized HTTP
  body after encoding. OpenAI Chat and Responses run aggregate logical-payload
  preflight before model discovery, so local over-limit requests perform neither
  discovery nor completion HTTP. Local budget failures are distinct from
  provider failures.
- Caller timeout ownership belongs to the shared AI gate attempt owner. A
  cancellation-marked operation that later returns a transport error releases
  its lease without recording that late error as another provider failure.

## Tests

- `ProviderAdapterTests`
- `ProviderLiveSmokeTests` when explicitly enabled by environment
