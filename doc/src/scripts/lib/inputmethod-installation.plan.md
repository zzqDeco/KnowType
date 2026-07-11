# scripts/lib/inputmethod-installation.sh

`scripts/lib/inputmethod-installation.sh` contains shared local install cleanup
helpers for KnowType's traditional IMK bundle.

It owns path discovery for `~/Library/Input Methods/KnowType.app` and
`~/Library/PreferencePanes/KnowType.prefPane`, LaunchServices registration
cleanup, duplicate local KnowType bundle detection, install-state paths, app
backup paths, backup manifest writes, and install bundle preflight validation.
The helper uses the current shared input-source IDs from
`scripts/lib/inputsource-ids.sh`, including the parent input method, visible
`.Hans` input mode, and legacy `.Mode` cleanup list.
Install preflight must also reject bundles that only declare the parent input
method and no menu-visible input mode, so `--from-bundle`, `--from-release-zip`,
and DMG payload installs cannot replace the current app with a non-switchable
parent-only build. The visible mode list must contain exactly one entry, and
that entry must match the current `.Hans` input mode id; older component-mode
bundles that declare another visible mode or retain an extra stale visible mode
are rejected before install/repair writes `.Hans` preferences.

The safe-removal helpers are intentionally strict. An input-method path must
resolve inside the local Input Methods directory and match the KnowType IMK
identity. A PreferencePane path must be the canonical local
`KnowType.prefPane`, must not be a symlink, and must declare
`CFBundleIdentifier=com.knowtype.preferencepane`. Install, uninstall, rollback,
and failed-install recovery treat a mismatch as blocking instead of removing or
replacing a same-name foreign bundle.

The shared pre-v2 provider compatibility validator accepts only a complete
schema-v1 envelope that the legacy Swift decoder can consume: integer version
`1`, a profile array, supported provider kinds, required profile fields, string
headers, numeric timeout, and boolean default state. Install and rollback use
the same validator and fail closed on malformed, tombstone, future-schema,
canonical, snapshot, or compare-and-claim metadata. The shared generation-2
migration runner invokes `knowtype-inputsource-tool` and validates its
privacy-safe status before rollback proceeds; it never launches the installed
IMK app executable.

PreferencePane replacement copies into a sibling staging directory, validates
the staged bundle, moves the current canonical pane aside, and only then
publishes the staged pane. A copy or validation failure leaves the current pane
untouched; a publish failure restores the moved-aside pane when available. The
same helper is used by normal install and failed-install recovery.

Dry-run callers may use the same discovery functions, but final summaries must
say "would remove" instead of reporting completed removal.

Install backups are artifact backups only. They may contain `KnowType.app` and
`KnowType.prefPane`, but they must not contain provider profiles, Keychain
secrets, Rime userdb, ENV.md, CORRECTION.md, LEXICAL_PROFILE.md, or local
lexicon data. Schema `2` manifests require each included artifact's checksum,
bundle identifier, short version, build version, designated signing
requirement, and normalized signing identity. Pane integrity fields are null
when no pane is included.

Backup discovery only treats directories with managed backup IDs, matching
manifests, and a restorable `KnowType.app` as rollback candidates. Unrelated
folders under the backup root are ignored by `--latest`, retention pruning, and
diagnostic backup summaries.

Rollback derives the active input mode from the restored bundle's
`ComponentInputModeDict` before repairing TIS preferences. Backups that only
declare the parent input method and no menu-visible input mode are rejected
before restore/repair, because they cannot satisfy the current menu-switchable
IMK model.

Schema `2` rollback validates manifest shape, recorded metadata, bundle
contents, `codesign --verify --deep --strict`, the recorded requirement, and
the staged copy before replacement. Missing or mismatched integrity data is
fatal. Schema `1` is rejected unless the caller explicitly uses
`--allow-unverified-backup`; that override remains legacy-only and cannot
bypass schema `2` failures.

Related scripts:

- `scripts/install-inputmethod.sh`
- `scripts/repair-inputmethod-selection.sh`
- `scripts/rollback-inputmethod.sh`
- `scripts/uninstall-inputmethod.sh`
- `scripts/smoke-inputmethod-install.sh`
