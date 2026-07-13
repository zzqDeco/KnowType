# ProviderRuntimeLoader

## Responsibility

`ProviderRuntimeLoader` resolves saved provider profiles and creates the
revisioned runtime source used by the input method.

## Boundaries

- It resolves metadata and secrets; it does not own UI validation or prompt
  policy.
- Core and input-method code should receive an optional `LLMProvider` rather
  than provider-specific configuration.

## Behavior Notes

- Missing or empty profile storage falls back to `ProviderProfileTemplates`.
- Existing profiles pass through the revision-aware retired-template migration
  before the default provider is resolved.
- `secretName` values resolve through `SecretStore`.
- IMK cold-start paths use `loadDefaultProvider(createProfileDirectory: false)`
  through lazy AI runtimes. This reads an existing profile when present but does
  not create `Application Support/KnowType` only because the host was launched.
- Runtime loading should fail transparently enough for diagnostics without
  leaking secret values.
- Runtime load results carry the canonical revision, an opaque SHA-256
  fingerprint of the resolved configuration, and the optional provider. The
  fingerprint can distinguish runtime generations without exposing endpoints,
  models, headers, or secrets.
- `loadProviderRevision()` is the lightweight missed-notification fallback used
  by `ProviderRuntimeRegistry` only before eligible AI dispatch.

## Tests

- `ProviderProfileTests`
- `ProviderProfilesViewModelTests`
- `ProviderRuntimeRegistryTests`
