# scripts/lib/inputmethod-installation.sh

`scripts/lib/inputmethod-installation.sh` contains shared local install cleanup
helpers for KnowType's traditional IMK bundle.

It owns path discovery for `~/Library/Input Methods/KnowType.app` and
`~/Library/PreferencePanes/KnowType.prefPane`, LaunchServices registration
cleanup, and duplicate local KnowType bundle detection. The helper uses the
current shared input-source IDs from `scripts/lib/inputsource-ids.sh`, including
the visible `.Hans` mode and legacy `.Mode` cleanup list.

The safe-removal helper is intentionally strict: if a path resolves outside the
local Input Methods directory, or does not look like a KnowType input-method
bundle, it fails instead of removing or replacing it. Install and repair scripts
must treat that failure as blocking so a symlink or stale LaunchServices path
cannot redirect local install writes into an unrelated bundle.

Dry-run callers may use the same discovery functions, but final summaries must
say "would remove" instead of reporting completed removal.

Related scripts:

- `scripts/install-inputmethod.sh`
- `scripts/repair-inputmethod-selection.sh`
- `scripts/uninstall-inputmethod.sh`
- `scripts/smoke-inputmethod-install.sh`
