# Install Selection Status

## Goal

Make the local input-method install script stop implying KnowType is globally selected when `TISSelectInputSource` only reports success in the installer process. The read-only diagnostic script remains the source of truth for system input-source status.

## Behavior

- After registration and enabling, `scripts/install-inputmethod.sh` requests selection of `com.knowtype.inputmethod.KnowType.Mode`.
- If the installer process observes that mode as current, the script reports the selection request rather than claiming global system selection.
- If the installer process still observes another input source, the script prints a warning with that input source ID and points the developer to System Settings.
- The final script output directs developers to `scripts/diagnose-inputmethod.sh` as the read-only system status check.

## Verification

```bash
bash -n scripts/install-inputmethod.sh
./scripts/install-inputmethod.sh
./scripts/diagnose-inputmethod.sh --strict
git diff --check
```
