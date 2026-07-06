# Settings User-Facing Control Center

## Summary

- Redesign the shared Settings UI from a provider/diagnostics-first surface into
  a user-facing control center for a Chinese input method.
- Keep advanced provider, path, log, and diagnostic controls available, but move
  them behind advanced configuration and troubleshooting sections.

## Scope

- Change `KnowTypeSettingsUI` sidebar information architecture to Overview, AI
  Continuation, Input Experience, Candidate Panel, Lexicons, Privacy, and
  Advanced.
- Add an Overview page that summarizes install, AI, lexicon, and privacy state
  from existing local view models and diagnostics snapshots.
- Reorganize existing Settings pages only; do not change provider JSON schema,
  Keychain behavior, AI prompts, Rime schema, input-method runtime behavior, or
  install scripts.

## Implementation

- Keep `ProviderProfilesView` as the shared SwiftUI entry point for the
  standalone settings app, PreferencePane host, and IMK preferences window.
- Add testable overview/sidebar presentation state so default section order,
  Chinese copy, and non-debug overview text are covered by unit tests.
- Use native SwiftUI `NavigationSplitView`, grouped `Form`, `Section`, and
  `DisclosureGroup`; avoid dashboard-style diagnostics as the default view.
- Put provider editor fields, `Base URL`, `Custom HTTP`, API key, lexicon paths,
  local data paths, and diagnostic commands in advanced disclosures or the
  Advanced page.
- Treat the provider marked `isDefault` as the active AI service shown on
  Overview and tested from the top-level AI service section. The selected
  profile/draft remains the advanced editing target, with draft connection
  tests kept next to the advanced editor.
- Do not fall back to the first saved profile when no profile is marked
  `isDefault`; the input runtime also treats that state as no active provider.
- Keep current-service selection separate from advanced profile editing:
  changing the current service persists the default provider, while the advanced
  edit selector only loads a draft.
- Create local logs/support/Rime directories before opening Settings shortcut
  buttons so fresh installs do not silently no-op.
- Keep Settings copy Chinese by default while preserving explicit English
  localization resources and missing-key fallback.

## Test Plan

- `swift test --quiet --filter ProviderProfilesPresentationTests`
- `swift test --quiet --filter ProviderProfilesViewModelTests`
- `swift test --quiet --filter ProviderProfileEditingPolicyTests`
- `swift test --quiet --filter LexiconSettingsPresentationTests`
- `swift test --quiet --filter LexiconSettingsViewModelTests`
- `swift test`
- `git diff --check`

## Assumptions

- The Advanced sidebar item remains visible by default so proxy/provider and
  local diagnostics stay discoverable.
- Opening Settings does not run network connection tests or mutate install
  state; connection tests remain explicit user actions.
- This slice is a Settings UX and copy change, not an input-method behavior
  change.
