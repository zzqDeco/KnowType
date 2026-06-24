# IMK Server Stable Connection

## Status

Delivered.

## Delivered Behavior

- `InputMethodConnectionName`, `KnowTypeInputSourceIDs.connectionName`, and `scripts/lib/inputsource-ids.sh` now use the same stable IMK server connection name: `com.knowtype.inputmethod.KnowType_Connection`.
- `KnowTypeInputMethodApp` continues to read the connection name from `Info.plist` before creating `IMKServer`, matching mature IMK input-method practice seen in Squirrel, McBopomofo, and Mozc.
- The controller write target boundary remains conservative: ordinary text, key event, and commit callbacks use the `IMKTextInput` supplied by the IMK callback. KnowType does not add a broad fallback that guesses another client when a key-event sender is not adaptable.

## Implementation Notes

- Squirrel reads `InputMethodConnectionName` from `Info.plist` and creates `IMKServer` with that value: <https://github.com/rime/squirrel/blob/master/sources/Main.swift>.
- Squirrel updates its weak `IMKTextInput` only when the callback sender is adaptable: <https://github.com/rime/squirrel/blob/master/sources/SquirrelInputController.swift>.
- McBopomofo uses a stable explicit connection name in both `Info.plist` and `main.swift`, and passes IMK callback clients through normal key and commit paths: <https://github.com/openvanilla/McBopomofo/blob/master/Source/main.swift>.
- Mozc reads `InputMethodConnectionName` from `Info.plist` in `main.mm`; its key-event path uses `handleEvent:client:` and passes the callback sender to processing/commit paths: <https://github.com/google/mozc/blob/master/src/mac/main.mm>.

## Verification

- `swift test --quiet --filter InputMethodBundleInfoTests`
- `swift test --quiet --filter "InputControllerCoordinatorTests/testInputControllerWrapper"`
- `swift test --quiet`
- `bash -n scripts/install-inputmethod.sh scripts/repair-inputmethod-selection.sh scripts/rollback-inputmethod.sh scripts/select-inputmethod.sh scripts/smoke-inputmethod-install.sh`
- `bash ./scripts/smoke-inputmethod-install.sh`
- `bash ./scripts/smoke-inputmethod-install.sh --with-prefpane`
- `/bin/bash ./scripts/perf-input-hotpath.sh`
- `git diff --check`
- Local release install reported postflight ok and installed build `20260624172106`.
- `PATH="/usr/bin:/bin:/usr/sbin:/sbin" ./scripts/diagnose-inputmethod.sh --strict --json` exited with zero failures and zero warnings.
- Cold-starting the installed app created launchd endpoint `com.knowtype.inputmethod.KnowType_Connection`.
- Protected user data hash manifests for Rime, AI learning/profile, provider profile, and `~/.knowtype` remained unchanged after install, selection, strict diagnostics, and cold-start endpoint verification.

## Docs Absorbed By

- [doc/interfaces.plan.md](../doc/interfaces.plan.md)
- [doc/src/Sources/KnowTypeInputMethodApp/README.plan.md](../doc/src/Sources/KnowTypeInputMethodApp/README.plan.md)
- [doc/src/Sources/KnowTypeInputSourceSupport/README.plan.md](../doc/src/Sources/KnowTypeInputSourceSupport/README.plan.md)

## Retirement Criteria

Retire after the connection-name change is merged and one more local IMK acceptance cycle confirms menu selection and real keyboard input outside Codex.
