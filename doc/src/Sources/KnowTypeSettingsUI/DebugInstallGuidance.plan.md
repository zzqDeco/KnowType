# DebugInstallGuidance

## Responsibility

`DebugInstallGuidance` defines the user-facing install, diagnose, selection, and
log command guidance shown in settings.

## Boundaries

- It documents local development commands; it does not execute them.
- Script behavior stays in `scripts/`.

## Behavior Notes

- Guidance should match the current script names and safe defaults.
- Release examples use `X.Y.Z` and `N` placeholders instead of embedding an old
  product version that can drift from the current bundle.
- The default install command installs the input-method app only; `--with-prefpane`
  is documented as the compatibility PreferencePane path.
- Settings should direct users to the localized input-method menu settings
  entry, which defaults to `KnowType 设置...`.
- Mutating selection/install actions should be clearly separated from read-only
  diagnostics.
- macOS policy caveats belong here only as concise user-facing guidance; deeper
  reasoning lives in `doc/local-inputmethod-testing.plan.md`.

## Tests

- `DebugInstallGuidanceTests`
