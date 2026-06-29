# Input Client Host Profile Preedit

## Delivered Behavior

- Status: Delivered.
- Branch: `fix/input-client-host-profile-preedit`.
- Host compatibility now has an explicit bundle-id `HostCompatibilityProfile`
  table for the carrier layer only: inline marked text, placeholder marked text,
  and terminal-style idle ASCII defaults.
- Commit-only hosts still receive only an attributed full-width-space
  placeholder in the host text field, but the real raw/preedit display string is
  rendered as a non-selectable preedit row above KnowType candidate rows.
- Fixed preedit rows have no shortcut, no selection identity, and do not consume
  candidate paging slots. With the current single-orientation AppKit layout
  engine, preedit rows force vertical layout so they appear above candidates.
- `KNOWTYPE_STARTUP_DEBUG=1` now records lightweight timings for controller
  init, first composition begin, first Rime session creation, and first
  candidate-panel materialization without logging user text.

## Verification

- `swift test --quiet --filter HostCompatibilityProfileTests`
- `swift test --quiet --filter InputClientCompatibilityPolicyTests`
- `swift test --quiet --filter CandidatePanelRendererTests`
- `swift test --quiet --filter CandidatePanelStateTests`
- `swift test --quiet --filter CandidatePanelLayoutEngineTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`

## Docs Absorbed By

- [Architecture](../doc/architecture.plan.md)
- [Interfaces](../doc/interfaces.plan.md)
- [Input method source notes](../doc/src/Sources/KnowTypeInputMethod/README.plan.md)
- [HostCompatibilityProfile source note](../doc/src/Sources/KnowTypeInputMethod/HostCompatibilityProfile.plan.md)

## Retirement Criteria

Retire this plan after the host-profile and preedit-row behavior has shipped in
an installed release and manual host acceptance is recorded for a browser/editor
inline host and at least one terminal-style host. Non-terminal default carrier
and preedit-row handling is superseded by `input-method-decouple-host-carrier`.
