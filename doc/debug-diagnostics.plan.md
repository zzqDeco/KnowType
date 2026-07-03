# Debug Diagnostics

KnowType debug diagnostics are opt-in and privacy-safe. They are intended for
replaying input-method timing without recording user text, candidate text,
committed text, prompts, provider output, or API keys.

## Environment Variables

| Variable | Scope |
|---|---|
| `KNOWTYPE_PERF_DEBUG=1` | Enables all performance-oriented input timing traces. |
| `KNOWTYPE_STARTUP_DEBUG=1` | Controller init, Rime prewarm, first Rime session, first composition, and first panel materialization. |
| `KNOWTYPE_INPUT_LATENCY_DEBUG=1` | Emits input latency stages over `KNOWTYPE_INPUT_LATENCY_BUDGET_MS` or 8 ms by default. |
| `KNOWTYPE_AI_DEBUG=1` | AI recommendation schedule, debounce, transport, stale-drop, and apply stages. |
| `KNOWTYPE_PANEL_DEBUG=1` | Candidate panel frame publication, window apply, layout, hide, and stale frame drops. |
| `KNOWTYPE_TURN_DEBUG=1` | Input turn effect sequence and per-effect timing. |
| `KNOWTYPE_CLIENT_WRITE_DEBUG=1` | Host write kind, bundle id, write mode, handled state, and reason. |
| `KNOWTYPE_ANCHOR_DEBUG=1` | Candidate anchor source acceptance or rejection reason. |

All debug lines use stable key/value output:

```text
KnowType debug: category=<category> stage=<stage> elapsedMs=<ms> ...
```

Allowed fields are limited to ids and metadata: `stage`, `elapsedMs`,
`budgetMs`, `turnID`, `compositionID`, `rawLength`, `rawRevision`,
`panelGeneration`, `requestID`, `provider`, `bundleID`, `writeMode`,
`anchorSource`, `handled`, and `reason`.

## Common Recipes

First-key or hot-path stalls:

```bash
launchctl setenv KNOWTYPE_PERF_DEBUG 1
launchctl setenv KNOWTYPE_STARTUP_DEBUG 1
launchctl setenv KNOWTYPE_INPUT_LATENCY_DEBUG 1
launchctl setenv KNOWTYPE_INPUT_LATENCY_BUDGET_MS 8
log stream --predicate 'subsystem == "com.knowtype.inputmethod.KnowType"' --style compact
```

AI recommendations that feel slow or interrupted:

```bash
launchctl setenv KNOWTYPE_AI_DEBUG 1
launchctl setenv KNOWTYPE_PERF_DEBUG 1
log stream --predicate 'subsystem == "com.knowtype.inputmethod.KnowType" && category == "ai"' --style compact
```

Candidate panel residue or stale frame replay:

```bash
launchctl setenv KNOWTYPE_PANEL_DEBUG 1
launchctl setenv KNOWTYPE_TURN_DEBUG 1
log stream --predicate 'subsystem == "com.knowtype.inputmethod.KnowType" && (category == "panel" || category == "turn")' --style compact
```

Host swallowing, passthrough, or marked-text write issues:

```bash
launchctl setenv KNOWTYPE_CLIENT_WRITE_DEBUG 1
launchctl setenv KNOWTYPE_ANCHOR_DEBUG 1
log stream --predicate 'subsystem == "com.knowtype.inputmethod.KnowType" && (category == "client_write" || category == "anchor")' --style compact
```

After manual testing, clear any debug environment variables and restart the
input method host:

```bash
launchctl unsetenv KNOWTYPE_PERF_DEBUG
launchctl unsetenv KNOWTYPE_STARTUP_DEBUG
launchctl unsetenv KNOWTYPE_INPUT_LATENCY_DEBUG
launchctl unsetenv KNOWTYPE_AI_DEBUG
launchctl unsetenv KNOWTYPE_PANEL_DEBUG
launchctl unsetenv KNOWTYPE_TURN_DEBUG
launchctl unsetenv KNOWTYPE_CLIENT_WRITE_DEBUG
launchctl unsetenv KNOWTYPE_ANCHOR_DEBUG
```

## Ownership

`InputDebugDiagnostics` owns environment parsing, privacy-safe key/value
formatting, elapsed timing, stderr mirroring, and unified logging output.
Feature runtimes own their diagnostic category and must not format raw debug
strings directly.

The coordinator remains the owner of IMK/Rime/AppKit side-effect execution.
Debug diagnostics observe stages and ordering; they must not affect input
handling, AI prompts, provider transport, Rime conversion, candidate ordering,
host compatibility, or install scripts.
