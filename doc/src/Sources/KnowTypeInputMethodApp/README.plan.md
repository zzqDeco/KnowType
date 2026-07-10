# Sources/KnowTypeInputMethodApp

`KnowTypeInputMethodApp` is the macOS agent process entry point for the installable MVP bundle.

Normal input-method launch is serve-only. `applicationDidFinishLaunching` creates `IMKServer` with the stable connection name declared in `Info.plist` (`com.knowtype.inputmethod.KnowType_Connection`) and emits the launch log before the `LSUIElement` application services its event loop. It does not register, enable, select, poll for, or repair Text Input Source records. `KnowTypeInputMethodStartupPolicy` keeps this path separate from explicit command execution, so missing parent or visible-mode records cannot make normal host startup wait.

Command-line activation flags remain available for installer, repair, compatibility, and debugging paths before `IMKServer` starts: `--knowtype-install-activate` registers, enables, and selects the visible `com.knowtype.inputmethod.KnowType.Hans` input mode from the signed installed app context; `--knowtype-disable-input-source` disables KnowType records through TIS before a System Settings re-add; `--knowtype-purge-legacy` disables legacy `.Mode` sources and cleans LaunchServices state; `--knowtype-switch-away` moves away from KnowType before replacement; and the narrower register/enable/select flags support script retries. Registration waits for the parent and visible mode only on these explicit paths. The select flag prints both `select.status` and `select.current`; a `noErr` TIS status is treated as a successful best-effort request even if the helper-local current source has not changed, and scripts decide whether to make that a hard failure. These CLI flags return before the app run loop starts, so registration does not initialize Rime user data. Stale `.Mode` registrations and parent-only selected/history rows are cleanup targets only. The actual per-client composition behavior lives in `KnowTypeInputController` inside `KnowTypeInputMethod`.

The installer also uses explicit `--knowtype-migrate-provider-profiles`,
`--knowtype-rollback-provider-profile-migration`, and
`--knowtype-downgrade-provider-profiles` commands. They run before the IMK
server, use `KnowTypeProviders` transactional storage and Keychain access,
honor the installer's `KNOWTYPE_APP_SUPPORT_DIR` test override, and print only
status/revision/count metadata. They never print endpoint, profile, or secret
contents. Migration rollback also requires the exact canonical revision emitted
by the corresponding migration command. The downgrade command preserves the
current profile set and credential references while writing the numeric schema
required by a pre-v2 backup.

The app target delegates low-level TIS lookup/property/ordering/wait helpers and LaunchServices stale-record cleanup to `KnowTypeInputSourceSupport`. The app entry point remains responsible for installed-app command sequencing, stdout/stderr compatibility, `IMKServer` startup, and avoiding Rime/user-data initialization during registration-only commands.

Local bundle assembly is intentionally script-based for v1:

- `scripts/build-inputmethod-bundle.sh` builds the executable and writes `dist/KnowType.app`.
- SwiftPM resource bundles such as `KnowType_KnowTypeCore.bundle` are copied into `Contents/Resources`, where the signed app bundle can contain them.
- `scripts/install-inputmethod.sh` copies the bundle into `~/Library/Input Methods`, then uses the installed app CLI to register and enable the parent anchor plus visible `.Hans` mode, with helper `repair-preferences` as scoped cache repair.
- `scripts/repair-inputmethod-selection.sh` cleans stale local LaunchServices records, stale `.Mode` preference rows, parent-only selected/history rows, and stale legacy TIS modes when repeated development installs make the input menu show duplicates or bounce back to another source. It invokes the installed app CLI to restore and verify `.Hans`, falls back to helper bootstrap when app registration fails, and rewrites HIToolbox selected preferences only after installed app selection is verified.
- `scripts/uninstall-inputmethod.sh` removes that local bundle and uses scoped preference cleanup to clear enabled KnowType rows that would otherwise point at the removed bundle.
