# Input Source Support Shared Cleanup

Status: Active

## Summary

Share the duplicated Text Input Source and LaunchServices support logic used by `KnowTypeInputMethodApp` and `knowtype-inputsource-tool` through `KnowTypeInputSourceSupport`.

This is a pure refactor. It does not change install script flow, TIS registration, enablement, selection, preference repair semantics, plist content, or local machine input-source state.

## Scope

- Move reusable LaunchServices helpers into `KnowTypeInputSourceSupport`:
  - suffix stripping for `lsregister -dump` rows
  - home path expansion
  - canonical bundle path resolution
  - `lsregister -dump` path parsing
  - stale LaunchServices unregister flow with injected runner and warning sink
- Move reusable TIS helpers into `KnowTypeInputSourceSupport`:
  - source lookup by input-source id and bundle id
  - current input-source id lookup
  - source property reads
  - source signatures, dedupe, activation and selection target ordering
  - parent-before-mode enable ordering and mode-before-parent disable ordering
  - distributed TIS notification posting
  - bounded wait helpers
- Keep `KnowTypeInputMethodApp` focused on installed-app command sequencing and `IMKServer` startup.
- Keep `KnowTypeInputSourceTool` focused on CLI argument parsing, key/value output compatibility, scoped preference repair, and command exit behavior.

## Non-Goals

- Do not run or change install, repair, rollback, uninstall, or smoke scripts.
- Do not change TIS registration, enablement, selection, or preference repair behavior.
- Do not change input method composition, Rime, candidate panel, AI, provider, or Settings UI logic.
- Do not add new user-facing install flows.

## Validation

- Build both entry points:
  - `swift build --product KnowTypeInputMethodApp`
  - `swift build --product knowtype-inputsource-tool`
- Add `KnowTypeInputSourceSupportTests` for pure LaunchServices parsing, path normalization, unregister runner injection, signatures, ordering, and visible mode counting.
- Keep `InputMethodBundleInfoTests` guarding command/output behavior while allowing the shared support boundary.
- Run:
  - `swift test --quiet --filter KnowTypeInputSourceSupportTests`
  - `swift test --quiet --filter InputMethodBundleInfoTests`
  - `swift test`
  - `git diff --check`
