# Input Method Diagnostic Scripts

`scripts/diagnose-inputmethod.sh` is the read-only smoke diagnostic for a locally installed KnowType input-method bundle. `scripts/select-inputmethod.sh` is the separate helper that requests KnowType as the current Text Input Source before a manual typing run. Both scripts resolve and run the dedicated SwiftPM executable `knowtype-inputsource-tool` for TIS operations instead of embedding `swift -` snippets.

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
- `KnowTypeInputMethodApp` process status;
- provider profile, candidate history, and local lexicon directory paths.

Use `--strict` only when a failing diagnostic should block a local smoke run. Use `--require-selected` only when this diagnostic process's current TIS context is the thing being checked. For manual typing acceptance, run `scripts/select-inputmethod.sh --require-selected` while the target text app is active as a selection preflight, then type a real probe in that app. macOS can report a different current source from a later shell diagnostic than the one applied to the frontmost text client. Without `--require-selected`, selection status remains advisory because developers may intentionally keep another keyboard selected while inspecting installation state. Warnings remain advisory because macOS may start the input-method process only after selection/use, the selected input source may intentionally be another keyboard during debugging, and fresh installs may not have provider profiles, history, or local lexicon directories yet.

The diagnostic also warns when macOS resolves the visible input-mode name to the raw mode id. That usually means the bundle was packaged without `*.lproj/InfoPlist.strings` or the TIS cache has not refreshed. Duplicate mode-registration warnings are advisory for local development; repeated installs can leave stale HIToolbox/TIS menu entries until logout or reboot.

`scripts/select-inputmethod.sh` sends `TISEnableInputSource`/`TISSelectInputSource` for KnowType through `knowtype-inputsource-tool`, polls selection in that same TIS helper process, and then runs the diagnostic by default. Passing `--require-selected` makes the in-process selection preflight a hard gate; the follow-up diagnostic remains a read-only install status check. The dedicated helper keeps macOS permission prompts from naming `swift-frontend`, which was an implementation detail of inline Swift scripts rather than the KnowType local tool.

The helper also reports `AppleSelectedInputSources` and `AppleEnabledInputSources` from `com.apple.HIToolbox`. This makes the local acceptance distinction explicit: a command-line helper can verify registration and helper-local TIS selection, but manual typing must use the active app's selected input source. If HIToolbox enabled preferences include KnowType while selected preferences still point at Apple Pinyin, the next action is to choose KnowType from the active app's input menu or System Settings, not to accept a Pinyin typing result as KnowType.

CI validates the non-mutating parts of this workflow: shell syntax for all local input-method scripts, helper packaging expectations, help output for the diagnostic and selection helpers, and `scripts/build-inputmethod-bundle.sh` packaging of the executable, `Info.plist`, SwiftPM core resource bundle, and input-source icon. CI does not install or select the input method because those actions mutate runner Text Input Source state.

After installation, `scripts/install-inputmethod.sh` prints the same separation explicitly: run the strict diagnostic for installed state, activate the target text app, run the require-selected selection preflight, then type a real probe before manual acceptance.
