# Input Debug Diagnostics Consolidation

## Status

Active

## Summary

Consolidate KnowType input-method debug and performance diagnostics behind
`InputDebugDiagnostics`, while keeping debug output opt-in and privacy-safe.

This plan covers the README/debug documentation closeout plus key-path
instrumentation for first-key stalls, AI latency, candidate-panel frame replay,
host writes, anchor selection, Rime processing, and input-turn sequencing.

## Implementation

- Add `KNOWTYPE_PERF_DEBUG=1` as the umbrella performance debug switch.
- Keep existing focused switches compatible:
  `KNOWTYPE_STARTUP_DEBUG`, `KNOWTYPE_INPUT_LATENCY_DEBUG`,
  `KNOWTYPE_AI_DEBUG`, `KNOWTYPE_PANEL_DEBUG`, `KNOWTYPE_TURN_DEBUG`,
  `KNOWTYPE_CLIENT_WRITE_DEBUG`, and `KNOWTYPE_ANCHOR_DEBUG`.
- Route key debug output through one privacy-safe key/value formatter with
  stderr mirroring and unified logging.
- Add timing metadata for `handle_key_total`, `commit_decision`,
  `turn_effect.<name>`, `refresh_composition`, `publish_local_suggestion`,
  native Rime process calls, candidate-panel frame publication/window apply,
  and AI debounce/transport stages.
- Preserve input behavior, AI prompts, provider configuration, Rime schema,
  host compatibility, candidate ranking, Settings UI, and install scripts.

## Validation

- `InputDebugDiagnosticsTests` cover environment switches, latency budget
  behavior, key/value formatting, and privacy-safe output assumptions.
- Existing input-method tests verify instrumentation does not change
  handled/pass-through/commit behavior.
- Source guards in `InputHotPathPerformanceTests` prevent reintroducing direct
  fputs-style logging in the critical diagnostics files.

## Non-Goals

- No new logging framework.
- No user-visible settings UI.
- No behavior change in the input hot path.
- No attempt to rewrite every historical diagnostic line outside the current
  input-method key path.
