# KnowTypeAI

`KnowTypeAI` owns AI capability runtime behavior that must stay outside the IMK keydown path.

Current responsibilities:

- `AIRecommendationRuntime` builds real-time provider requests from raw input, optional user-confirmed `lockedPrefix`, current-page Rime `candidateHints`, app context, `ENV.md`, `CORRECTION.md`, and optional `LEXICAL_PROFILE.md`.
- `AIRecommendationRuntime` debounces, hard-times out after 10 seconds by default, caches, sanitizes returned continuations when a locked prefix exists, and reports ready/unavailable/ineligible state through `AIRecommendationState`.
- `AIRecommendationDiagnosticSink` records request substates through macOS unified logging by default. Events carry request/composition identifiers, lengths, counts, elapsed milliseconds, and normalized reasons, but never raw input, candidate text, context document bodies, or API keys.
- `LexicalContextBuilder` produces top-K local lexical and tone summaries from current candidates, recent commits, selection history, and stored Rime userdb terms; full DB files and raw logs are not sent.
- `LexicalProfileStore` persists canonical lexical profile JSON under Application Support and mirrors readable `~/.knowtype/LEXICAL_PROFILE.md` for diagnostics.
- Input-method callers must keep Level 0/protected app commits and protected
  app selection history out of lexical profile inputs before constructing AI
  recommendation requests.
- `AIContextMemoryRuntime` records committed typing events and periodically asks the provider to summarize them into `ENV.md`.
- `TypingEventStore` stores event batches as JSONL and archives processed batches after a successful digest.
- `EnvironmentDocumentStore` creates and updates `~/.knowtype/ENV.md`, replacing only the generated section. Loaded snapshots normalize duplicate generated markers and persist the repair best-effort while still returning the repaired in-memory content if write-back fails.
- `CorrectionInstructionStore` creates `~/.knowtype/CORRECTION.md`; deterministic traditional input does not read this file.
- `AIHealthMonitor` keeps transient provider failures from hammering the provider or blocking input.

Testing concerns:

- provider requests must carry context documents; current-page Rime candidates stay contextual and must not become locked prefixes unless the user has confirmed them
- when `lockedPrefix` is absent, provider `text` is a full commit-ready recommendation, not a suffix that must be attached to the first hint
- when `lockedPrefix` is present, returned text must stay prefix-locked
- lexical profile hash changes must invalidate AI recommendation cache entries
- Rime userdb parser tests must cover malformed rows, protected-token filtering, frequency ranking, and UTF-8 Chinese terms
- protected Level 0 content must be sanitized before logging or skipped before real-time AI calls
- diagnostic tests should use an injected sink and assert stage names without relying on OSLog
- failure cooldown must suppress repeated provider calls
- context digest must preserve `User Notes` in `ENV.md`
