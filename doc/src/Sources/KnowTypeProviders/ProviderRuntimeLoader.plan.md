# ProviderRuntimeLoader

## Responsibility

`ProviderRuntimeLoader` resolves saved provider profiles and creates the runtime
provider used by the input method.

## Boundaries

- It resolves metadata and secrets; it does not own UI validation or prompt
  policy.
- Core and input-method code should receive an optional `LLMProvider` rather
  than provider-specific configuration.

## Behavior Notes

- Missing or empty profile storage falls back to `ProviderProfileTemplates`.
- `secretName` values resolve through `SecretStore`.
- IMK cold-start paths use `loadDefaultProvider(createProfileDirectory: false)`
  through lazy AI runtimes. This reads an existing profile when present but does
  not create `Application Support/KnowType` only because the host was launched.
- Runtime loading should fail transparently enough for diagnostics without
  leaking secret values.

## Tests

- `ProviderProfileTests`
- `ProviderProfilesViewModelTests`
- Input-method provider fallback tests
