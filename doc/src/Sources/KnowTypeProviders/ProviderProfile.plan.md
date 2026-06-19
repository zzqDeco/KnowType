# ProviderProfile

## Responsibility

`ProviderProfile` and its stores define persisted provider metadata.

## Boundaries

- API key values are never stored in provider JSON.
- Draft UI state belongs in settings ViewModels.
- Adapter-native payloads belong in individual providers.

## Behavior Notes

- Persisted fields include display name, kind, base URL, model, timeout,
  headers, custom HTTP mapping, default status, and `secretName`.
- Validation differs for local and remote OpenAI-compatible profiles: local
  profiles may leave model blank for discovery, remote profiles may not.
- Saved profiles override seeded defaults.
- The default file store has an explicit no-create mode for runtime cold start:
  missing profile files load as an empty profile file without creating the
  `KnowType` Application Support directory. Saves still create the directory.

## Tests

- `ProviderProfileTests`
- `ProviderProfilesViewModelTests`
