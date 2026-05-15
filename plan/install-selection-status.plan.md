# Install Selection Status

## Goal

Make the local input-method install script stop implying KnowType is globally selected when `TISSelectInputSource` only reports success in the installer process. The read-only diagnostic script remains the source of truth for system input-source status.

## Behavior

- After registration and enabling, `scripts/install-inputmethod.sh` requests selection of `com.knowtype.inputmethod.KnowType.Mode`.
- TIS registration, enabling, selection, and status checks run through `knowtype-inputsource-tool`, not inline `swift -`, so local macOS permission prompts are attributable to the KnowType helper instead of `swift-frontend`.
- If `TISSelectInputSource` returns `noErr`, the script reports that the selection request was made rather than claiming global system selection.
- Diagnostics report both helper-local TIS state and persisted HIToolbox preferences; `AppleEnabledInputSources` can contain KnowType while `AppleSelectedInputSources` still points at Apple Pinyin.
- If `TISSelectInputSource` returns an error, the script prints the status and points the developer to System Settings.
- The script does not read the current input source inside the same short-lived Swift process, because that value can be stale until keyboard-selection notifications are processed.
- The final script output directs developers to `scripts/diagnose-inputmethod.sh --strict` as the read-only install status check.
- The final script output also tells developers to activate the target text app, run `scripts/select-inputmethod.sh --require-selected` as a preflight, then type a real probe for manual typing acceptance.
- The diagnostic reports the localized input-mode name so developers can distinguish a packaging/display-name issue from a missing registration issue.

## Verification

```bash
bash -n scripts/install-inputmethod.sh
./scripts/install-inputmethod.sh
./scripts/diagnose-inputmethod.sh --strict
git diff --check
```

Before manual typing acceptance, activate the target text app, run `./scripts/select-inputmethod.sh --require-selected` as a preflight, then type a real probe in that app. Treat preflight failure as "macOS has not switched KnowType into that active TIS context yet" rather than as an install-script failure.

If the input menu does not visibly show `KnowType` / `知键`, inspect the diagnostic's localized-name line. A raw `com.knowtype.inputmethod.KnowType.Mode` name indicates missing or stale `InfoPlist.strings`; duplicate mode registrations usually require logout or reboot after reinstalling.
