# ProviderProfilesViewModel

`ProviderProfilesViewModel` is the settings-app state owner for provider profile editing.

## Responsibilities

- Load provider profiles from `ProviderProfileStore`, seeding default profiles when the store is empty.
- Use `KnowTypeProviders.ProviderProfileTemplates` so settings defaults match IMK runtime defaults.
- Keep cloud-provider secrets out of JSON by using profile-scoped `SecretStore` names, while leaving unauthenticated custom HTTP profiles without a `secretName`.
- Validate drafts before persistence, including host-bearing HTTP(S) base URLs, remote OpenAI-compatible real model IDs instead of discovery placeholders, and custom HTTP template fields.
- Test the current provider draft by building a transient `ProviderConfiguration` and running `ProviderConnectionDiagnostic` without saving provider metadata.
- Require new or existing cloud-provider API keys before saving profiles that need secrets.
- Save a profile-scoped custom HTTP secret only when the draft contains a non-blank API key.
- Keep local/no-secret provider switches explicit by clearing the draft API key and deleting stale non-local profile secrets during save only when no other saved profile still references them. Existing local OpenAI-compatible profiles keep their optional key when the draft API key is left blank only if the referenced secret still resolves.
- Stage profile updates before saving so a failed `ProviderProfileStore.saveProfiles` call does not publish unsaved profile state.

## Persistence Notes

Load failures block settings persistence until profiles can be loaded successfully. Save failures surface through `lastErrorMessage` and keep the published `profiles` array unchanged. If a secret write or delete fails after the staged metadata file is written, the previous metadata file is saved again before the failure is returned.

Connection tests use a non-blank draft API key only for the test request. Blank draft API keys reuse an existing saved secret when one is available. Missing required keys fail before the diagnostic sends a provider request.

Connection status is scoped to the draft snapshot being tested. Editing draft fields or switching profiles resets stale connection status, and in-flight diagnostic results are ignored if the draft snapshot has changed before the request completes. Diagnostic failures are shown in `connectionStatus`, not in the persistent `lastErrorMessage` save/load slot.
