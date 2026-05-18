# KeychainSecretStore

## Responsibility

`KeychainSecretStore` stores provider API keys in macOS Keychain under the
KnowType service.

## Boundaries

- Provider JSON stores `secretName`, not secret values.
- Settings and runtime code should use the `SecretStore` protocol rather than
  Keychain APIs directly.

## Behavior Notes

- Secret mutations are coordinated with provider profile saves so failed writes
  do not publish half-saved profiles.
- Tests can use in-memory stores to avoid touching a developer Keychain.

## Tests

- `ProviderProfileTests`
- `ProviderProfilesViewModelTests`
