# ProviderProfilesViewModel

`ProviderProfilesViewModel` is the settings-app state owner for provider profile editing.

## Responsibilities

- Load provider profiles from `ProviderProfileStore`, seeding default profiles when the store is empty.
- Keep cloud-provider secrets out of JSON by using profile-scoped `SecretStore` names, while leaving unauthenticated custom HTTP profiles without a `secretName`.
- Validate drafts before persistence, including host-bearing HTTP(S) base URLs, remote OpenAI-compatible model IDs, and custom HTTP template fields.
- Require new or existing cloud-provider API keys before saving profiles that need secrets.
- Save a profile-scoped custom HTTP secret only when the draft contains a non-blank API key.
- Keep local/no-secret provider switches explicit by clearing the draft API key and deleting the old profile secret during save only when no other saved profile still references it. Local OpenAI-compatible profiles with blank API keys also clear stale secret references.
- Stage profile updates before saving so a failed `ProviderProfileStore.saveProfiles` call does not publish unsaved profile state.

## Persistence Notes

Load failures block settings persistence until profiles can be loaded successfully. Save failures surface through `lastErrorMessage` and keep the published `profiles` array unchanged. If a secret write or delete fails after the staged metadata file is written, the previous metadata file is saved again before the failure is returned.
