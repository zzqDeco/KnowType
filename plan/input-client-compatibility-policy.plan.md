# Input Client Compatibility Policy

## Summary

- Status: Active.
- Branch: `fix/input-client-compatibility-policy`.
- Goal: prevent ordinary typing from being swallowed in host apps that do not
  reliably accept inline IMK marked text.

## Scope

- Add host compatibility write modes for inline composition, commit-only
  composition, ASCII passthrough, and missing-client disabled handling.
- Keep standard AppKit hosts on inline composition.
- Default terminal-style hosts to idle ASCII passthrough.
- Default editor, Codex, common Electron, and JetBrains-style hosts to Chinese
  commit-only composition so candidates can appear without inline marked text.
- Persist `InputTextMode` alongside punctuation and symbol-width defaults.
- Add a session-local `Option + /` text-mode toggle so compatibility hosts can
  switch between Chinese composition and idle ASCII passthrough without a
  settings UI.
- Update input-method tests, README behavior notes, source notes, and current
  architecture/interface docs.
- Do not change Rime schemas, AI provider behavior, candidate ranking,
  input-source registration, install scripts, or per-host policy settings UI.

## Implementation

- `InputClientCompatibilityPolicy` maps bundle id, input mode state, active
  composition, and client availability to `InputClientWriteMode`.
- `InputModePreferences.standard.codeAppState` defaults to ASCII text mode,
  Chinese punctuation, and half-width symbols. App policy applies that text mode
  only to terminal-style hosts; editor/Codex/Electron compatibility hosts keep
  the normal text-mode default while still using code-app punctuation and symbol
  width.
- Idle printable ASCII returns `false` in passthrough or disabled modes so the
  host app owns normal typing.
- Once composition is active, `Space`, numeric candidate selection, and commit
  actions stay handled by KnowType.
- Focused bundle changes bypass the normal preference reload throttle, while
  unchanged preferences and app context keep session-local toggles intact.
- `InputClientWriteCoordinator` owns `setMarkedText`, `insertText`, the
  `{NSNotFound, NSNotFound}` replacement-range policy, and
  `KNOWTYPE_CLIENT_WRITE_DEBUG=1` diagnostics.
- `KnowTypeInputController` falls back to `currentInputControllerClient` when
  an IMK callback sender cannot be adapted.

## Test Plan

- `swift test --quiet --filter InputClientCompatibilityPolicyTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputSymbolModeTests`
- `swift test`
- `git diff --check`
- Manual host acceptance should cover TextEdit, Terminal/iTerm, VS Code,
  Codex/Electron, and Xcode before the PR is marked ready.

## Assumptions

- The first slice has no settings UI for per-host policy, only UserDefaults
  override keys.
- Compatibility policy is conservative: if no client exists and no composition
  is active, printable input should pass through rather than be consumed.
- Manual host acceptance can be reported separately if this branch is reviewed
  before installed-app smoke testing.
