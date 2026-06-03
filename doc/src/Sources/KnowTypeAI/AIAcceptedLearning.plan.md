# AIAcceptedLearning

`Sources/KnowTypeAI/AIAcceptedLearning.swift` owns local learning from AI
recommendations the user explicitly accepts.

It appends full accepted-AI history to Application Support JSONL, builds a
bounded language summary, and writes a readable diagnostics mirror. The full
history is local-only; provider requests receive only the accepted summary after
`LexicalProfileRuntime` merges it into `LEXICAL_PROFILE.md`.
If the accepted text is also present in the current recent-commits slice that
triggered the refresh, `LexicalContextBuilder` keeps the accepted summary as the
canonical source and filters that duplicate current commit before rendering the
request or persistent lexical context.

Summary rebuilds are delayed and run on a utility task. After a rebuild is
persisted, the store emits summary-ready metadata containing only schema id,
history hash, and counts. It does not emit raw input or accepted text.
It emits ready events only for schemas whose accepted history changed since the
previous rebuild, so schema-specific lexical profile refreshes are not retriggered
by unchanged cached summaries.

`AIAcceptedLearningMaintenance` is the non-runtime control surface for this
data. It powers `knowtype-accepted-learning-tool` and the
`scripts/accepted-learning.sh` wrapper with read-only status, explicit rebuild,
and guarded clear operations. Rebuild reuses the same summary builder used by
runtime learning. Runtime startup repair and maintenance writes share an
interprocess lock file. Clear removes accepted-learning history, summary, and
mirror files, writes a clear marker so a running store drops stale in-memory
records before the next snapshot, append, or rebuild, and scrubs accepted-AI
terms/source lines plus matching accepted recent commits from the persistent
lexical profile while preserving non-AI recent commits and tone data. If only
the markdown mirror can be scrubbed and accepted history is unavailable, clear
removes accepted-AI marker/source lines but leaves unknown recent commits alone
because their source cannot be proven. Active `LexicalProfileRuntime` instances
reload the scrubbed persistent profile, and still filter accepted-AI terms/source
lines as a fallback, before producing request-time lexical context. Clear never
touches Rime, provider profiles, Keychain data, ENV, or CORRECTION.

Privacy rules:

- skip the whole accepted-learning record when raw input, locked prefix, or
  accepted text contains secret-like content
- do not log accepted text or raw input
- allow ordinary technical text such as `JSON`, `API`, and `snake_case`
- never write Rime userdb or call `sync_user_data`
