# scripts/rollback-inputmethod.sh

## Responsibility

Restores a local KnowType install artifact backup created by the install or
uninstall scripts.

## Boundaries

- Rollback restores `KnowType.app` and optional `KnowType.prefPane`. User data
  values remain in place. When the backup predates provider storage generation
  2, the current generation-2 executable first converts canonical profile
  metadata to the numeric legacy schema without changing profiles or Keychain
  secrets.
- It does not restore or delete Rime userdb, Keychain secrets, ENV.md,
  CORRECTION.md, LEXICAL_PROFILE.md, or local lexicons.
- It is a local development recovery tool, not a notarized production updater.

## Behavior Notes

- `--list` prints managed, restorable backup ids with version/build metadata.
- `--latest` restores the newest managed backup; `--to <backup-id>` restores a
  specific backup.
- `--dry-run` shows target app/prefPane paths and refresh steps without changing
  files or input-source state.
- Schema `2` rollback preflight requires complete app and optional pane
  checksum, bundle ID, short version/build, signing requirement, and signing
  identity metadata. It compares every field to the backup, runs
  `codesign --verify --deep --strict`, tests the recorded requirement, and
  rechecks staged-copy checksums before replacing the current bundle.
- Missing or mismatched schema `2` integrity data always fails closed.
  `--allow-unverified-backup` is a prominent legacy-only override for schema
  `1`; dry-run output shows when it is active, and it cannot bypass schema `2`
  validation.
- Rollback refuses to remove or replace an installed same-name PreferencePane
  unless it is the canonical non-symlink bundle with
  `CFBundleIdentifier=com.knowtype.preferencepane`.
- A real rollback first requires `KnowTypeInputMethodApp` to be stopped, then
  switches away from KnowType and quiesces Settings writers. Each app declares
  `KnowTypeProviderProfileStorageGeneration` in `Info.plist`. Before a pre-v2
  backup becomes canonical, the current app runs the explicit privacy-safe
  provider downgrade command; without a usable generation-2 executable,
  canonical metadata or interrupted migration evidence fails closed. After a
  generation-2 backup is published, its explicit migration command converts any
  legacy metadata before the previous app is discarded or registration begins;
  failure restores the previous app only after metadata compatibility is proven.
  Only then does rollback refresh
  LaunchServices, clears stale prefPane caches, repairs scoped input-source
  preferences, runs helper bootstrap without `--select`, and writes
  `install-state.json`. The running-host check matches the full process command
  basename rather than a truncated process name.
- Rollback does not start the restored input-method host or initialize Rime user
  data; the user still verifies real typing after selecting KnowType manually.

## Tests

- `scripts/smoke-inputmethod-install.sh`
- Manual local rollback after installing a newer build
