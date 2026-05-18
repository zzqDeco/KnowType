# ProviderConnectionDiagnostic

## Responsibility

`ProviderConnectionDiagnostic` verifies a draft provider configuration from
settings without saving it.

## Boundaries

- Diagnostics must not write provider JSON or mutate `SecretStore`.
- Draft validation belongs in settings presentation and ViewModel code; adapter
  construction remains provider-layer work.

## Behavior Notes

- The diagnostic sends a small prefix-locked continuation request.
- Blank candidate lists and blank text are reported as failures.
- In-flight results for stale drafts should be ignored by the settings
  ViewModel.

## Tests

- `ProviderProfilesViewModelTests`
- `ProviderAdapterTests`
