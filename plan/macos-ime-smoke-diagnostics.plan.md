# macOS IME Smoke Diagnostics

## Goal

Add a repeatable local diagnostic entry point for the installed KnowType input-method bundle so manual MVP acceptance can distinguish packaging, Text Input Source registration, and runtime data-path problems before Computer Use typing checks.

## Behavior

- Add `scripts/diagnose-inputmethod.sh`.
- The script is read-only by default and does not register, enable, select, kill, or reinstall the input source.
- It checks:
  - installed bundle path, executable, and `Info.plist` identifiers;
  - packaged SwiftPM core resource bundle and input-source icon;
  - `codesign --verify --deep --strict`;
  - macOS Text Input Source registration, enabled state, and currently selected input source;
  - whether `KnowTypeInputMethodApp` is running;
  - provider profile, local candidate history, and local lexicon directory paths.
- `--strict` exits non-zero when critical install, signing, registration, or enabled-state checks fail, making it usable as a local smoke gate after `./scripts/install-inputmethod.sh`.
- `--path` can inspect a specific `KnowType.app` bundle without changing the default installed bundle.

## Verification

```bash
bash -n scripts/diagnose-inputmethod.sh
./scripts/diagnose-inputmethod.sh
./scripts/install-inputmethod.sh
./scripts/diagnose-inputmethod.sh --strict
swift test
git diff --check
```
