# Input Method Install Canonical Registration

## Summary

Fix local development installs where the macOS menu bar does not reliably show
KnowType after replacing the app bundle. Release zip installs validated as the
healthy baseline: they end at the canonical
`~/Library/Input Methods/KnowType.app` path and the input menu shows the `K`
icon plus the `知键` item. Manual local installs can diverge when the old
input-method host is still running or when `dist/KnowType.app`/temporary
release payload paths remain registered in LaunchServices.

## Scope

- Change `scripts/install-inputmethod.sh` so local, bundle, release zip, and DMG
  payload installs enter a safe quiesce phase before building or replacing the
  installed bundle.
- Keep the existing parent input method plus visible `.Hans` input mode model.
- Keep user data, Settings UI, candidate panel, AI, Rime schema, and provider
  configuration unchanged.
- Treat the experimental display-name branch as the wrong fix direction; menu
  visibility is an install registration and host lifecycle issue.

## Implementation

- Before the first host-stopped gate, the installer switches away to the
  fallback input source, disables all existing KnowType TIS rows by bundle id,
  restarts `cfprefsd`, `TextInputMenuAgent`, and `TextInputSwitcher`, then asks
  any remaining `KnowTypeInputMethodApp` process to exit with `TERM`.
- The default installer does not hard-kill the host. `--force-stop-host` is an
  explicit developer option that sends `KILL` only after switch-away, disable,
  menu-agent refresh, and a failed `TERM` window.
- After copying the source bundle to
  `~/Library/Input Methods/KnowType.app`, the installer unregisters stale
  LaunchServices records except that canonical target and registers only the
  canonical target.
- After refreshing `cfprefsd` and text-input menu agents, the installer performs
  one final scoped preference repair before restarting only the menu agents. This
  keeps HIToolbox enabled rows aligned after pre-install disable.
- Dry-run output reports the quiesce plan without mutating input sources or
  processes.
- Install summary reports source path, canonical target path, pre-install
  disable status/count, host-stop status, menu-agent restart status, stale
  LaunchServices cleanup count, and the manual menu acceptance gate.

## Test Plan

- `swift test --quiet --filter InputMethodBundleInfoTests`
- `bash -n scripts/install-inputmethod.sh scripts/repair-inputmethod-selection.sh scripts/diagnose-inputmethod.sh`
- `git diff --check`
- Manual local build install:
  `./scripts/install-inputmethod.sh --configuration release`,
  `./scripts/select-inputmethod.sh --require-selected --no-diagnose`, and
  `./scripts/diagnose-inputmethod.sh --strict`.
- Manual menu acceptance: the real macOS input menu must show the `K` icon and a
  `知键` entry. Helper selection alone is not sufficient.
- Release-path regression: install the latest prerelease local MVP zip through
  `--from-release-zip` and confirm it follows the same canonical registration
  postflight.

## Assumptions

- Release `v0.2.4` menu behavior is the known-good baseline.
- A local install should not mutate Rime userdb, provider profiles, Keychain
  secrets, AI learning files, `~/.knowtype`, or lexicon data.
- If the host survives the default TERM path, the user must either quit it
  manually or opt in to `--force-stop-host` for development installs.
