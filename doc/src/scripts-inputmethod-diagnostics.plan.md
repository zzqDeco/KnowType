# Input Method Diagnostic Scripts

`scripts/diagnose-inputmethod.sh` is the read-only smoke diagnostic for a locally installed KnowType input-method bundle. `scripts/select-inputmethod.sh` is the separate helper that requests KnowType as the current Text Input Source before a manual typing run.

It intentionally sits after `scripts/install-inputmethod.sh` in the developer loop:

1. Build and install the bundle.
2. Run the diagnostic to catch packaging, signing, Text Input Source registration, and user-data path issues.
3. Request KnowType selection with `scripts/select-inputmethod.sh` when the next step is manual typing.
4. Use TextEdit, browser fields, Terminal, and chat apps for real typing acceptance.

The script does not mutate macOS input-source state. It reports:

- bundle existence, executable permission, and `Info.plist` identifiers;
- packaged SwiftPM resource bundle for the seed lexicon;
- codesign verification and signing summary;
- current Text Input Source ID plus KnowType parent/mode registration and enabled status;
- `KnowTypeInputMethodApp` process status;
- provider profile, candidate history, and local lexicon directory paths.

Use `--strict` only when a failing diagnostic should block a local smoke run. Use `--require-selected` when the next step truly requires KnowType to be the current input source; a non-KnowType selected source or an unavailable Text Input Source query becomes a failure in that mode. Without `--require-selected`, selection status remains advisory because developers may intentionally keep another keyboard selected while inspecting installation state. Warnings remain advisory because macOS may start the input-method process only after selection/use, the selected input source may intentionally be another keyboard during debugging, and fresh installs may not have provider profiles, history, or local lexicon directories yet.

`scripts/select-inputmethod.sh` sends `TISEnableInputSource`/`TISSelectInputSource` for KnowType and then runs the diagnostic by default. It reports that selection was requested; the follow-up diagnostic is still the source of truth for whether macOS has actually switched the current input source. Passing `--require-selected` forwards that hard gate to the diagnostic.

CI validates the non-mutating parts of this workflow: shell syntax for all local input-method scripts, help output for the diagnostic and selection helpers, and `scripts/build-inputmethod-bundle.sh` packaging of the executable, `Info.plist`, SwiftPM core resource bundle, and input-source icon. CI does not install or select the input method because those actions mutate runner Text Input Source state.
