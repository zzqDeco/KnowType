# macOS IME Acceptance Harness Plan

## Summary

Add a local acceptance harness that turns the existing install, diagnostics,
selection, and manual typing runbook into one repeatable developer entry point
without claiming GUI behavior is CI-proven.

## Implementation

- Add `scripts/accept-inputmethod-local.sh` as the local harness.
- Keep the default path non-mutating: script smoke, diagnostic, report template,
  and checklist.
- Make mutating operations explicit with `--install` and `--select`.
- Generate `dist/KnowTypeLocalIMEAcceptance.md` with exact probes for TextEdit,
  Chrome/Safari, Electron/Codex-style fields, Terminal, Xcode, and provider
  failure behavior.
- Include the harness in deterministic script smoke through `--help`.

## Verification

- `swift test`
- `git diff --check`
- `./scripts/smoke-inputmethod-install.sh`
- `./scripts/accept-inputmethod-local.sh --skip-smoke --skip-diagnose --no-report --print-checklist`

## Assumptions

- The harness records manual acceptance evidence; it does not automate GUI
  typing or replace real target-app validation.
- Real install and input-source selection remain opt-in because they mutate the
  local macOS user session.
