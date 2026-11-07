# IMK Idle Deactivate XPC Avoidance And Archived Install Backups

## Delivered Behavior

- Guarded `InputControllerCoordinator.deactivateServer(client:)`,
  `InputControllerCoordinator.hidePalettes()`, and
  `InputControllerCoordinator.inputControllerWillClose()` so `hostCursorSnapshot`
  (`selectedRange`, `markedRange`, and `bundleIdentifier` reverse-XPC queries)
  and fallback `host.currentClient` lookups only run when an active symbol or
  text/native composition requires them, and skipped `selectedRange`
  punctuation-context reads when `.lifecycleFinish` commits active raw text on
  deactivate, eliminating 3-second `IMKServerXPCInvocation` main-thread
  deadlocks during focus switches in hosts such as Apple Music, Chrome, and
  Acrobat Pro.
- Updated `KnowTypeInputController.deactivateServer(_:)` to pass only the
  callback sender adapter and rely on the coordinator's active-composition
  fallback to `currentClient`.
- Changed `knowtype_create_install_backup` to store backup bundles as lossless
  `ditto` zip archives (`KnowType.app.zip` and optional `KnowType.prefPane.zip`)
  inside `~/Library/Application Support/KnowType/Backups/<backup-id>/` so
  LaunchServices and Spotlight never index unpacked `.app` bundles under
  `Application Support`, while preserving backward-compatible rollback and
  diagnostics support for legacy unpacked `KnowType.app` backups and archiving
  existing unpacked managed backups in place during `install-inputmethod.sh`.

## Verification

- `swift test`
- `./scripts/smoke-inputmethod-install.sh`

## Docs Absorbed By

- [InputController](../doc/src/Sources/KnowTypeInputMethod/InputController.plan.md)
- [InputControllerCoordinator](../doc/src/Sources/KnowTypeInputMethod/InputControllerCoordinator.plan.md)
- [Input Method Installation Helpers](../doc/src/scripts/lib/inputmethod-installation.plan.md)
- [Input Method Installer](../doc/src/scripts/install-inputmethod.plan.md)
- [Input Method Rollback](../doc/src/scripts/rollback-inputmethod.plan.md)

## Retirement Criteria

- Retire once idle IMK lifecycle XPC avoidance and archived install backups are
  part of a tagged release and remain covered by unit and script smoke tests.
