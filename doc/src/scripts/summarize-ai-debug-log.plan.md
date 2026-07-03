# summarize-ai-debug-log.py

## Responsibility

- Summarizes privacy-safe KnowType AI debug log exports for local diagnosis.
- Counts AI diagnostic stages, reasons, provider-health signals, selected
  transport/cancellation samples, and `handle_key_total` latency percentiles.

## Boundaries

- This helper consumes existing log text only; it does not read runtime state,
  change input-method behavior, query providers, or inspect user data stores.
- It must not print raw input, candidate text, committed text, prompt/context
  bodies, provider output, or API keys. Output stays limited to existing
  metadata such as ids, lengths, revisions, stages, reasons, providers, and
  elapsed times.

## Behavior Notes

- Missing log paths fail clearly with a nonzero exit code; empty logs succeed
  with zero events so scripted checks can distinguish collection failures from
  no-event captures.
- Provider-health signals treat `provider_error`, `timeout`, and
  `cooldown_active` as separate indicators. Localized unavailable reasons such
  as `AI_暂不可用` also count as unavailable without requiring English text.
- Transport samples are drawn from diagnostic metadata fields only and never
  echo the original log line.

## Tests

- `AIDebugLogSummaryScriptTests`
- `python3 scripts/summarize-ai-debug-log.py Tests/Fixtures/ai-debug-cancellation.log`
