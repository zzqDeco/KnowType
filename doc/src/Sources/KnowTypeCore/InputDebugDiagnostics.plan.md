# InputDebugDiagnostics

`InputDebugDiagnostics` is the shared debug/performance diagnostics helper for
the input-method hot path.

Current behavior:

- owns the umbrella `KNOWTYPE_PERF_DEBUG=1` switch
- preserves focused switches for startup, input latency, AI, panel, turn,
  client write, and anchor diagnostics
- emits stable key/value lines to stderr and macOS unified logging
- times synchronous operations through a small `trace` wrapper
- applies the input-latency budget from `KNOWTYPE_INPUT_LATENCY_BUDGET_MS`
  unless the umbrella perf switch is enabled
- restricts diagnostic fields to privacy-safe metadata such as ids, lengths,
  revisions, generations, reasons, elapsed times, bundle ids, write modes,
  anchor sources, probe counts, and handled state

It must not receive or format raw input, preedit, candidate text, committed
text, prompt bodies, provider output, context documents, or API keys.

Tests:

- `InputDebugDiagnosticsTests`
- `InputHotPathPerformanceTests`
