# AIAcceptedLearning

`Sources/KnowTypeAI/AIAcceptedLearning.swift` owns local learning from AI
recommendations the user explicitly accepts.

It appends accepted-AI history to Application Support JSONL under a bounded
sliding-window capacity (`maxRecordCount`, defaulting to
`AIAcceptedLearningStore.defaultMaxRecordCount = 500` and clamped to at least
`1`), builds a bounded language summary over the retained window, and writes a
readable diagnostics mirror. When `append(_:)` or startup loading observes more
than `maxRecordCount` records, the store reloads the authoritative locked
on-disk history before trimming `records` to the latest `maxRecordCount`
entries, records SHA-256 digests of evicted commit text variants in
`accepted-ai-learning.evicted-commits.json` (bounded to 4,096 entries during
normal compaction; clear can temporarily fold in active-record digests)
so maintenance `clear` can still scrub older accepted commits from
`LEXICAL_PROFILE.md`, atomically rewrites the compacted
`accepted-ai-learning.jsonl` file, and marks any evicted schemas alongside the
appended schema for summary rebuild. The retained sliding-window history and
evicted-commit digest ledger are local-only; provider requests receive only the
accepted summary after `LexicalProfileRuntime` merges it into
`LEXICAL_PROFILE.md`.
If the accepted text is also present in the current recent-commits slice that
triggered the refresh, `LexicalContextBuilder` keeps the accepted summary as the
canonical source and filters that duplicate current commit before rendering the
request or persistent lexical context.

