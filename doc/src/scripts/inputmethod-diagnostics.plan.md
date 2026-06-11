# Input Method Diagnostic Scripts

`scripts/diagnose-inputmethod.sh` is the read-only smoke diagnostic for a locally installed KnowType input-method bundle. `scripts/select-inputmethod.sh` requests KnowType as the current Text Input Source before a manual typing run. `scripts/repair-inputmethod-selection.sh` is the mutating local repair script for stale development registration state. Diagnostics resolve and run the dedicated SwiftPM executable `knowtype-inputsource-tool` instead of embedding `swift -` snippets; install and rollback registration use that helper without launching the input-method host.

It intentionally sits after `scripts/install-inputmethod.sh` in the developer loop:

1. Build and install the bundle.
2. Run the diagnostic to catch packaging, signing, Text Input Source registration, and user-data path issues.
3. Activate the target text app, then request KnowType selection with `scripts/select-inputmethod.sh` when the next step is manual typing.
4. Use TextEdit, browser fields, Terminal, and chat apps for real typing acceptance.

The script does not mutate macOS input-source state. It reports:

- install-state metadata, bundle version/build, source commit/tag when known,
  managed backup count, latest backup id, and the rollback command for that
  backup;
- bundle existence, executable permission, and `Info.plist` identifiers;
- the active visible component input mode `com.knowtype.inputmethod.KnowType.Hans`;
- packaged SwiftPM resource bundle for the seed lexicon;
- codesign verification and signing summary;
- current Text Input Source ID plus KnowType parent/mode registration, enabled
  status, localized display name, exact active-mode count, and legacy `.Mode`
  count;
- persisted HIToolbox and third-party enabled preference rows for active
  KnowType, plus strict failures when those rows still point at legacy `.Mode`
  or when the third-party parent anchor required by System Settings is missing;
- KnowType's `AppleInputSourceHistory` position, because `Ctrl+Space` normally
  toggles the current and previous input sources and can skip KnowType if it is
  buried behind ABC or Apple Pinyin in history;
- parent TIS type and select-capable state;
- Gatekeeper assessment status, because an Apple Development-signed local bundle can pass `codesign --verify` but still be rejected by system execution policy;
- stale LaunchServices records for the same KnowType bundle id outside `~/Library/Input Methods/KnowType.app`;
- optional compatibility `KnowType.prefPane` metadata when it is installed;
- `KnowTypeInputMethodApp` process status;
- provider profile, candidate history, local lexicon directory paths, AI
  lexical profile file, and ENV/CORRECTION/LEXICAL_PROFILE document presence.

`--json` prints the stable machine-readable subset used by local tooling and
settings diagnostics. It includes `install`, `bundle`, `preferencePane`,
`rime`, `ai`, `userData`, `backups`, `warnings`, and `failures`, and avoids API
keys, user text, candidate text, complete lexicons, and Rime userdb contents.

Use `--strict` only when a failing diagnostic should block a local smoke run. Use `--require-selected` only when this diagnostic process's current TIS context is the thing being checked. Use `--logs` when the visible symptom is "the input source is enabled but cannot be selected"; it prints recent KnowType app logs plus `GatekeeperPolicyScanError` and `user-preference-write com.apple.inputsources` entries from unified logging. For manual typing acceptance after diagnostics have already run, run `scripts/select-inputmethod.sh --require-selected --no-diagnose` while the target text app is active as a selection preflight, then type a real probe in that app. macOS can report a different current source from a later shell diagnostic than the one applied to the frontmost text client. Without `--require-selected`, selection status remains advisory because developers may intentionally keep another keyboard selected while inspecting installation state. Warnings remain advisory because macOS may start the input-method process only after selection/use, the selected input source may intentionally be another keyboard during debugging, and fresh installs may not have provider profiles, history, or local lexicon directories yet.

The diagnostic also warns when macOS resolves the visible input-source name to the raw bundle id. That usually means the bundle was packaged without `*.lproj/InfoPlist.strings` or the TIS cache has not refreshed. The de-duplicated active `.Hans` input-mode count is a strict gate when `--strict` is used; duplicate raw TIS rows are warnings because mature IMK installers de-duplicate TIS records by input-source id and stale session cache can survive until logout or reboot. Stale `.Mode` TIS registrations are warnings because old TIS cache rows can survive even after app-side TIS disable.

When `com.apple.inputsources.plist` still contains a legacy `.Mode` third-party
row and has `com.apple.macl` or `com.apple.quarantine` extended attributes,
strict diagnostics fail with a local-machine cleanup hint. That state means TIS
registration is no longer the blocker; macOS is protecting or restoring the
stale third-party input-source preference file, so cleanup needs Full Disk
Access for Terminal/Codex or a logout/reboot before repeating System Settings
remove/add.

