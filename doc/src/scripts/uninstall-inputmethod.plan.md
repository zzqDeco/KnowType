# scripts/uninstall-inputmethod.sh

## Responsibility

Removes the locally installed KnowType input method bundle from the developer
machine.

## Boundaries

- It is a local cleanup script, not a production uninstaller.
- It should not remove unrelated Text Input Source preferences or user data
  unless explicitly documented.

## Behavior Notes

- Use after manual acceptance or when replacing local builds.
- By default, the script creates the same app/prefPane artifact backup used by
  install rollback before removing local bundles. Use `--no-backup` only when a
  rollback point is not wanted.
- Existing backups are preserved after uninstall. Use `--purge-backups`
  explicitly to delete them; purge mode skips creating a new backup because the
  backup root will be removed. User data is still left in place.
- It removes stale System Settings PreferencePane caches that still reference
  `com.knowtype.preferencepane` or `KnowType.prefPane` and asks System Settings
  to quit if needed, so an already removed compatibility pane does not remain as
  an unloadable sidebar item. Plain unrelated `KnowType` cache text is left
  untouched.
- Stale Text Input Source state can still require diagnostics or repair helpers
  after removal.

## Tests

- `scripts/smoke-inputmethod-install.sh`
- Manual local install/uninstall checks
