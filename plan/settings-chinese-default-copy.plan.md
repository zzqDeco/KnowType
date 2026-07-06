# Settings Chinese Default Copy

## Summary

Make the KnowType settings surface and input-method settings menu use
Simplified Chinese as the default user-facing copy. English resources remain
available for explicit English locale queries and missing-key fallback.

## Scope

- Change `SettingsLocalization` default lookup so normal UI calls check
  `zh-Hans` before system preferred languages.
- Keep explicit `localeIdentifier: "en"` and region-specific English identifiers
  on the English resource path.
- Move remaining Settings and input-method menu hard-coded user-facing copy into
  `Localizable.strings`.
- Localize Settings-generated validation, connection, rollback, and lexicon
  action messages by default.

## Out Of Scope

- Provider prompts, provider/model configuration, Keychain behavior, profile JSON
  schema, input-source registration, Rime candidates, and candidate-panel visual
  behavior.
- Translating provider/system error text or provider output.

## Test Plan

- `swift test --quiet --filter ProviderProfilesPresentationTests`
- `swift test --quiet --filter ProviderProfilesViewModelTests`
- `swift test --quiet --filter ProviderProfileEditingPolicyTests`
- `swift test --quiet --filter LexiconSettingsPresentationTests`
- `swift test --quiet --filter LexiconSettingsViewModelTests`
- `swift test --quiet --filter InputMethodMenuBuilderTests`
- `swift test`
- `git diff --check`

## Status

Active.
