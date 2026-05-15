# Input Source Selection Helper

## Goal

Keep local installation, input-source selection, and diagnostics as separate developer actions. The install script can request selection after copying the bundle, but a standalone helper makes it possible to retry selection without rebuilding or reinstalling KnowType.

## Behavior

- `scripts/select-inputmethod.sh` locates `com.knowtype.inputmethod.KnowType.Mode`, enables the parent and mode input sources when present, and calls `TISSelectInputSource`.
- The helper reports that macOS selection was requested rather than claiming a global switch.
- By default the helper runs `scripts/diagnose-inputmethod.sh --strict` after the request so the read-only diagnostic remains the source of truth for installed state.
- `--require-selected` forwards a stricter gate to the diagnostic, causing the command to fail if KnowType is not the current input source after the request.
- `--no-diagnose` is available when a developer only wants to send the selection request.
- `scripts/diagnose-inputmethod.sh --require-selected` can also be used directly before manual typing acceptance.

## Verification

```bash
bash -n scripts/diagnose-inputmethod.sh scripts/select-inputmethod.sh
./scripts/select-inputmethod.sh
swift test
git diff --check
```
