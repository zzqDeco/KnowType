# System Settings PreferencePane Cache Cleanup

## Summary

- Default local installs keep KnowType settings behind the input-method menu
  item `KnowType Settings...` and do not install `KnowType.prefPane`.
- macOS can keep `com.knowtype.preferencepane` in System Settings cache files
  after the optional pane is removed, leaving an unloadable `KnowType` sidebar
  item.

## Implementation

- Add shared install helpers that detect and remove the known System Settings
  PreferencePane cache files only when they contain KnowType metadata.
- Run that cleanup from default install, `--with-prefpane` install, and
  uninstall, then ask System Settings to quit so its sidebar cache rebuilds.
- Make strict diagnostics fail when the pane is absent but the cache still
  references KnowType; a matching installed pane remains valid as a compatibility
  fallback.

## Test Plan

- `swift test --quiet`
- `./scripts/smoke-inputmethod-install.sh`
- `./scripts/smoke-inputmethod-install.sh --with-prefpane`
- `./scripts/perf-input-hotpath.sh`
- `git diff --check`

## Assumptions

- The primary settings surface remains the IMK input-menu preferences window.
- The compatibility PreferencePane stays optional and is installed only with
  `--with-prefpane`.
