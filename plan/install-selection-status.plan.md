# Install Selection Status

## Goal

Make the local input-method install script stop implying KnowType is globally selected when `TISSelectInputSource` only reports success in the installer process. The read-only diagnostic script remains the source of truth for system input-source status.

## Behavior

- `scripts/install-inputmethod.sh` copies the signed bundle into `~/Library/Input Methods`, runs `lsregister -f`, then executes `KnowTypeInputMethodApp --knowtype-purge-legacy` and `KnowTypeInputMethodApp --knowtype-install-activate` so the installed app purges stale `.Mode` development state and activates the visible `.Hans` input mode before starting `IMKServer`.
- The installed app registers the missing parent/mode pair, enables the active mode from its own signed bundle context when needed, and logs the app-local `TISSelectInputSource` result. This follows the component-mode shape used by Squirrel, McBopomofo, and macSKK.
- The repair path mirrors System Settings on this macOS build: HIToolbox enabled/history rows point at `.Hans`, while `com.apple.inputsources` keeps the third-party parent anchor plus `.Hans`. Diagnostics still read the protected lists so stale `.Mode` rows and missing anchors are visible.
- The command-line helper remains available for status, dump, compatibility bootstrap, debug legacy purge, and scoped preference repair, but install and selection paths no longer use helper-side TIS mutation requests.
- If app-local `TISSelectInputSource` returns `noErr`, that still proves only the app context; diagnostics remain the source of truth for persisted system selected input source.
- Diagnostics report both helper-local TIS state and persisted HIToolbox preferences; `AppleSelectedInputSources` can still point at another input source even when TIS reports KnowType as enabled.
- The final script output directs developers to `scripts/diagnose-inputmethod.sh --strict` as the read-only install status check.
- The final script output also tells developers to activate the target text app, run `scripts/select-inputmethod.sh --require-selected` as a preflight, then type a real probe for manual typing acceptance.
- The diagnostic reports the localized input-source name so developers can distinguish a packaging/display-name issue from a missing registration issue.
- The diagnostic can include unified-log hints for Gatekeeper and input-source sandbox denials with `--logs`.

## Verification

```bash
bash -n scripts/install-inputmethod.sh
./scripts/install-inputmethod.sh
./scripts/diagnose-inputmethod.sh --strict --logs
git diff --check
```

Before manual typing acceptance, activate the target text app, run `./scripts/select-inputmethod.sh --require-selected` as a preflight, then type a real probe in that app. Treat preflight failure as "macOS has not switched KnowType into that active TIS context yet" rather than as an install-script failure.

If the input menu does not visibly show `KnowType` / `知键`, inspect the diagnostic's localized-name and third-party preference lines. A raw `com.knowtype.inputmethod.KnowType` name indicates missing or stale `InfoPlist.strings`; stale `.Mode` registrations or missing third-party parent anchors should be fixed by removing/re-adding KnowType in System Settings and may still require logout or reboot.
