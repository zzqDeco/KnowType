# Input Client Compatibility Policy

## Summary

- Status: Absorbed by
  [input-method-decouple-host-carrier.plan.md](input-method-decouple-host-carrier.plan.md).
- Branch: `fix/input-client-compatibility-policy`.
- Goal: prevent ordinary typing from being swallowed in host apps that do not
  reliably accept inline IMK marked text.

## Scope

- Add host compatibility write modes for inline composition, commit-only
  composition, ASCII passthrough, and missing-client disabled handling.
- Keep standard AppKit hosts on inline composition.
- Default terminal-style hosts to idle ASCII passthrough.
- Initial versions defaulted editor/Electron/JetBrains-style hosts to Chinese
  commit-only composition; this has been superseded by the decoupled
  host-carrier policy, where inline-compatible hosts do not receive app-specific
  carrier branches unless a UserDefaults override says otherwise.
- Legacy versions persisted `InputTextMode` alongside punctuation and
  symbol-width defaults; current runtime mode is process-global and starts in
  linked Chinese mode.
- `Option + /` switches the process-global text mode so every compatibility
  host observes the same Chinese or ASCII state.
- Update input-method tests, README behavior notes, source notes, and current
  architecture/interface docs.
- Do not change Rime schemas, AI provider behavior, candidate ranking,
  input-source registration, install scripts, or per-host policy settings UI.

## Implementation

- `InputClientCompatibilityPolicy` maps bundle id, input mode state, active
  composition, and client availability to `InputClientWriteMode`.
- The earlier default/code-app mode split is retired. Current host compatibility
  selects only the marked-text carrier; process-global mode is independent of
  bundle identity.
- Idle half-width printable ASCII returns `false` in passthrough or disabled
  modes so the host app owns normal typing. Full-width printable ASCII is
  transformed and inserted by KnowType before this policy runs.
- Once composition is active, `Space`, numeric candidate selection, and commit
  actions stay handled by KnowType.
- Focused bundle changes do not reload text or punctuation mode; process-global
  generation is the runtime synchronization boundary.
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
- Manual host acceptance for the superseding policy should cover standard inline
  hosts, Terminal/iTerm placeholder behavior, and any override host before the
  PR is marked ready.

## Assumptions

- The first slice has no settings UI for per-host policy, only UserDefaults
  override keys.
- Compatibility policy is conservative: if no client exists and no composition
  is active, printable input should pass through rather than be consumed.
- Manual host acceptance can be reported separately if this branch is reviewed
  before installed-app smoke testing.
