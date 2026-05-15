# Install Selection Status

## Goal

Make the local input-method install script stop implying KnowType is globally selected when `TISSelectInputSource` only reports success in the installer process. The read-only diagnostic script remains the source of truth for system input-source status.

## Behavior

- `scripts/install-inputmethod.sh` copies the signed bundle into `~/Library/Input Methods` and launches `KnowType.app --knowtype-install-activate`.
- The installed app registers missing sources, enables existing sources from its own signed bundle context, and logs the app-local `TISSelectInputSource` result.
- The command-line helper remains available for status, dump, manual register, and manual selection retries, but the default install path no longer routes registration or selection through a sandboxed helper.
- If app-local `TISSelectInputSource` returns `noErr`, that still proves only the app context; diagnostics remain the source of truth for persisted system selected input source.
- Diagnostics report both helper-local TIS state and persisted HIToolbox preferences; `AppleEnabledInputSources` can contain KnowType while `AppleSelectedInputSources` still points at Apple Pinyin.
- The final script output directs developers to `scripts/diagnose-inputmethod.sh --strict` as the read-only install status check.
- The final script output also tells developers to activate the target text app, run `scripts/select-inputmethod.sh --require-selected` as a preflight, then type a real probe for manual typing acceptance.
- The diagnostic reports the localized input-mode name so developers can distinguish a packaging/display-name issue from a missing registration issue.
- The diagnostic can include unified-log hints for Gatekeeper and input-source sandbox denials with `--logs`.

## Verification

```bash
bash -n scripts/install-inputmethod.sh
./scripts/install-inputmethod.sh
./scripts/diagnose-inputmethod.sh --strict --logs
git diff --check
```

Before manual typing acceptance, activate the target text app, run `./scripts/select-inputmethod.sh --require-selected` as a preflight, then type a real probe in that app. Treat preflight failure as "macOS has not switched KnowType into that active TIS context yet" rather than as an install-script failure.

If the input menu does not visibly show `KnowType` / `知键`, inspect the diagnostic's localized-name line. A raw `com.knowtype.inputmethod.KnowType.Mode` name indicates missing or stale `InfoPlist.strings`; duplicate mode registrations usually require logout or reboot after reinstalling.
