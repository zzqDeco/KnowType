# Deduplicate Local Install Bundles

Status: Active

## Summary

Local development installs now share duplicate bundle and LaunchServices cleanup
helpers. The installer, repair script, and uninstaller detect all local
KnowType input-method bundles under `~/Library/Input Methods`, unregister stale
LaunchServices records, and refuse unsafe paths that resolve outside the local
Input Methods directory.

## Delivered Behavior

- `scripts/install-inputmethod.sh --dry-run` prints local KnowType bundles and
  LaunchServices records that would be cleaned without mutating system state.
- Real install removes safe local duplicate bundles before copying the newly
  built app, then continues to use installed-app TIS activation for `.Hans`.
- `scripts/repair-inputmethod-selection.sh` backs up relevant preference plists,
  removes duplicate local bundles except the installed path, unregisters stale
  LaunchServices records, and then runs the existing installed-app activation
  and scoped preference repair flow.
- `scripts/uninstall-inputmethod.sh --dry-run` reports pending removals as
  pending work; real uninstall removes all safe local KnowType bundles and the
  local preference pane.

## Safety Notes

The cleanup helper treats symlinked or externally resolved bundle paths as hard
failures for install replacement. This prevents `cp -R` from writing into an
external bundle target when `~/Library/Input Methods/KnowType.app` is not a
safe local directory.

## Verification

- `swift test`
- `./scripts/smoke-inputmethod-install.sh`
- `git diff --check`
