# KnowTypeAI

`KnowTypeAI` owns AI capability runtime behavior that must stay outside the IMK keydown path.

Current responsibilities:

- `AIRecommendationRuntime` builds real-time provider requests from raw input, optional user-confirmed `lockedPrefix`, app context, `ENV.md`, `CORRECTION.md`, and optional `LEXICAL_PROFILE.md`.
- `AIRecommendationRuntime` debounces for 350 ms by default for non-IMK direct callers, hard-times out after 10 seconds by default, caches, sanitizes returned continuations when a locked prefix exists, and reports ready/unavailable/ineligible state through `AIRecommendationState`.
- `LazyDefaultAIRecommendationRuntime` can be constructed with
  `debounceMilliseconds: 0` for the input-method path, where
  `InputAIRecommendationRuntime` owns the trailing debounce and stale-drop
  transport sequencing.
- `AIRecommendationDiagnosticSink` records request substates through macOS unified logging by default. Events carry request/composition identifiers, lengths, counts, elapsed milliseconds, and normalized reasons, but never raw input, candidate text, context document bodies, or API keys.
- `LexicalContextBuilder` produces top-K local lexical and tone summaries from recent commits, selection history, accepted AI summaries, and stored Rime userdb terms; current composition candidates, full DB files, full accepted-learning history, and raw logs are not sent. When the same accepted text appears in both accepted-AI summary and current recent commits, accepted-AI summary is the canonical source and the duplicate current commit is filtered. Input-method callers construct this context only after cheap AI schedule eligibility passes, and sanitization uses cached regular expressions.
- `LexicalProfileStore` persists canonical lexical profile JSON under Application Support and mirrors readable `~/.knowtype/LEXICAL_PROFILE.md` for diagnostics.
- `AIAcceptedLearningStore` appends full local history for AI recommendations the user explicitly accepts, writes `accepted-ai-summary.json`, and mirrors bounded diagnostics to `~/.knowtype/ACCEPTED_AI_LEARNING.md`; only the summary can feed `LEXICAL_PROFILE.md`.
- `AIRecommendationRuntime` only hard-blocks cloud AI recommendation when raw
  input or confirmed `lockedPrefix` contains secret-like credentials.
- Input-method callers keep noisy Level 0/protected app commits and protected
  app selection history out of lexical profile inputs, but those correction
  protection rules are not the cloud-AI disabled-state gate.
- `AIContextMemoryRuntime` records committed typing events and periodically asks the provider to summarize them into `ENV.md`.
- `TypingEventStore` stores event batches as JSONL and archives processed batches after a successful digest.
- `EnvironmentDocumentStore` creates and updates `~/.knowtype/ENV.md`, replacing only the generated section. Loaded snapshots normalize duplicate generated markers and persist the repair best-effort while still returning the repaired in-memory content if write-back fails.
- `CorrectionInstructionStore` creates `~/.knowtype/CORRECTION.md`; deterministic traditional input does not read this file.
- `AIHealthMonitor` keeps transient provider failures from hammering the provider or blocking input.

Testing concerns:

- provider requests must carry context documents; current-page Rime candidates must not be sent to providers or become locked prefixes unless the user has confirmed them
- when `lockedPrefix` is absent, provider `text` is a full commit-ready recommendation inferred from raw input and context, not a suffix that must be attached to a candidate hint
- no-locked-prefix real-time recommendation can trigger once raw input reaches three visible characters; locked-prefix recommendation keeps the stricter two-Han-or-six-visible-character threshold
- when `lockedPrefix` is present, returned text must stay prefix-locked
- lexical profile hash changes must invalidate AI recommendation cache entries
- Rime userdb parser tests must cover malformed rows, protected-token filtering, frequency ranking, and UTF-8 Chinese terms
- `AI 已禁用` must be reserved for secret-like raw input or locked prefixes;
  normal technical text, commands, paths, URLs, and protected app contexts stay
  eligible for real-time AI recommendation
- diagnostic tests should use an injected sink and assert stage names without relying on OSLog
- failure cooldown must suppress repeated provider calls
- context digest must preserve `User Notes` in `ENV.md`
- accepted AI learning must skip secret-like content, record only explicit AI commits, and never write Rime userdb
