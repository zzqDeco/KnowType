# Native IMK Settings Menu

## Summary

- Align KnowType's settings experience with mature macOS IMK input methods such
  as McBopomofo: settings live behind the input-method menu, not a standalone
  settings app.
- Keep `KnowType.prefPane` as a compatibility fallback, but make local install
  default to `KnowType.app` plus the in-bundle preferences window.

## Scope

- Update the input-method menu, preferences window chrome, install/smoke script
  defaults, and user-facing docs.
- Do not change input-source registration, Rime conversion, candidate panel
  behavior, appex packaging, or the main/release branch flow.

## Implementation

- Add a testable `InputMethodMenuBuilder` that produces the native menu order:
  `AI Continuation`, data/diagnostic folders, `KnowType Settings...`, and About.
- Keep `KnowType Settings...` bound to `showPreferences:` and use the existing
  `KnowTypePreferencesWindowController` as the in-bundle settings host.
- Persist menu toggles through `InputMethodRuntimePreferenceStore`, then force
  the coordinator to reload runtime preferences for that external change.
- Make `scripts/install-inputmethod.sh` install the compatibility
  `KnowType.prefPane` only with `--with-prefpane`; keep release packaging of the
  pane as a fallback artifact and do not add a standalone settings app.

## Test Plan

- `swift test`
- `./scripts/smoke-inputmethod-install.sh`
- `./scripts/perf-input-hotpath.sh`
- `git diff --check`
- Manual: install release build, open `KnowType Settings...` from the input menu,
  toggle AI continuation, open log/support/Rime folders, and verify typing
  behavior has no performance regression.

## Assumptions

- The standalone settings app target remains only a developer preview host.
- The compatibility PreferencePane remains buildable and packageable, but it is
  no longer the default local settings path.
