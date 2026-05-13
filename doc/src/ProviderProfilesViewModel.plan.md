# ProviderProfilesViewModel

`ProviderProfilesViewModel` is the settings-app state owner for provider profile editing.

## Responsibilities

- Load provider profiles from `ProviderProfileStore`, seeding default profiles when the store is empty.
- Keep cloud-provider secrets out of JSON by using profile-scoped `SecretStore` names.
- Validate drafts before persistence, including host-bearing HTTP(S) base URLs and custom HTTP template fields.
- Keep local/no-secret provider switches explicit by clearing the draft API key and deleting the old profile secret during save.
- Stage profile updates before saving so a failed `ProviderProfileStore.saveProfiles` call does not publish unsaved profile state.

## Persistence Notes

Load failures block settings persistence until profiles can be loaded successfully. Save failures surface through `lastErrorMessage` and keep the published `profiles` array unchanged.
