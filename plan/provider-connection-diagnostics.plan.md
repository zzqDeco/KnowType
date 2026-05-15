# Provider Connection Diagnostics

## Goal

Make AI provider configuration observable from the settings app so users can verify whether KnowType is calling a real provider before testing inside the input method.

## Behavior

- `KnowTypeProviders` exposes `ProviderConnectionDiagnostic`.
- The diagnostic builds the configured provider and sends one small prefix-locked continuation request.
- Empty provider responses fail the diagnostic instead of being treated as success.
- `ProviderProfilesViewModel` can test the current draft configuration without saving profile metadata.
- A non-blank draft API key is used only for the test request and is not persisted.
- A blank draft API key can reuse an existing saved `secretName` value when available.
- Remote providers that require a key fail before making a test request when no key is available.
- The settings UI shows testing, success, and failure status in the AI Provider tab.

## Verification

```bash
swift test --filter ProviderProfileTests
swift test --filter ProviderProfilesViewModelTests
swift test
git diff --check
```
