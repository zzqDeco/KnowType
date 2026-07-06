# ProviderProfilesView

## Responsibility

`ProviderProfilesView` presents the shared settings surface in a macOS-native
sidebar/detail layout. Settings copy defaults to Simplified Chinese through
`SettingsLocalization`; English resources remain for explicit English locale
queries and missing-key fallback. It covers input behavior, candidate display,
local lexicons, AI continuation/service configuration, privacy, and advanced
diagnostics.

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
- The default section is `Overview`: a user-facing control center for install,
  AI continuation, lexicon, and privacy status plus common actions.
- Provider internals, raw paths, debug commands, and install diagnostics should
  stay under AI advanced configuration or the Advanced troubleshooting page.
- Diagnostics includes dynamic read-only install status: app version/build,
  install source, Rime runtime files, AI provider summary, user-data file
  timestamps, backup count, latest backup, and rollback command.
- Diagnostics must not execute rollback or overwrite the running input-method
  bundle from inside the settings process.
- The AI page should lead with user-facing continuation controls, current
  service summary, and connection test. Provider technical identifiers remain
  available only in the advanced service configuration disclosure.
- The current service summary and top-level connection test use the saved
  default provider, matching the input runtime's active service. A profiles file
  with profiles but no explicit default is shown as no configured active service.
  Unsaved draft edits are tested from the advanced service configuration
  disclosure.
- The current-service picker persists the runtime default. The advanced edit
  selector loads a profile into the draft without switching the active provider.
- Settings directory shortcuts create the target logs/support/Rime folder before
  opening it, so fresh installs expose a usable troubleshooting path.
- User-facing settings copy defaults to Simplified Chinese. Technical terms such
  as API Key, URL, Rime, macOS, and InputMethodKit remain untranslated where that
  is the clearest mixed Chinese copy.

## Tests

- `ProviderProfilesViewModelTests`
- `ProviderProfilesPresentationTests`
- Manual settings UI check when layout changes
