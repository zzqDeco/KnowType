# TypingEventStore

## Responsibility

- Own the public Context Digest event-store API and the pending JSONL file at
  `events/typing-events.jsonl`.
- Maintain the process-local inventory used to make append, threshold, privacy,
  and failure-cooldown decisions without repeatedly decoding the backlog.
- Enforce pending, digest-claim, event-string, and processed-archive retention
  bounds.

## Boundaries

- Provider selection, failure cooldown, single-flight scheduling, and `ENV.md`
  updates belong to `AIContextMemoryRuntime`.
- The JSONL persistence shape remains `AITypingEvent`; this store does not add a
  sidecar or migrate existing files.
- Every successful write to `events/processed/` invokes best-effort retention
  pruning in the same process-local file-lock critical section, including local
  protected, invalid, oversized, and claim-recovery archives. Startup,
  initialization, and installation do not scan or rewrite user data when no
  archive is written.

## Behavior Notes

- Inventory entries are shared by normalized file path and are rescanned only
  when file metadata no longer matches the cached snapshot. If an existing file
  already exceeds 1 MiB, recovery first reads only a bounded suffix and rewrites
  the retained tail before inventory decoding; an oversized legacy line inside
  the 1 MiB hard limit is retained for bounded local prefix archive rather than
  provider decoding. Inventory, full-snapshot,
  prefix archive, and legacy archive safety checks use file-handle reads capped
  at the pending hard limit plus one detection byte rather than metadata or
  whole-file allocation.
- Inventory counts undecodable lines toward backlog size and prefix claims but
  excludes them from protected/unprotected event classification and provider
  request content. A protected-only backlog therefore remains local even when a
  partial JSONL line is present.
- `rawInput` and `committedText` are bounded to 2,048 Unicode scalars before
  append. Raw input and locked prefix over 4 KiB UTF-8 are never semantically
  truncated for an AI request. Diagnostics expose only removed counts and
  bytes.
- Pending data is compacted atomically to the newest 450 events and at most
  768 KiB after crossing 500 events or 1 MiB. While a digest is in flight, its
  claimed prefix is retained ahead of the newest bounded tail.
- Every processed archive write applies the 7-day, 100-file, and 10 MiB
  retention policy immediately while the existing file lock is held. Permission
  and deletion failures are best-effort cleanup failures: they do not undo the
  completed archive or make the provider call eligible for repetition.
- Digest claims contain the oldest 50 lines and at most 48 KiB, including a
  malformed record without a newline. Blank or undecodable claimed prefixes are
  archived locally and never included in provider request content. One oversized
  line is handled as a local archive unit so provider budgets are not bypassed.
- Successful prefix archive uses exact raw-byte matching so events appended
  during a digest remain pending. Claim recovery reads exactly the recorded
  byte/event prefix rather than decoding the whole pending snapshot, and a
  changed prefix returns `pendingContentChanged` for fail-closed recovery. A
  bounded legacy oversized-line archive also verifies the expected prefix
  before reading at most the pending-file limit. Deterministic processed-archive
  recovery bounded-reads the expected byte count plus one and verifies SHA-256;
  filename or metadata size alone is never completion evidence. With valid
  archive evidence, a second bounded check classifies pending as missing,
  provably different, exact, or indeterminate. Only an exact prefix is archived;
  truncated, permission-denied, and unreadable states remain fail-closed.
- Pending append, compaction, and tail rewrite paths plus deterministic
  processed archives force mode 0600. Existing pending/archive files are
  corrected before access, atomic writes protect both temporary and final
  targets, and permission failures fail closed.

## Tests

- `AIContextMemoryRuntimeTests`
- `ProviderRuntimeRegistryTests`
- `swift test`
