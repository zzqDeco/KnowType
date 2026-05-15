# Settings Debug Selection Guidance

## Goal

Keep the SwiftUI Debug Install tab aligned with the current local input-method workflow after the selection helper and stricter diagnostic gate were added.

## Behavior

- Move Debug Install steps and commands into `DebugInstallGuidance` so the settings UI renders a testable source of truth.
- Show `scripts/diagnose-inputmethod.sh --strict` as the read-only install status check.
- Show `scripts/diagnose-inputmethod.sh --strict --logs` for local selection-chain debugging when the input source is enabled but cannot be selected.
- Show `scripts/select-inputmethod.sh` for retrying selection without reinstalling.
- Show `scripts/select-inputmethod.sh --require-selected` as the selection preflight and direct final acceptance to a real typing probe in the target app.
- Keep the Apple Development signing install command visible for local signed testing.

## Verification

```bash
swift build
swift test
git diff --check
```
