# Input Method Diagnostic Scripts

`scripts/diagnose-inputmethod.sh` is the read-only smoke diagnostic for a locally installed KnowType input-method bundle. `scripts/select-inputmethod.sh` is the separate helper that requests KnowType as the current Text Input Source before a manual typing run. `scripts/repair-inputmethod-selection.sh` is the mutating local repair helper for stale development registration state. These scripts resolve and run the dedicated SwiftPM executable `knowtype-inputsource-tool` for TIS operations instead of embedding `swift -` snippets.

It intentionally sits after `scripts/install-inputmethod.sh` in the developer loop:

1. Build and install the bundle.
2. Run the diagnostic to catch packaging, signing, Text Input Source registration, and user-data path issues.
3. Activate the target text app, then request KnowType selection with `scripts/select-inputmethod.sh` when the next step is manual typing.
4. Use TextEdit, browser fields, Terminal, and chat apps for real typing acceptance.

The script does not mutate macOS input-source state. It reports:

- bundle existence, executable permission, and `Info.plist` identifiers;
- packaged SwiftPM resource bundle for the seed lexicon;
- codesign verification and signing summary;
- current Text Input Source ID plus KnowType parent/mode registration, enabled status, localized display name, and duplicate mode-registration count;
- parent/mode TIS type and select-capable state, because macOS may list a parent input method record that is enabled but not directly selectable;
- Gatekeeper assessment status, because an Apple Development-signed local bundle can pass `codesign --verify` but still be rejected by system execution policy;
- stale LaunchServices records for the same KnowType bundle id outside `~/Library/Input Methods/KnowType.app`;
- `KnowTypeInputMethodApp` process status;
- provider profile, candidate history, and local lexicon directory paths.

Use `--strict` only when a failing diagnostic should block a local smoke run. Use `--require-selected` only when this diagnostic process's current TIS context is the thing being checked. Use `--logs` when the visible symptom is "the input source is enabled but cannot be selected"; it prints recent KnowType app logs plus `GatekeeperPolicyScanError` and `user-preference-write com.apple.inputsources` entries from unified logging. For manual typing acceptance after diagnostics have already run, run `scripts/select-inputmethod.sh --require-selected --no-diagnose` while the target text app is active as a selection preflight, then type a real probe in that app. macOS can report a different current source from a later shell diagnostic than the one applied to the frontmost text client. Without `--require-selected`, selection status remains advisory because developers may intentionally keep another keyboard selected while inspecting installation state. Warnings remain advisory because macOS may start the input-method process only after selection/use, the selected input source may intentionally be another keyboard during debugging, and fresh installs may not have provider profiles, history, or local lexicon directories yet.

The diagnostic also warns when macOS resolves the visible input-mode name to the raw mode id. That usually means the bundle was packaged without `*.lproj/InfoPlist.strings` or the TIS cache has not refreshed. Duplicate mode-registration warnings are advisory for local development; repeated installs can leave stale HIToolbox/TIS menu entries until logout or reboot.

When Gatekeeper rejects an Apple Development build on macOS 15+, the diagnostic points to `scripts/create-local-system-policy-profile.sh --open`. That helper reads the installed bundle's designated code requirement and writes a device `com.apple.systempolicy.rule` configuration profile for manual System Settings installation. It does not install the profile itself because modern macOS no longer permits configuration-profile installation through the `profiles` CLI. After the profile is installed, `spctl --assess --type execute` should accept the bundle before a typing result is treated as KnowType acceptance.

`scripts/select-inputmethod.sh` sends `TISEnableInputSource`/`TISSelectInputSource` for KnowType through `knowtype-inputsource-tool`, polls selection in that same TIS helper process, and then runs the diagnostic by default. Passing `--require-selected` makes the in-process selection preflight a hard gate; the follow-up diagnostic remains a read-only install status check. The helper remains useful from a normal developer terminal, but it is not treated as the install path source of truth because sandboxed hosts such as Codex can trigger `user-preference-write com.apple.inputsources` denials.

The helper also reports `AppleSelectedInputSources` and `AppleEnabledInputSources` from `com.apple.HIToolbox`. This makes the local acceptance distinction explicit: a command-line helper can verify registration and helper-local TIS selection, but manual typing must use the active app's selected input source. If HIToolbox enabled preferences include KnowType while selected preferences still point at Apple Pinyin, the next action is to choose KnowType from the active app's input menu or System Settings, not to accept a Pinyin typing result as KnowType.

On first local installation, macOS can show a System Settings authorization
prompt asking whether to allow `知键` to enable `KnowType`. Until the user
clicks Allow, TIS can report KnowType as registered and enabled while the
system input menu or shortcut still falls back to another source. This is a
permission gate, not a Chinese engine failure.

When HIToolbox enabled preferences include KnowType, `TISSelectInputSource` returns success in the app context, and `AppleSelectedInputSources` still remains on Apple Pinyin, the diagnostic treats this as an input-source selection-chain problem rather than an engine problem. The two log patterns that matter most are `GatekeeperPolicyScanError Code=-67018`, which means system policy has not allowed the locally signed bundle, and `user-preference-write com.apple.inputsources`, which means a sandboxed helper attempted to mutate Text Input Source preferences.

`knowtype-inputsource-tool dump` prints every TIS record for the KnowType bundle. Use it when the input menu shows `知键` but the item is disabled or selection falls back to another source; duplicated mode records or a parent-only selectable path usually point to stale Text Input Source registration.

`scripts/repair-inputmethod-selection.sh` backs up `com.apple.HIToolbox` and `com.apple.inputsources`, unregisters stale LaunchServices records for old KnowType build paths, runs `knowtype-inputsource-tool dedupe-preferences`, restarts `cfprefsd`, `TextInputMenuAgent`, `TextInputSwitcher`, and `KnowTypeInputMethodApp`, then relaunches the installed app with `--knowtype-install-activate`. Use it after repeated local installs when the menu can see KnowType but selection bounces back to Apple Pinyin or ABC.

`knowtype-inputsource-tool disable` remains available for manual cleanup, but the local install script no longer disables or selects through the command-line helper. It copies the new bundle, then launches `KnowType.app --knowtype-install-activate` so registration, enabling, and the best-effort selection request run from the installed app context.

`KnowTypeInputMethodApp` registers its input source on launch only when TIS has no existing KnowType sources, then enables one unique parent and visible mode from the signed app bundle context. With `--knowtype-install-activate`, it also requests selection and logs both the `TISSelectInputSource` status and the app-local current input source. That app-context enablement is intentionally separate from the command-line helper because modern macOS can treat helper-local TIS selection as a preflight that does not prove the menu item is selectable in the active app. Avoiding unconditional registration and deduplicating enable requests both reduce stale duplicate mode rows during repeated local installs.

CI validates the non-mutating parts of this workflow: shell syntax for all local input-method scripts, helper packaging expectations, help output for the diagnostic and selection helpers, and `scripts/build-inputmethod-bundle.sh` packaging of the executable, `Info.plist`, SwiftPM core resource bundle, and input-source icon. CI does not install or select the input method because those actions mutate runner Text Input Source state.

After installation, `scripts/install-inputmethod.sh` prints the same separation explicitly: run the strict diagnostic for installed state, activate the target text app, run the require-selected selection preflight, then type a real probe before manual acceptance.