Summary rebuilds are delayed and run on a utility task. Each rebuild reloads the
authoritative on-disk history under the interprocess file lock so a delayed
rebuild cannot overwrite a newer store's compacted state, renders the diagnostics
mirror with the configured `maxRecordCount` retention capacity, and synchronizes
other live stores sharing `historyURL` (while `snapshot()` / `snapshot(schemaID:)`
also detect on-disk history signature changes across processes). After a rebuild
or peer synchronization is applied, the store emits summary-ready metadata
containing only schema id, history hash, and counts (including a zero-count
invalidation event when a schema's last record is evicted by compaction). It
does not emit raw input or accepted text. It emits ready events only for schemas
whose accepted history changed since the previous rebuild, so schema-specific
lexical profile refreshes are not retriggered by unchanged cached summaries.
If append first applies an external history change and then fails to encode,
append, or compact its local record, those external events are still delivered
once on the failure exit, after both locks are released. This includes changed
schemas with surviving records, not only zero-count invalidations; subsequent
reads with already-current disk metadata do not need to rediscover the change.

Runtime store construction is read-only when history is missing or within
`maxRecordCount`, provided no existing markdown mirror requires refresh or
removal. Missing history, summary, mirror, and clear-marker files do not create
the AI directory, lock file, or markdown mirror. If a persisted summary is stale
and no existing mirror requires repair, startup rebuilds the in-memory snapshot
and leaves persistent summary repair to explicit record/rebuild paths or startup
compaction; when an existing JSONL file exceeds `maxRecordCount` or an existing
markdown mirror does not match the active summary and configured
`maxRecordCount` (including an orphaned mirror left behind when history is
missing or empty), startup acquires the interprocess file lock (creating the
lock file if necessary) to compact the history/summary/mirror or refresh/remove
the existing mirror on disk, and retries that repair on subsequent reads (with
bounded monotonic backoff) if startup persistence failed transiently. Startup
reads always participate in the in-process accepted-learning lock and also join
an existing accepted-learning maintenance file lock when another process has
already created one, so concurrent append/rebuild/clear operations are observed
consistently without making missing-history cold start create a lock file of its
own when no existing mirror cleanup is needed.

Runtime history reads require every nonblank JSONL row to decode as an
`AIAcceptedLearningRecord`. A malformed or forward-incompatible complete row
blocks append, delayed rebuild, and startup compaction rather than letting a
partial decode silently replace the original history. Read/write diagnostics
contain only the error type, not row contents. Existing cached state is retained
on a failed read; a cold start without cached records defers repair instead of
learning from a partial history. After an external repair restores decodable
rows, normal sliding-window compaction resumes (startup repair also retries
when the file metadata changes). Blank and whitespace-only lines are ignored.
A complete final JSON row may lack LF. After the whole history decodes, fast
append checks the final byte under the file lock and prefixes the new row with
LF when needed, without rewriting existing bytes. A genuinely truncated EOF row
still blocks append unchanged, with or without a trailing LF.

`AIAcceptedLearningMaintenance` is the non-runtime control surface for this
data. It powers `knowtype-accepted-learning-tool` and the
`scripts/accepted-learning.sh` wrapper with read-only status, explicit rebuild,
and guarded clear operations. Rebuild applies the same `maxRecordCount` sliding
window and summary builder used by runtime learning. Maintenance writes share an
interprocess lock file. Before changing the ledger or deleting history, clear
atomically snapshots all required scrub entries into the optional
`pendingEvictedCommitEntries` array in `accepted-ai-learning.clear.json`.
Failure to persist that pin leaves ledger, history, and other learning files
unchanged; it creates no new durable recovery snapshot, and subsequent ordinary
ledger rotation still follows the normal bounded policy. Once the pin is durable,
clear folds active records into the eviction ledger (temporarily allowing the
pre-clear 4,096 digests plus active-window digests until scrub completes). A
later failure still synchronizes peer stores outside the file lock; the marker
requests a reload of actual disk history, not an assumption that clear completed.
This extends the existing schema-version-1
marker (`schemaVersion`, `clearedAt`); older markers without the array remain
readable. New entries are commit digests, while inherited legacy ledger entries
retain their matching semantics. Ordinary appends never mutate the marker, so
the pinned snapshot survives subsequent ledger rotation back to 4,096 entries.
A retried clear unions prior pins, the current ledger, and active-record
digests. The clear marker also makes a running store drop stale records before
the next snapshot, append, or rebuild. Clear scrubs accepted-AI terms/source
lines plus matching accepted recent commits (including both active and previously
evicted commits recorded in the ledger) from the persistent lexical profile
while preserving non-AI recent commits and tone data, and removes
`accepted-ai-learning.evicted-commits.json` only after the lexical profile scrub
succeeds. Only then is the marker rewritten without its pending array. A
failure, including one while finalizing that marker, leaves the pins available
for another clear; they are retry state, not an ever-growing ordinary eviction
ledger. Rebuild refuses undecodable nonblank history rows with
`AIAcceptedLearningMaintenance.Error.undecodableHistoryRows` before changing
history, ledger, or summaries; read-only status still reports
`invalid_history_lines:<count>`. Explicit confirmed clear remains destructive
and may delete undecodable history rows; it does not claim to decode or scrub
unknown row contents. An unreadable retry marker aborts clear rather than
discarding pending entries. If only the markdown mirror can be scrubbed and
accepted history is unavailable, clear removes accepted-AI marker/source lines but leaves
unknown recent commits alone because their source cannot be proven. Active
`LexicalProfileRuntime` instances reload the scrubbed persistent profile, and
still filter accepted-AI terms/source lines as a fallback, before producing
request-time lexical context. Clear never touches Rime, provider profiles,
Keychain data, ENV, or CORRECTION.

Privacy rules:

- skip the whole accepted-learning record when raw input, locked prefix, or
  accepted text contains secret-like content
- do not log accepted text or raw input
- allow ordinary technical text such as `JSON`, `API`, and `snake_case`
- never write Rime userdb or call `sync_user_data`

`Sources/KnowTypeAI/AIAcceptedFeedbackLearning.swift` owns the separate
negative-signal data path. It records only verified post-accept edits supplied
by the input-method tracker, builds a bounded feedback summary, and renders
`AI_FEEDBACK.md` for provider requests. The summary is a soft style signal that
can lower the chance of repeated deleted phrases or overly long continuations;
it never turns ordinary Backspace events into feedback, never exposes full edit
history to providers, never writes Rime userdb, and does not create feedback
files during cold-start snapshot reads when no feedback history exists. Feedback
snapshot reads always participate in the in-process feedback lock and also honor
an already existing feedback maintenance file lock before checking clear
markers, preventing stale feedback from leaking across an active clear while
keeping missing-history cold start read-only.
