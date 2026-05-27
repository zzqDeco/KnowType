# KnowType Accepted AI Learning

Status: Active

## Summary

KnowType records AI recommendations the user explicitly accepts through Tab,
Option-number, or the AI row as local accepted-learning history. The full history
stays on the user's machine; provider requests receive only bounded summaries
through `LEXICAL_PROFILE.md`.

This work does not write Rime userdb, call `sync_user_data`, import user
dictionaries, or change Rime candidate ranking.

## Implementation

- Add `AIAcceptedLearningStore` under `KnowTypeAI`.
- Append full accepted AI records to Application Support JSONL.
- Save `accepted-ai-summary.json` and a readable
  `~/.knowtype/ACCEPTED_AI_LEARNING.md` mirror.
- Skip entire records when raw input, locked prefix, or accepted text contains
  secret-like content.
- Extract bounded accepted terms and style signals for lexical profile merging.
- Wire `InputControllerCoordinator` so only AI commits are recorded; native Rime,
  raw passthrough, symbols, and external deletes are not.
- Merge accepted-learning summaries into `LexicalProfileRuntime` without reading
  or writing Rime userdb on the key path.

## Test Plan

- AI Tab and Option-number accepted commits write accepted-learning records.
- Native Rime commits and idle passthrough do not write accepted-learning records.
- Secret-like accepted text is skipped.
- Technical terms such as `JSON`, `API`, and `snake_case` can appear in accepted
  summaries while full history stays out of `LEXICAL_PROFILE.md`.
- Accepted summary hash changes participate in lexical profile cache invalidation.
- Regression: `swift test --quiet`,
  `./scripts/smoke-inputmethod-install.sh`,
  `./scripts/perf-input-hotpath.sh`, and `git diff --check`.

## Assumptions

- Full accepted history is local-only and not injected directly into provider
  prompts.
- Rime promotion is a separate future opt-in feature.
- Secret-like content is not stored; ordinary technical text is allowed.
