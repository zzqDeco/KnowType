# Install Selection Status

## Goal

Make the local input-method install script stop implying KnowType is globally selected when `TISSelectInputSource` only reports success in the installer process. The read-only diagnostic script remains the source of truth for system input-source status.

## Behavior

- After registration and enabling, `scripts/install-inputmethod.sh` requests selection of `com.knowtype.inputmethod.KnowType.Mode`.
- If `TISSelectInputSource` returns `noErr`, the script reports that the selection request was made rather than claiming global system selection.
- If `TISSelectInputSource` returns an error, the script prints the status and points the developer to System Settings.
- The script does not read the current input source inside the same short-lived Swift process, because that value can be stale until keyboard-selection notifications are processed.
- The final script output directs developers to `scripts/diagnose-inputmethod.sh` as the read-only system status check.

## Verification

```bash
bash -n scripts/install-inputmethod.sh
./scripts/install-inputmethod.sh
./scripts/diagnose-inputmethod.sh --strict
git diff --check
```
