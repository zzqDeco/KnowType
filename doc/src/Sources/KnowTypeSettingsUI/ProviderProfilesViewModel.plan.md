# ProviderProfilesViewModel

`ProviderProfilesViewModel` is the settings-app state owner for provider profile editing.

## Responsibilities

- Load provider profiles from `ProviderProfileStore`, seeding default profiles when the store is empty.
- Use `KnowTypeProviders.ProviderProfileTemplates` so settings defaults match IMK runtime defaults.
- Delegate draft validation, save-plan construction, profile-scoped secret mutation, and transient connection-test configuration to `ProviderProfileEditingPolicy`.
- Test the current provider draft by asking the policy for a transient `ProviderConfiguration` and running `ProviderConnectionDiagnostic` without saving provider metadata.
- Stage profile updates before saving so a failed `ProviderProfileStore.saveProfiles` call does not publish unsaved profile state.

## Persistence Notes

Load failures block settings persistence until profiles can be loaded successfully. Save failures surface through `lastErrorMessage` and keep the published `profiles` array unchanged. If a secret write or delete fails after the staged metadata file is written, the previous metadata file is saved again before the failure is returned.

Connection tests use a non-blank draft API key only for the test request. Blank draft API keys reuse an existing saved secret only when the policy confirms the saved secret still belongs to the same provider kind and endpoint credential scope. Missing required keys fail before the diagnostic sends a provider request, and invalid draft fields refresh `validationErrors` before returning while preserving save-only errors such as the single-default-provider rule.

Connection status is scoped to the draft snapshot being tested. Editing draft fields or switching profiles resets stale connection status, and in-flight diagnostic results are ignored if the draft snapshot has changed before the request completes. Diagnostic failures are shown in `connectionStatus`, not in the persistent `lastErrorMessage` save/load slot. Diagnostic success also preserves existing persistence errors because it does not retry or repair failed profile saves.

When a saved profile is edited to another provider protocol, another remote endpoint, or a local endpoint, a blank draft API key does not reuse the saved remote secret for the connection test. This mirrors save behavior for remote-to-local optional-secret transitions and prevents old cloud keys from being sent to a different provider.

`ProviderProfilesViewModel` remains the `@MainActor` UI state owner. It should not grow new provider credential policy helpers; add those rules to `ProviderProfileEditingPolicy` and keep the ViewModel limited to selection, persistence sequencing, connection-test generation, and result publication.
