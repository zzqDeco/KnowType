# Provider Endpoint Summary Helper

## Responsibility

`scripts/lib/provider_endpoint_summary.py` renders the provider endpoint shown
by `scripts/diagnose-inputmethod.sh` in text and JSON modes.

## Privacy Contract

- Keep only scheme, host, port, and path.
- Remove username, password, query, and fragment for every output mode.
- Append `[query redacted]` when a non-empty query was removed, without exposing
  query keys or values.
- Return `<invalid endpoint>` rather than echoing an input that cannot be parsed
  safely.
- Do not inspect provider secrets or Keychain state.

The helper and Swift `ProviderEndpointURLPolicy` are both validated against
`Tests/Fixtures/provider-endpoint-summary.json` so their output cannot drift
silently.

## Packaging

`scripts/package-dmg.sh` copies the helper beside the packaged diagnostic script
under `Scripts/lib/`.
