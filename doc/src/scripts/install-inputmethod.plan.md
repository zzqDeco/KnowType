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
- It switches away, disables stale `.Mode` TIS modes, registers/enables the new
  app, and repairs scoped preference rows through `knowtype-inputsource-tool`.
  These default install steps do not start the installed input-method host and
  do not select KnowType.
- The switch-away helper also removes KnowType from HIToolbox
  `AppleSelectedInputSources`; otherwise macOS can relaunch the host from stale
  selected preferences even when the live current source is ABC.
- If `KnowTypeInputMethodApp` is already running, the installer aborts before the
  build/replace phase instead of killing it, because process shutdown can flush
  Rime user data and would violate the install/user-data boundary. The check
  matches the full process command basename rather than a truncated process
  name.
- Local installs inject a timestamp `CFBundleVersion` by default so
  LaunchServices and TIS do not keep reusing stale metadata from a previous
  development build with the same source-controlled version.
- It uses `knowtype-inputsource-tool repair-preferences --add-active` around the
  helper bootstrap to keep local development caches aligned with the current
  single input-source model: enabled preferences contain
  `com.knowtype.inputmethod.KnowType`; history repair keeps that source
  available without moving it ahead of the retained current source. The install
  path does not pass `--include-selected`, so it does not rewrite the user's
  selected input source.
- The install step must not initialize Rime user data, AI learning/profile
  files, provider profiles, `ENV.md`, `CORRECTION.md`, or `~/.knowtype`. Real
  typing after the user manually selects KnowType may initialize Rime as normal
  product use.
- Postflight uses `diagnose-inputmethod.sh --json` as a static install snapshot
  check. Full `--strict` diagnostics remain explicit because TIS diagnostics may
  cause macOS to prelaunch the IMK host on some systems. A JSON diagnostic that
  exits successfully but reports a non-empty top-level `failures` array is still
  treated as a postflight warning.
- Runtime cold-start boundaries are the primary protection: if macOS does
  prelaunch the host during TIS or LaunchServices work, the controller and
  Rime/provider/learning stores must remain read-only until real input or an
  explicit maintenance action.
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
- TIS registration and enablement are performed by the dedicated SwiftPM helper;
  explicit selection belongs to `scripts/select-inputmethod.sh` or
  `scripts/repair-inputmethod-selection.sh`, not the default installer.
- macOS 15 local policy issues may still require the SystemPolicyRule profile
  flow before selection works reliably.

## Tests

- `scripts/smoke-inputmethod-install.sh`
- Manual `doc/mvp-acceptance.plan.md` install gate
