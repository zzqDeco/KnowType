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
- Route provider-field sidebar search terms such as `Base URL` and
  `Custom HTTP` to the AI Continuation page, where the advanced service
  configuration controls actually live.
- Treat the provider marked `isDefault` as the active AI service shown on
  Overview and tested from the top-level AI service section. The selected
  profile/draft remains the advanced editing target, with draft connection
  tests kept next to the advanced editor.
- Do not fall back to the first saved profile when no profile is marked
  `isDefault`; the input runtime also treats that state as no active provider.
- Keep current-service selection separate from advanced profile editing:
  changing the current service persists the default provider, while the advanced
  edit selector only loads a draft. When the current service changes, the
  advanced draft's default flag is reconciled to the newly active provider
  without discarding unsaved draft edits.
- Validate a saved profile before making it current. Remote provider templates
  without an available Keychain secret are rejected before canonical provider
  metadata is rewritten as the runtime default.
- Reject unconfigured Custom HTTP example endpoints before they can become the
  current service, and clear missing optional secret references from local
  OpenAI-compatible or Custom HTTP profiles before canonical provider metadata
  is rewritten as the runtime default.
- Keep saved-service and draft-editor connection status separate. The top-level
  connection test reports only the saved default provider, while draft
  validation/test results stay inside the advanced service configuration area.
  Saved-service connection tests reuse the same current-service guard, so they
  do not send diagnostics traffic to placeholder endpoints and repair missing
  optional secret references before reporting success.
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