When Gatekeeper rejects an Apple Development build on macOS 15+, the diagnostic points to `scripts/create-local-system-policy-profile.sh --open`. That helper reads the installed bundle's designated code requirement and writes a device `com.apple.systempolicy.rule` configuration profile for manual System Settings installation. It does not install the profile itself because modern macOS no longer permits configuration-profile installation through the `profiles` CLI. After the profile is installed, `spctl --assess --type execute` should accept the bundle before a typing result is treated as KnowType acceptance.

`scripts/select-inputmethod.sh` is the explicit selection step before manual typing. Passing `--require-selected` gates on the active process's current source result; the follow-up read-only diagnostic intentionally does not require its own process context to be selected.

The helper reports `AppleSelectedInputSources` and `AppleEnabledInputSources` from `com.apple.HIToolbox`, plus the third-party input source preference from `com.apple.inputsources`. This makes the local acceptance distinction explicit: diagnostics can verify registration and persisted state, but manual typing must use the active app's selected input source. Missing HIToolbox mode rows, missing third-party mode rows, missing third-party parent anchor, remaining legacy `.Mode` rows, or a KnowType history index beyond 1 are failures under `--strict` because the macOS input menu and `Ctrl+Space` switcher can skip the input method when the protected enabled list or history points at stale sources first. The helper registration path follows mature IMK boundaries by preparing TIS records without starting the host; explicit repair only rewrites scoped KnowType rows to match the System Settings add result.

On first local installation, macOS can show a System Settings authorization
prompt asking whether to allow `知键` to enable `KnowType`. Until the user
clicks Allow, TIS can report KnowType as registered and enabled while the
system input menu or shortcut still falls back to another source. This is a
permission gate, not a Chinese engine failure.

When `TISSelectInputSource` returns success in the app context and `AppleSelectedInputSources` still remains on Apple Pinyin, the diagnostic treats this as an input-source selection-chain problem rather than an engine problem. The two log patterns that matter most are `GatekeeperPolicyScanError Code=-67018`, which means system policy has not allowed the locally signed bundle, and `user-preference-write com.apple.inputsources`, which means a sandboxed helper attempted to mutate Text Input Source preferences.

`knowtype-inputsource-tool dump` prints every TIS record for the KnowType bundle. Use it when the input menu shows `知键` but the item is disabled or selection falls back to another source; duplicated parent or legacy mode records usually point to stale Text Input Source registration.

`scripts/repair-inputmethod-selection.sh` uses helper `purge-legacy`, `repair-preferences`, and `bootstrap --select` to remove legacy KnowType rows and restore the third-party parent anchor plus `.Hans`, then restarts `cfprefsd`, `TextInputMenuAgent`, and `TextInputSwitcher`. It does not start the installed input-method host. Use it after repeated local installs when stale `.Mode` rows or missing third-party anchors make the menu bounce back to Apple Pinyin or ABC. Add KnowType in System Settings if the third-party enabled list remains missing.

`knowtype-inputsource-tool disable` remains available for manual cleanup. The local install script copies the new bundle, refreshes LaunchServices, then uses helper `purge-legacy`, `repair-preferences`, and `bootstrap` without `--select` so cleanup, registration, and enablement do not launch `KnowTypeInputMethodApp`.

The default install script does not install `KnowType.prefPane`. That
PreferencePane remains a compatibility fallback requested with `--with-prefpane`;
the primary settings entry is the input-method menu item `KnowType Settings...`.
When the pane is missing, strict diagnostics fail if System Settings cache files
still contain stable PreferencePane identifiers (`com.knowtype.preferencepane`
or `KnowType.prefPane`), because that produces an unloadable `KnowType` sidebar
entry. Diagnostics validate installed pane metadata, binary shape, and signing
without loading the pane bundle. Re-run the install or uninstall script to remove
those cache files and reopen System Settings.

`KnowTypeInputMethodApp` still handles compatibility/debug flags such as `--knowtype-install-activate`,
`--knowtype-switch-away`, `--knowtype-purge-legacy`,
`--knowtype-disable-input-source`,
`--knowtype-register-input-source`, `--knowtype-enable-input-source`, and
`--knowtype-select-input-source` before starting `IMKServer`, matching mature IMK
installers that perform TIS registration/enablement in a short command-line
mode. Default install/rollback/repair paths do not execute those flags. Normal app launch still starts the server and enables the active input source
from the signed app bundle context. The disable command mirrors the
TIS disable path used by mature installers for cleanup before a System Settings
re-add; it does not write preference files. Stale `.Hans`/`.Mode` records are counted
for logs but are not activation targets, and the preference rewrite stays
inside the explicit repair script.

CI validates the non-mutating parts of this workflow: shell syntax for all local input-method scripts, helper packaging expectations, help output for the diagnostic and selection helpers, and `scripts/build-inputmethod-bundle.sh` packaging of the executable, `Info.plist`, SwiftPM core resource bundle, and input-source icon. CI does not install or select the input method because those actions mutate runner Text Input Source state.

After installation, `scripts/install-inputmethod.sh` prints the same separation explicitly: run the strict diagnostic for installed state, activate the target text app, run the require-selected selection preflight, then type a real probe before manual acceptance.
