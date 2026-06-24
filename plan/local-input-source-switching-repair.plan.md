# Local Input Source Switching Repair

## Summary

Local Apple Development builds can be registered and enabled while still refusing to become the active macOS input source. The observed failure mode is a split state: `TISSelectInputSource` succeeds in the helper or app process, but `com.apple.HIToolbox` returns to Apple Pinyin when the active text client refreshes.

The fix keeps the installed bundle shape closer to mature IMK frontends and adds a repair path for stale local development state:

- `KnowType.app` is an `LSUIElement` agent app instead of a pure `LSBackgroundOnly` app, matching Squirrel and vChewing-style IMK frontends.
- The visible `.Hans` input mode declares Chinese script repertoires with script codes such as `Hans`, `Hant`, `Hani`, `Hanb`, and `Han`, plus a compact menu label.
- The visible input mode does not advertise `Latn`; otherwise TIS can classify the third-party Chinese input source as ASCII-capable and skip it in normal input-source cycling.
- The input-method app deduplicates TIS sources before issuing enable requests, so repeated local launches do not amplify duplicated records.
- `scripts/repair-inputmethod-selection.sh` uses the input-source helper to unregister stale LaunchServices records for old KnowType build paths and disable legacy TIS modes, then removes stale `.Mode` and parent-only preference rows, keeps enabled repair on parent plus `.Hans`, keeps history/selected repair on `.Hans`, and restarts Text Input menu agents.
- `scripts/diagnose-inputmethod.sh --strict` fails when LaunchServices still has stale KnowType bundle records outside the installed path.
- Install and settings guidance now calls out the macOS authorization prompt that asks whether to allow `知键` to enable `KnowType`; until that prompt is approved, macOS can keep falling back to another source even when registration and enablement checks pass.

## Validation

- `swift test`
- `git diff --check`
- `bash -n scripts/repair-inputmethod-selection.sh scripts/diagnose-inputmethod.sh scripts/smoke-inputmethod-install.sh`
- Local repair smoke:
  - `./scripts/install-inputmethod.sh`
  - `./scripts/repair-inputmethod-selection.sh`
  - `./scripts/diagnose-inputmethod.sh --strict --logs`

## Notes

The repair script is a local development tool. It does not claim CI can prove target-app selection, because macOS Text Input Source state is scoped to the interactive login session and the active text client.
