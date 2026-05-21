# ProviderProfilesView

## Responsibility

`ProviderProfilesView` presents the shared settings surface in a Simplified
Chinese macOS-native sidebar/detail layout. It covers input behavior, candidate
display, Rime/user data, AI continuation/provider profiles, privacy, and
diagnostics.

## Boundaries

- Validation and persistence behavior belong to `ProviderProfilesViewModel`.
- Provider adapter behavior belongs to `KnowTypeProviders`.

## Behavior Notes

- Draft API keys used for connection tests are transient unless the user saves.
- The view should not display or persist raw stored Keychain values.
- UI copy should distinguish local OpenAI-compatible endpoints from remote
  provider profiles.
- The top-level layout is a `NavigationSplitView` with searchable sidebar
  sections. Detail pages use grouped forms and native SwiftUI controls.
- The AI provider page is a single grouped form rather than a nested split view;
  provider technical identifiers remain in English.
- User-facing settings copy is Simplified Chinese. Technical terms such as API
  Key, URL, Rime, macOS, and InputMethodKit remain untranslated.

## Tests

- `ProviderProfilesViewModelTests`
- `ProviderProfilesPresentationTests`
- Manual settings UI check when layout changes
