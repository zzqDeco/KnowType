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
- On a 429 response, the HTTP validation boundary gives a valid standard
  `Retry-After` header precedence. It parses finite non-negative delay seconds,
  IMF-fixdate, RFC 850 obsolete-date, and ANSI C asctime-date. RFC 850
  two-digit years use the injected current time: dates within 50 years in the
  future keep that century, while later dates resolve to the most recent past
  year with the same suffix.
- When the header has no valid value, at most 64 KiB of structured JSON may
  provide a finite numeric `reset_seconds`, `reset_time`, `retry_after`, or
  `retry_after_seconds`. Traversal depth and node count are bounded. Strings,
  booleans, negative values, current or past absolute reset times, malformed
  JSON, and oversized bodies are ignored. Absolute `reset_time` is accepted
  only when it is strictly later than the injected current time. A valid hint
  is normalized to 15 seconds through 7 days. The raw 429 body is never
  propagated or diagnosed.
- `ProviderRateLimitError` remains a source-compatible carrier: its public
  `retryAfterSeconds` property is writable and its initializer preserves the
  supplied value verbatim. Manually constructed errors can therefore carry
  arbitrary hints; the shared AI gate independently validates and bounds them.
  Provider cooldown is distinct from Context Digest's persistent success
  cadence.
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
