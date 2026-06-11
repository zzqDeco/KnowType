# scripts/rollback-inputmethod.sh

## Responsibility

Restores a local KnowType install artifact backup created by the install or
uninstall scripts.

## Boundaries

- Rollback restores `KnowType.app` and optional `KnowType.prefPane` only.
- It does not restore or delete user data, Rime userdb, provider profiles,
  Keychain secrets, ENV.md, CORRECTION.md, LEXICAL_PROFILE.md, or local
  lexicons.
- It is a local development recovery tool, not a notarized production updater.

## Behavior Notes

- `--list` prints managed, restorable backup ids with version/build metadata.
- `--latest` restores the newest managed backup; `--to <backup-id>` restores a
  specific backup.
- `--dry-run` shows target app/prefPane paths and refresh steps without changing
  files or input-source state.
- Rollback preflights the backed-up app with the same required runtime checks
  as install source validation before it replaces the current bundle.
- A real rollback first requires `KnowTypeInputMethodApp` to be stopped, then
  switches away from KnowType, restores the backup app, refreshes
  LaunchServices, clears stale prefPane caches, repairs scoped input-source
  preferences, runs helper bootstrap without `--select`, and writes
  `install-state.json`. The running-host check matches the full process command
  basename rather than a truncated process name.
- Rollback does not start the restored input-method host or initialize Rime user
  data; the user still verifies real typing after selecting KnowType manually.

## Tests

- `scripts/smoke-inputmethod-install.sh`
- Manual local rollback after installing a newer build
