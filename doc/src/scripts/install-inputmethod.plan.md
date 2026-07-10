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
  commit/tag, and manifest digest in install state. Packaged copies do not
  require the source-tree `Resources/InputMethod/Info.plist`; source version
  lookup is limited to local-build mode.
- Release archive provenance is accepted only when the extracted archive has a
  single unambiguous `release-manifest.json`; older archives may still use one
  sibling manifest beside the zip.
- Before replacing an existing app, it creates an install-artifact backup under
  `~/Library/Application Support/KnowType/Backups/` unless `--no-backup` is
  passed. Backups contain `KnowType.app`, optional `KnowType.prefPane`, and a
  manifest; they do not contain user data.
- New backups use manifest schema `2` and record complete app and optional pane
  checksum, bundle identity, short version/build, and signing
  requirement/identity metadata. Backup creation fails rather than writing an
  unverifiable rollback point.
- Successful installs write
  `~/Library/Application Support/KnowType/install-state.json` with source,
  version/build, commit/tag when known, installed paths, and previous backup id.
- If replacement fails after a backup is created, the script validates that
  schema `2` backup before attempting recovery. Failed-install recovery also
  refuses to remove or replace a foreign same-name PreferencePane. App and pane
  recovery copies are staged and validated before the canonical targets change.
- The script keeps the newest three backups by default. Use `--keep-backups N`
  to adjust retention.
- The script switches away from any current KnowType source, disables existing
  KnowType TIS rows, restarts text-input menu agents, asks a remaining
  `KnowTypeInputMethodApp` to exit with `TERM`, replaces
  `~/Library/Input Methods/KnowType.app`, clears quarantine, and refreshes the
  installed path with `lsregister -f`.
- `--force-stop-host` is an explicit development escape hatch. The default path
  never sends `KILL`; if `TERM` does not quiesce the host, the install fails
  with instructions instead of risking an unplanned process kill.
- The postflight unregisters stale LaunchServices records for source,
  `dist/KnowType.app`, release extraction, and backup paths, then registers only
  the canonical installed app at `~/Library/Input Methods/KnowType.app`.
  Registering `dist/KnowType.app` directly is not a supported local install
  state because it can split helper/TIS state from the real menu-bar state.
- It switches away, disables stale `.Mode` TIS modes, registers/enables the
  parent anchor and visible `.Hans` mode from the installed app CLI context, and
  repairs scoped preference rows through `knowtype-inputsource-tool`.
  These default install steps return before the app run loop starts and do not
  select KnowType.
- After the post-registration `cfprefsd` and menu-agent refresh, it runs one
  final scoped preference repair and restarts only the menu agents. This keeps
  HIToolbox enabled rows from being overwritten by stale `cfprefsd` cache after
  a pre-install disable.
- The switch-away helper also removes KnowType from HIToolbox
  `AppleSelectedInputSources`; otherwise macOS can relaunch the host from stale
  selected preferences even when the live current source is ABC.
- If `KnowTypeInputMethodApp` keeps running after switch-away, disable, menu
  agent refresh, and `TERM`, the installer aborts before replacement unless
  `--force-stop-host` was explicitly passed. The process check matches the full
  process command basename rather than a truncated process name.
- If source preparation, bundle validation, or another pre-replacement preflight
  fails after quiescing, the failure trap re-registers/re-enables the existing
  canonical install, unregisters non-canonical LaunchServices records, and
  repairs scoped preferences. A failed local build or bad release archive must
  not leave the previously working input source disabled.
- Local installs inject a timestamp `CFBundleVersion` by default so
  LaunchServices and TIS do not keep reusing stale metadata from a previous
  development build with the same source-controlled version. The installer
  resolves one short version and one build version and passes both to the app
  and optional PreferencePane builders.
- It uses `knowtype-inputsource-tool repair-preferences --add-active` around the
  installed app registration to keep local development caches aligned with the
  current parent-plus-mode model: enabled preferences contain the parent anchor
  and `.Hans`; history repair keeps `.Hans` available without moving it ahead of
  the retained current source. The install path does not pass
  `--include-selected`, so it does not rewrite the user's selected input source.
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
- The primary settings entry is the input-method menu's localized settings item,
  defaulting to `KnowType 设置...`; the script does not install a standalone
  settings app.
- Default installs remove any previously installed compatibility
  `KnowType.prefPane` so an old pane cannot drift out of version sync with the
  newly installed input-method app. Use `--with-prefpane` to install a matching
  compatibility pane.
- Any installed `KnowType.prefPane` must be the canonical non-symlink path and
  declare `CFBundleIdentifier=com.knowtype.preferencepane`. A same-name foreign
  bundle blocks install before quiescing or replacement. A new pane is copied
  and validated in a sibling staging directory before the existing pane is
  moved aside and the staged bundle is atomically published.
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
