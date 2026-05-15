# Provider Runtime Seeded Defaults

## Goal

Keep the settings app and input-method runtime aligned when `providers.json` has not been created yet.

## Behavior

- Default provider templates live in `KnowTypeProviders`, not only in the settings app.
- The first seeded default is a local OpenAI-compatible profile:
  - kind: `openai_chat`
  - base URL: `http://127.0.0.1:8317/v1`
  - model: blank, resolved later through `/v1/models`
  - API key: optional and stored only through `SecretStore` when the user saves one
- `ProviderRuntimeLoader` loads seeded defaults when the profile store is empty, so the IMK runtime can attempt real local provider requests without requiring a prior settings save.
- Existing non-empty profile stores remain authoritative. If the user has saved profiles, runtime loading uses those profiles only.
- Runtime loading remains best-effort: store, secret, or provider construction failure returns `nil` so traditional input is not blocked.

## Verification

```bash
swift test --filter ProviderProfileTests
swift test --filter ProviderProfilesViewModelTests
swift test
git diff --check
```
