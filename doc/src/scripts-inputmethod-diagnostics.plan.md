# Input Method Diagnostic Scripts

`scripts/diagnose-inputmethod.sh` is the read-only smoke diagnostic for a locally installed KnowType input-method bundle.

It intentionally sits after `scripts/install-inputmethod.sh` in the developer loop:

1. Build and install the bundle.
2. Run the diagnostic to catch packaging, signing, Text Input Source registration, and user-data path issues.
3. Use TextEdit, browser fields, Terminal, and chat apps for real typing acceptance.

The script does not mutate macOS input-source state. It reports:

- bundle existence, executable permission, and `Info.plist` identifiers;
- packaged SwiftPM resource bundle for the seed lexicon;
- codesign verification and signing summary;
- current Text Input Source ID plus KnowType parent/mode registration and enabled status;
- `KnowTypeInputMethodApp` process status;
- provider profile, candidate history, and local lexicon directory paths.

Use `--strict` only when a failing diagnostic should block a local smoke run. Warnings remain advisory because macOS may start the input-method process only after selection/use, the selected input source may intentionally be another keyboard during debugging, and fresh installs may not have provider profiles, history, or local lexicon directories yet.
