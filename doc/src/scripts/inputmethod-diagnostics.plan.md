# Input Method Diagnostic Scripts

`scripts/diagnose-inputmethod.sh` is the read-only smoke diagnostic for a locally installed KnowType input-method bundle. `scripts/select-inputmethod.sh` requests KnowType as the current Text Input Source before a manual typing run. `scripts/repair-inputmethod-selection.sh` is the mutating local repair script for stale development registration state. Diagnostics resolve and run the dedicated SwiftPM executable `knowtype-inputsource-tool` instead of embedding `swift -` snippets; install and rollback registration, provider migration, and preference repair all stay in that helper without launching the input-method host run loop.

It intentionally sits after `scripts/install-inputmethod.sh` in the developer loop:

1. Build and install the bundle.
2. Run the diagnostic to catch packaging, signing, Text Input Source registration, and user-data path issues.
3. Activate the target text app, then request KnowType selection with `scripts/select-inputmethod.sh` when the next step is manual typing.
4. Use TextEdit, browser fields, Terminal, and chat apps for real typing acceptance.

The script does not mutate macOS input-source state. It reports:

- install-state metadata, bundle version/build, source commit/tag when known, managed backup count, latest backup id, and rollback command;
- bundle existence, executable permission, and `Info.plist` identifiers;
- that `Info.plist` declares the parent input method plus exactly one visible `.Hans` input mode in `ComponentInputModeDict`;
- packaged SwiftPM resource bundle for the seed lexicon;
- codesign verification and signing summary;
- current Text Input Source ID plus KnowType parent/mode registration, enabled status, select-capable status, localized display names, exact de-duplicated active-mode count, and legacy `.Mode` count;
- persisted HIToolbox and third-party enabled preference rows for the parent anchor and `.Hans`, plus strict failures when selected/history still point at the non-selectable parent or legacy `.Mode`;
- KnowType's `AppleInputSourceHistory` position, because `Ctrl+Space` normally toggles the current and previous input sources and can skip KnowType if it is buried behind ABC or Apple Pinyin in history;
- Gatekeeper assessment status, stale LaunchServices records outside `~/Library/Input Methods/KnowType.app`, optional compatibility `KnowType.prefPane` metadata, `KnowTypeInputMethodApp` process status, privacy-safe provider profile and storage-generation state, local lexicon directories, AI lexical profile files, and ENV/CORRECTION/LEXICAL_PROFILE document presence.

Provider diagnostics distinguish canonical, unmigrated legacy, legacy-writer
divergence, tombstone-only, and missing-canonical states. Divergence warnings
state that both canonical and legacy payloads were preserved; migration may
also retain a permission-restricted `providers.legacy-conflict.<UUID>.json`
when three legacy writes overlap the atomic cutover. Provider summaries
always prefer `providers.v2.json` and never expose credentials or removed URL
query values.

Strict stale LaunchServices failures are install blockers, not cosmetic
warnings. Records that still point at `dist/KnowType.app`, release extraction
directories, or backup paths can make helper-level TIS selection look repaired
while the real macOS input menu still resolves a different bundle path. The
local installer must quiesce the old host before replacement and register only
the canonical `~/Library/Input Methods/KnowType.app` target.

`--json` prints the stable machine-readable subset used by local tooling and settings diagnostics. It includes `install`, `bundle`, `preferencePane`, `rime`, `ai`, `userData`, `backups`, `warnings`, and `failures`, and avoids API keys, user text, candidate text, complete lexicons, and Rime userdb contents. Text and JSON provider summaries both use `scripts/lib/provider_endpoint_summary.py`, which strips URL userinfo, query, and fragment while retaining scheme, host, port, and path. When a query was removed, the summary appends `[query redacted]` without exposing its keys or values.

Use `--strict` only when a failing diagnostic should block a local smoke run. `--legacy-parent-anchor` is retained as a deprecated compatibility flag. Use `--require-selected` only when this diagnostic process's current TIS context is the thing being checked. Use `--logs` when the visible symptom is "the input source is enabled but cannot be selected"; it prints recent KnowType app logs plus `GatekeeperPolicyScanError` and `user-preference-write com.apple.inputsources` entries from unified logging. For manual typing acceptance after diagnostics have already run, run `scripts/select-inputmethod.sh --require-selected --no-diagnose` while the target text app is active as a selection preflight, then type a real probe in that app.

The diagnostic warns when macOS resolves the input-source name to the raw bundle id. That usually means the bundle was packaged without `*.lproj/InfoPlist.strings` or the TIS cache has not refreshed. Duplicate raw TIS rows are warnings because mature IMK installers de-duplicate TIS records by input-source id and stale session cache can survive until logout or reboot. Legacy `.Mode` TIS registrations are warnings or strict failures depending on where they appear.

When `com.apple.inputsources.plist` still contains a legacy third-party row and has `com.apple.macl` or `com.apple.quarantine` extended attributes, strict diagnostics fail with a local-machine cleanup hint. That state means TIS registration is no longer the blocker; macOS is protecting or restoring the stale third-party input-source preference file, so cleanup needs Full Disk Access for Terminal/Codex or a logout/reboot before repeating System Settings remove/add.

On first local installation, macOS can show a System Settings authorization prompt asking whether to allow `知键` to enable `KnowType`. Until the user clicks Allow, TIS can report KnowType as registered and enabled while the system input menu or shortcut still falls back to another source. This is a permission gate, not a Chinese engine failure.

`knowtype-inputsource-tool dump` prints every TIS record for the KnowType bundle. Use it when the input menu shows duplicated `知键` items, the item is disabled, or selection falls back to another source; duplicated legacy mode records usually point to stale Text Input Source registration.

`scripts/repair-inputmethod-selection.sh` uses helper `purge-legacy`, `bootstrap`, `select`, and `repair-preferences` to remove legacy KnowType rows, restore the visible `.Hans` input mode, then restart `cfprefsd`, `TextInputMenuAgent`, and `TextInputSwitcher`. It repairs selected preferences only after helper-local selection is verified. It does not start the installed input-method host run loop. Use it after repeated local installs when stale `.Mode`, parent-only selected/history rows, or stale selected/history rows make the menu show duplicates or bounce back to Apple Pinyin or ABC.

`knowtype-inputsource-tool disable` remains available for manual cleanup. The local install script now uses the helper before and after replacement: it switches away from KnowType, disables existing KnowType input-source rows, restarts text-input menu agents, asks a remaining host to stop, copies the new bundle, refreshes LaunchServices for the canonical target, then uses helper migration, `bootstrap`, `purge-legacy`, and `repair-preferences` without `--include-selected` so cleanup, registration, and enablement do not launch the input-method host run loop.

CI validates the non-mutating parts of this workflow: shell syntax for all local input-method scripts, helper packaging expectations, help output for the diagnostic and selection helpers, and `scripts/build-inputmethod-bundle.sh` packaging of the executable, `Info.plist`, SwiftPM core resource bundle, and input-source icon. CI does not install or select the input method because those actions mutate runner Text Input Source state.
