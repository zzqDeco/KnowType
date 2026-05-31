# AIAcceptedLearning

`Sources/KnowTypeAI/AIAcceptedLearning.swift` owns local learning from AI
recommendations the user explicitly accepts.

It appends full accepted-AI history to Application Support JSONL, builds a
bounded language summary, and writes a readable diagnostics mirror. The full
history is local-only; provider requests receive only the accepted summary after
`LexicalProfileRuntime` merges it into `LEXICAL_PROFILE.md`.

Summary rebuilds are delayed and run on a utility task. After a rebuild is
persisted, the store emits summary-ready metadata containing only schema id,
history hash, and counts. It does not emit raw input or accepted text.

Privacy rules:

- skip the whole accepted-learning record when raw input, locked prefix, or
  accepted text contains secret-like content
- do not log accepted text or raw input
- allow ordinary technical text such as `JSON`, `API`, and `snake_case`
- never write Rime userdb or call `sync_user_data`
