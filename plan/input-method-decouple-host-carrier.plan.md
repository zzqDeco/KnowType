# Input Method Host Carrier Decoupling

## Delivered Behavior

- Status: Delivered.
- Branch: `fix/input-method-decouple-host-carrier`.
- `HostCompatibilityProfile` now owns only the host marked-text carrier table.
  Code-app input defaults stay in `InputModeAppPolicy`.
- Browsers, editors, IDEs, Electron/ToDesktop shells, JetBrains-style hosts, and
  other inline-compatible clients default to inline composition, so raw preedit
  is visible in the focused text field instead of only as a candidate-panel
  preedit row.
- Any Codex-specific carrier or candidate-panel preedit display branch has been
  removed; Codex can remain a code-app preference entry without affecting host
  carrier selection.
- Terminal, iTerm, MacVim, and Emacs-style hosts keep idle ASCII passthrough via
  their input-mode default and use placeholder carrier during Chinese
  composition.
- Inline preedit and placeholder carrier writes both use attributed marked text
  with TSM marked-text attributes.
- UserDefaults `input.client.<bundle id>.writeMode` overrides still take
  precedence and can force `commitOnlyComposition` for hosts that prove
  incompatible with inline marked text.

## Verification

- `swift test --quiet --filter HostCompatibilityProfileTests`
- `swift test --quiet --filter InputClientCompatibilityPolicyTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`

## Docs Absorbed By

- [Architecture](../doc/architecture.plan.md)
- [Interfaces](../doc/interfaces.plan.md)
- [Input method source notes](../doc/src/Sources/KnowTypeInputMethod/README.plan.md)
- [HostCompatibilityProfile source note](../doc/src/Sources/KnowTypeInputMethod/HostCompatibilityProfile.plan.md)
- [InputClientCompatibilityPolicy source note](../doc/src/Sources/KnowTypeInputMethod/InputClientCompatibilityPolicy.plan.md)
- [InputControllerHostClientSeams source note](../doc/src/Sources/KnowTypeInputMethod/InputControllerHostClientSeams.plan.md)

## Retirement Criteria

Retire this plan after the decoupled carrier behavior has shipped in an
installed release and manual host acceptance is recorded for Codex inline,
Chrome/TextEdit inline, and at least one terminal-style placeholder host.
