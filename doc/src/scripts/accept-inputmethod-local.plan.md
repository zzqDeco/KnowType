# scripts/accept-inputmethod-local.sh

Runs the local IME acceptance harness for developer-machine validation. The
script keeps CI-safe preflight checks separate from actions that mutate macOS
Text Input Source state.

Responsibilities:

- run deterministic script, bundle, signing, and profile smoke checks;
- optionally install the local input method when `--install` is passed;
- optionally request target-app selection when `--select` is passed;
- run installed-bundle diagnostics with recent log hints;
- write a Markdown report template with the manual typing probes required for
  TextEdit, browser, Electron/Codex-style fields, Terminal, Xcode, and provider
  failure behavior.

The script does not drive GUI typing itself. A generated report is acceptance
evidence only after a human or Computer Use run fills in the target-app probe
results with screenshots, logs, or notes.
