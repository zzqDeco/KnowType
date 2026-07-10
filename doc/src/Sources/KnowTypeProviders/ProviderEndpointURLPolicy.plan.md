# ProviderEndpointURLPolicy

## Responsibility

`ProviderEndpointURLPolicy` is the shared provider-layer contract for accepting
runtime Base URLs and rendering privacy-safe endpoint summaries.

## Behavior Notes

- Accepted URLs use HTTP or HTTPS and include a host.
- Usernames, passwords, and fragments are rejected.
- Query parameters remain accepted for runtime compatibility.
- Diagnostic summaries retain only scheme, host, port, and path. They always
  remove userinfo, query, and fragment and return a fixed placeholder if the URL
  cannot be decomposed safely.
- `ProviderProfileResolver` rechecks this policy so manually edited persisted
  profiles cannot bypass Settings validation.

## Tests

- `ProviderProfileTests`
- `ProviderProfileEditingPolicyTests`
- Shared fixtures in `Tests/Fixtures/provider-endpoint-summary.json`
