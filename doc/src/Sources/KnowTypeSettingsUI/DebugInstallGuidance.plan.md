# DebugInstallGuidance

## Responsibility

`DebugInstallGuidance` defines the user-facing install, diagnose, selection, and
log command guidance shown in settings.

## Boundaries

- It documents local development commands; it does not execute them.
- Script behavior stays in `scripts/`.

## Behavior Notes

- Guidance should match the current script names and safe defaults.
- Mutating selection/install actions should be clearly separated from read-only
  diagnostics.
- macOS policy caveats belong here only as concise user-facing guidance; deeper
  reasoning lives in `doc/local-inputmethod-testing.plan.md`.

## Tests

- `DebugInstallGuidanceTests`
