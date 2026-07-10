# KnowType Install Upgrade Rollback Experience Plan

## Summary

- Add a local install state file, app/prefPane backups, rollback script, and diagnostics status so local installs are traceable and recoverable.
- Keep user data values in place across install and rollback. Rime userdb,
  Keychain secrets, ENV/CORRECTION/LEXICAL_PROFILE, and lexicon data are not
  copied or restored by default. Provider metadata may be format-converted when
  an older app requires its legacy numeric schema.
- Keep the settings UI read-only for rollback. Replacing the running input-method bundle is handled by external scripts.

## Scope

- `scripts/install-inputmethod.sh` supports source builds, existing app bundles, release zips, backups, and install-state writes.
- `scripts/rollback-inputmethod.sh` restores a saved app/prefPane backup.
- `scripts/uninstall-inputmethod.sh` preserves backups by default.
- `scripts/diagnose-inputmethod.sh --json` provides a stable machine-readable status snapshot.
- Settings diagnostics display install, runtime, AI, user data, and backup status.

## Implementation

- `~/Library/Application Support/KnowType/install-state.json` records schema version, install time, source, version/build, commit/tag when known, installed paths, and the previous backup id.
- `~/Library/Application Support/KnowType/Backups/<backup-id>/manifest.json` records the backed-up app version/build, bundle id, app checksum, prefPane inclusion, and rollback command.
- Install preflights validate KnowType identity, executable, Rime dylib/data, and codesign unless `--no-verify` is passed.
- Install creates a backup before replacing an existing app. If replacement fails after backup, it restores the backup and re-registers LaunchServices.
- Release zips may carry `release-manifest.json` inside the archive; the installer also accepts a sibling manifest for older packages.
- Rollback prepares a provider metadata format compatible with the target app,
  swaps install artifacts, refreshes LaunchServices and input-source
  preferences, and writes a fresh install-state file.
- `diagnose-inputmethod.sh --json` outputs `install`, `bundle`, `rime`, `ai`, `userData`, `backups`, `warnings`, and `failures`.

## Test Plan

- Unit tests cover settings diagnostics status rows for install metadata, runtime resources, AI provider, user data files, and rollback command.
- Smoke tests cover script syntax, install dry-run output, backup manifest creation, rollback list/dry-run, uninstall dry-run backup preservation, and diagnostics JSON shape.
- Required validation:
  - `swift test --quiet`
  - `./scripts/smoke-inputmethod-install.sh`
  - `./scripts/smoke-inputmethod-install.sh --with-prefpane`
  - `./scripts/perf-input-hotpath.sh`
  - `git diff --check`

## Assumptions

- This slice does not add notarized pkg, Sparkle, App Store distribution, or in-app self-update.
- Source values are `local-build`, `release-zip`, and `bundle`; rollback records the restored app as a bundle-sourced install with the restored backup id.
- User data is preserved by leaving it untouched, not by copying it into rollback backups.
