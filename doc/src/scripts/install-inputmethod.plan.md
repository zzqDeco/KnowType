# scripts/install-inputmethod.sh

## Responsibility

Installs the locally built KnowType input method bundle into
`~/Library/Input Methods/KnowType.app`.

## Boundaries

- The script copies and prepares the local development bundle.
- The compatibility PreferencePane is optional and installed only with
  `--with-prefpane` or `KNOWTYPE_INSTALL_PREFPANE=1`.
- It does not prove target-app typing behavior; manual acceptance still must
  type in real host apps.

## Behavior Notes

- The script can install from four sources: a release-config local build, an
  existing `KnowType.app` via `--from-bundle`, a release archive via
  `--from-release-zip`, or a mounted Developer Preview DMG root via
  `--from-dmg-payload`.
- Developer Preview DMG installs record `source=dmg-dev-preview`, release
  commit/tag, and manifest digest in install state.
- Release archive provenance is accepted only when the extracted archive has a
  single unambiguous `release-manifest.json`; older archives may still use one
  sibling manifest beside the zip.
- Before replacing an existing app, it creates an install-artifact backup under
  `~/Library/Application Support/KnowType/Backups/` unless `--no-backup` is
  passed. Backups contain `KnowType.app`, optional `KnowType.prefPane`, and a
  manifest; they do not contain user data.
- Successful installs write
  `~/Library/Application Support/KnowType/install-state.json` with source,
  version/build, commit/tag when known, installed paths, and previous backup id.
- If replacement fails after a backup is created, the script attempts to restore
  that backup before exiting.
- The script keeps the newest three backups by default. Use `--keep-backups N`
  to adjust retention.
- The script switches away from any current KnowType source, replaces
  `~/Library/Input Methods/KnowType.app`, clears quarantine, and refreshes the
  installed path with `lsregister -f`.
- It terminates any running `KnowTypeInputMethodApp`, replaces the bundle, then
  asks the newly installed app to disable stale `.Mode` TIS modes and unregister
  older KnowType LaunchServices paths.
- Local installs inject a timestamp `CFBundleVersion` by default so
  LaunchServices and TIS do not keep reusing stale metadata from a previous
  development build with the same source-controlled version.
- It executes the installed app with
  `--knowtype-install-activate` so registration, enabling, and best-effort
  selection happen from the signed app context before `IMKServer` starts.
- It uses `knowtype-inputsource-tool repair-preferences --add-active` before
  and after app activation to keep local development caches aligned with the
  System Settings add result: `.Hans` in HIToolbox/history and parent anchor
  plus `.Hans` in `com.apple.inputsources`.
- After activation, it opens the installed app as a background agent so the
  `IMKServer` connection is available to Text Input clients.
- The primary settings entry is the input-method menu's
  `KnowType Settings...`; the script does not install a standalone settings app.
- Default installs remove any previously installed compatibility
  `KnowType.prefPane` so an old pane cannot drift out of version sync with the
  newly installed input-method app. Use `--with-prefpane` to install a matching
  compatibility pane.
- The script removes stale System Settings PreferencePane cache files only when
  they contain stable pane identifiers (`com.knowtype.preferencepane` or
  `KnowType.prefPane`) using fixed-string matching, and asks System Settings to
  quit if it is running so the sidebar is rebuilt on next launch. Plain
  unrelated `KnowType` text and regex-like lookalikes such as
  `comXknowtypeXpreferencepane` are not treated as stale pane metadata. This
  prevents a default install from leaving an unloadable `KnowType` sidebar item
  after the optional pane has been removed.
- TIS registration, enablement, and selection remain attributed to
  `KnowType.app`; the SwiftPM helper is used only for scoped preference repair.
- macOS 15 local policy issues may still require the SystemPolicyRule profile
  flow before selection works reliably.

## Tests

- `scripts/smoke-inputmethod-install.sh`
- Manual `doc/mvp-acceptance.plan.md` install gate
