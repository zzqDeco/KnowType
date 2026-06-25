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
- Default terminal, code editor, Codex, common Electron, and JetBrains-style
  hosts to idle ASCII passthrough and Chinese commit-only composition.
- Persist `InputTextMode` alongside punctuation and symbol-width defaults.
- Update input-method tests, README behavior notes, source notes, and current
  architecture/interface docs.
- Do not change Rime schemas, AI provider behavior, candidate ranking,
  input-source registration, install scripts, or settings UI.

## Implementation

- `InputClientCompatibilityPolicy` maps bundle id, input mode state, active
  composition, and client availability to `InputClientWriteMode`.
- `InputModePreferences.standard.codeAppState` defaults to ASCII text mode,
  Chinese punctuation, and half-width symbols; saved preferences can still
  override the state.
- Idle printable ASCII returns `false` in passthrough or disabled modes so the
  host app owns normal typing.
- Once composition is active, `Space`, numeric candidate selection, and commit
  actions stay handled by KnowType.
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
