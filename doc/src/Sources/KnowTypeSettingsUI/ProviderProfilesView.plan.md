# ProviderProfilesView

## Responsibility

`ProviderProfilesView` presents the shared settings surface in a macOS-native
sidebar/detail layout. Settings copy defaults to Simplified Chinese through
`SettingsLocalization`; English resources remain for explicit English locale
queries and missing-key fallback. It covers input behavior, candidate display,
Rime/user data, AI continuation/provider profiles, privacy, and diagnostics.

## Boundaries

- UI state and persistence sequencing belong to `ProviderProfilesViewModel`.
- Draft validation, credential reuse, save-plan, and connection-test
  configuration rules belong to `ProviderProfileEditingPolicy`.
- Provider adapter behavior belongs to `KnowTypeProviders`.

## Behavior Notes

- Draft API keys used for connection tests are transient unless the user saves.
- The view should not display or persist raw stored Keychain values.
- UI copy should distinguish local OpenAI-compatible endpoints from remote
  provider profiles.
- The top-level layout is a `NavigationSplitView` with searchable sidebar
  sections. Detail pages use grouped forms and native SwiftUI controls.
- Diagnostics includes dynamic read-only install status: app version/build,
  install source, Rime runtime files, AI provider summary, user-data file
  timestamps, backup count, latest backup, and rollback command.
- Diagnostics must not execute rollback or overwrite the running input-method
  bundle from inside the settings process.
- The AI provider page is a single grouped form rather than a nested split view;
  provider technical identifiers remain in English.
- User-facing settings copy defaults to Simplified Chinese. Technical terms such
  as API Key, URL, Rime, macOS, and InputMethodKit remain untranslated where that
  is the clearest mixed Chinese copy.

## Tests

- `ProviderProfilesViewModelTests`
- `ProviderProfilesPresentationTests`
- Manual settings UI check when layout changes
