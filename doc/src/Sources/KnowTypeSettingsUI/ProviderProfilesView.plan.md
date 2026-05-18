# ProviderProfilesView

## Responsibility

`ProviderProfilesView` presents provider profile editing, API-key entry, model
configuration, custom HTTP fields, and connection testing.

## Boundaries

- Validation and persistence behavior belong to `ProviderProfilesViewModel`.
- Provider adapter behavior belongs to `KnowTypeProviders`.

## Behavior Notes

- Draft API keys used for connection tests are transient unless the user saves.
- The view should not display or persist raw stored Keychain values.
- UI copy should distinguish local OpenAI-compatible endpoints from remote
  provider profiles.

## Tests

- `ProviderProfilesViewModelTests`
- `ProviderProfilesPresentationTests`
- Manual settings UI check when layout changes
