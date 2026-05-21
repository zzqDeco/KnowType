# System Settings PreferencePane Cache Cleanup

## Summary

- Default local installs keep KnowType settings behind the input-method menu
  item `KnowType Settings...` and do not install `KnowType.prefPane`.
- macOS can keep `com.knowtype.preferencepane` in System Settings cache files
  after the optional pane is removed, leaving an unloadable `KnowType` sidebar
  item.

## Implementation

- Add shared install helpers that detect and remove the known System Settings
  PreferencePane cache files only when they contain stable pane identifiers:
  `com.knowtype.preferencepane` or `KnowType.prefPane`. Matching is fixed-string
  only, so regex-like lookalikes such as `comXknowtypeXpreferencepane` do not
  trigger cleanup or strict diagnostic failures.
- Run that cleanup from default install, `--with-prefpane` install, and
  uninstall, then ask System Settings to quit so its sidebar cache rebuilds.
- Make strict diagnostics fail when the pane is absent but the cache still
  references those pane identifiers; a matching installed pane remains valid as a
  compatibility fallback. Diagnostics must not load or execute the pane bundle
  while inspecting install state.

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
