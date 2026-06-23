# scripts/lib/inputmethod-installation.sh

`scripts/lib/inputmethod-installation.sh` contains shared local install cleanup
helpers for KnowType's traditional IMK bundle.

It owns path discovery for `~/Library/Input Methods/KnowType.app` and
`~/Library/PreferencePanes/KnowType.prefPane`, LaunchServices registration
cleanup, duplicate local KnowType bundle detection, install-state paths, app
backup paths, backup manifest writes, and install bundle preflight validation.
The helper uses the current shared input-source IDs from
`scripts/lib/inputsource-ids.sh`, including the single active input source and
legacy `.Hans` / `.Mode` cleanup list.

The safe-removal helper is intentionally strict: if a path resolves outside the
local Input Methods directory, or does not look like a KnowType input-method
bundle, it fails instead of removing or replacing it. Install and repair scripts
must treat that failure as blocking so a symlink or stale LaunchServices path
cannot redirect local install writes into an unrelated bundle.

Dry-run callers may use the same discovery functions, but final summaries must
say "would remove" instead of reporting completed removal.

Install backups are artifact backups only. They may contain `KnowType.app` and
`KnowType.prefPane`, but they must not contain provider profiles, Keychain
secrets, Rime userdb, ENV.md, CORRECTION.md, LEXICAL_PROFILE.md, or local
lexicon data.

Backup discovery only treats directories with managed backup IDs, matching
manifests, and a restorable `KnowType.app` as rollback candidates. Unrelated
folders under the backup root are ignored by `--latest`, retention pruning, and
diagnostic backup summaries.

Related scripts:

- `scripts/install-inputmethod.sh`
- `scripts/repair-inputmethod-selection.sh`
- `scripts/rollback-inputmethod.sh`
- `scripts/uninstall-inputmethod.sh`
- `scripts/smoke-inputmethod-install.sh`
