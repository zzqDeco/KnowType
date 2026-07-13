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
- Processed archives are pruned only after a successful provider digest. Startup
  and installation do not rewrite user data.

## Behavior Notes

- Inventory entries are shared by normalized file path and are rescanned only
  when file metadata no longer matches the cached snapshot. If an existing file
  already exceeds 1 MiB, recovery first reads only a bounded suffix and rewrites
  the retained tail before inventory decoding; oversized legacy records are
  discarded rather than loaded as one unbounded value.
- Inventory counts undecodable lines toward backlog size and prefix claims but
  excludes them from protected/unprotected event classification and provider
  request content. A protected-only backlog therefore remains local even when a
  partial JSONL line is present.
- Every event string is capped at 2,048 Unicode scalars. This keeps a single
  encoded record below the 256 KiB digest-request limit while diagnostics expose
  only removed scalar counts.
- Pending data is compacted atomically to the newest 450 events and at most
  768 KiB after crossing 500 events or 1 MiB. While a digest is in flight, its
  claimed prefix is retained ahead of the newest bounded tail.
- Digest claims contain the oldest 50 lines and at most 256 KiB, including a
  malformed record without a newline. Blank or undecodable claimed prefixes are
  archived locally and never included in provider request content.
- Successful prefix archive uses exact raw-byte matching so events appended
  during a digest remain pending.

## Tests

- `AIContextMemoryRuntimeTests`
- `ProviderRuntimeRegistryTests`
- `swift test`
