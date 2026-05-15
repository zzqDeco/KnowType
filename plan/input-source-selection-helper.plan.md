# Input Source Selection Helper

## Goal

Keep local installation, input-source selection, and diagnostics as separate developer actions. The install script can request selection after copying the bundle, but a standalone helper makes it possible to retry selection without rebuilding or reinstalling KnowType.

## Behavior

- `scripts/select-inputmethod.sh` locates `com.knowtype.inputmethod.KnowType.Mode`, enables the parent and mode input sources when present, and calls `TISSelectInputSource`.
- The helper reports that macOS selection was requested rather than claiming a global switch.
- By default the helper runs `scripts/diagnose-inputmethod.sh --strict` after the request so the read-only diagnostic remains the source of truth for installed state.
- `--require-selected` verifies KnowType selection inside the same TIS process that requested selection. A later shell diagnostic can observe a different app context, and even this helper remains only a selection preflight, so final acceptance must type a real probe in the target app.
- `--no-diagnose` is available when a developer only wants to send the selection request.
- `scripts/diagnose-inputmethod.sh --require-selected` remains available for checking the diagnostic process's own current TIS context, not for proving another app's final typing state.

## Verification

```bash
bash -n scripts/diagnose-inputmethod.sh scripts/select-inputmethod.sh
./scripts/select-inputmethod.sh
swift test
git diff --check
```
