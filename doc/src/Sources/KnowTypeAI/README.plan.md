# KnowTypeAI

`KnowTypeAI` owns AI capability runtime behavior that must stay outside the IMK keydown path.

Current responsibilities:

- `AIRecommendationRuntime` builds real-time prefix-locked provider requests from raw input, the traditional first candidate, app context, `ENV.md`, and `CORRECTION.md`.
- `AIRecommendationRuntime` debounces, hard-times out, caches, sanitizes returned continuations, and reports ready/unavailable/ineligible state through `AIRecommendationState`.
- `AIContextMemoryRuntime` records committed typing events and periodically asks the provider to summarize them into `ENV.md`.
- `TypingEventStore` stores event batches as JSONL and archives processed batches after a successful digest.
- `EnvironmentDocumentStore` creates and updates `~/.knowtype/ENV.md`, replacing only the generated section.
- `CorrectionInstructionStore` creates `~/.knowtype/CORRECTION.md`; deterministic traditional input does not read this file.
- `AIHealthMonitor` keeps transient provider failures from hammering the provider or blocking input.

Testing concerns:

- provider requests must carry context documents and stay prefix-locked
- protected Level 0 content must be sanitized before logging or skipped before real-time AI calls
- failure cooldown must suppress repeated provider calls
- context digest must preserve `User Notes` in `ENV.md`
