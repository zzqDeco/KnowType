# Input Method Script CI Smoke

## Goal

Make CI cover the local InputMethodKit helper scripts that are required before manual macOS acceptance. The package tests already validate product logic, but they do not catch shell syntax errors, missing help paths, or broken bundle packaging.

## Behavior

- CI runs `bash -n` for all scripts under the local input-method workflow.
- CI exercises read-only help paths for `scripts/diagnose-inputmethod.sh` and `scripts/select-inputmethod.sh`.
- CI builds `dist/KnowType.app` with `scripts/build-inputmethod-bundle.sh`.
- CI verifies the packaged executable, `Info.plist`, SwiftPM core resource bundle, and input-source icon exist in the bundle.
- CI does not run `scripts/install-inputmethod.sh` or `scripts/select-inputmethod.sh` in mutating mode because those change Text Input Source state on the runner.

## Verification

```bash
swift build
swift test
bash -n scripts/build-inputmethod-bundle.sh scripts/diagnose-inputmethod.sh scripts/install-inputmethod.sh scripts/select-inputmethod.sh scripts/uninstall-inputmethod.sh
./scripts/diagnose-inputmethod.sh --help
./scripts/select-inputmethod.sh --help
./scripts/build-inputmethod-bundle.sh
git diff --check
```
