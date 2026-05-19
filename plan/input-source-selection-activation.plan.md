# Input Source Selection Activation

## Goal

Fix the local state where macOS shows `KnowType` / `知键` in the input menu but
keeps the menu item disabled, so it cannot be selected in the active text app.

## Findings

- The bundle can be installed, signed, registered, enabled, and launched while
  the input menu still exposes `知键` as an `enabled=false` menu item.
- `knowtype-inputsource-tool` can see helper-local TIS selection success, but
  `TextInputMenuAgent` may still refuse the menu item.
- Apple Text Input Sources headers confirm the parent input-method record is
  not necessarily selectable; the visible input mode is the selectable source
  and requires the parent to be enabled.
- Local logs can show two different blockers:
  `user-preference-write com.apple.inputsources` when a sandboxed helper tries
  to write input-source preferences, and `GatekeeperPolicyScanError -67018`
  when an Apple Development-signed local bundle passes `codesign --verify` but
  is still not allowed by system policy.
- `KnowTypeInputMethodApp --knowtype-install-activate` can log
  `TISSelectInputSource` success in the app context while the persisted
  HIToolbox selected input source still remains Apple Pinyin. That is evidence
  of a selection-chain/system-policy issue, not a pinyin engine issue.
- This means command-line TIS state is not enough for local acceptance. The
  installed app must participate in registration/enabling from its own signed
  bundle context, matching the pattern used by mature macOS input-method
  installers.

## Implementation

- `KnowTypeInputMethodApp` registers and enables its installed input source on
  launch from the signed app context.
- The app writes unified logs under subsystem
  `com.knowtype.inputmethod.KnowType`, category `input-method-app`.
- `knowtype-inputsource-tool status` reports parent/mode TIS type and
  select-capable state.
- `knowtype-inputsource-tool dump` prints every TIS record for the KnowType
  bundle so duplicate or stale records are visible.
- `knowtype-inputsource-tool disable` disables existing KnowType TIS records
  for manual cleanup when stale enabled rows remain in HIToolbox preferences.
- `scripts/install-inputmethod.sh` copies the built bundle, launches the
  installed app with `--knowtype-install-activate`, then reads helper status
  without routing registration or selection through a sandboxed helper.
- The app registers through `TISRegisterInputSource` only when no KnowType
  sources exist, then enables existing records on every launch. Repeated local
  installs must not create more stale duplicate mode records.
- `scripts/diagnose-inputmethod.sh --logs` surfaces recent app, Gatekeeper, and
  input-source sandbox logs so local selection failures can be traced to the
  right layer.

## Verification

```bash
swift test
./scripts/install-inputmethod.sh
./scripts/diagnose-inputmethod.sh --strict
```

Manual acceptance still requires opening the active app input menu and checking
that `知键` is enabled, then typing a real probe in TextEdit or another text
field.
