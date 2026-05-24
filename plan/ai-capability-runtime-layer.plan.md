# KnowType AI Capability Runtime Layer

## Summary

KnowType now treats AI as a separate capability layer instead of embedding provider continuation inside the input-method session. The Rime Chinese input path remains first and deterministic; AI owns the fixed second candidate slot and updates asynchronously after base candidates are already visible.

Default candidate order:

1. Rime candidate 1
2. AI recommendation slot
3. Rime candidate 2
4. Rime candidate 3...

`Space` and ordinary digits stay reserved for Rime input. `Tab` or explicit AI shortcuts commit the AI recommendation only when it is ready. Pending, unavailable, or ineligible AI states do not block input and do not commit mock text.

## Scope

- Add `KnowTypeAI` as an independent Swift target.
- Add `AIRecommendationRuntime` for real-time, prefix-locked recommendations.
- Add `AIContextMemoryRuntime` for background typing-event summarization.
- Add `EnvironmentDocumentStore` for `~/.knowtype/ENV.md`.
- Add `CorrectionInstructionStore` for `~/.knowtype/CORRECTION.md`.
- Add `AIHealthMonitor` with failure-count cooldown.
- Extend `LLMRequest` with `contextDigest` and `contextDocuments`.
- Update the input-method coordinator to publish local candidates first and AI slot state later.

## Runtime Files

```text
~/.knowtype/
  ENV.md
  CORRECTION.md
  events/typing-events.jsonl
  events/processed/
```

`ENV.md` stores generated context inside the guarded generated section and leaves `User Notes` for manual edits. `CORRECTION.md` is the only AI-facing correction instruction file; the deterministic traditional input engine does not read it.

Typing events are appended only after commit. Marked text is not logged. Level 0 protected content is logged as protected labels such as `protected:url` or `protected:path`.

## Non-Blocking Rules

- The keydown path updates marked text and local traditional candidates without awaiting AI.
- Real-time AI requests debounce before provider calls.
- Stale AI results are discarded by composition id, raw input, and runtime generation.
- Provider timeouts, HTTP errors, malformed responses, empty candidates, repeated prefixes, and prefix rewrites never replace traditional candidates.
- Failure cooldown stops new AI calls temporarily while keeping the second slot unavailable.

## Acceptance

- Traditional input remains usable with no provider configured.
- Provider configured: second slot shows pending, ready, unavailable, or disabled state without reordering traditional candidates.
- `Tab` / `2` commit only ready AI recommendations.
- `ENV.md` and `CORRECTION.md` are created on first AI use.
- Context digest updates only the generated section in `ENV.md` and preserves `User Notes`.
