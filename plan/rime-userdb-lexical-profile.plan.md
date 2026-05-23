# KnowType Rime UserDB Lexical Profile Plan

## Status

Active.

## Summary

KnowType promotes `LEXICAL_PROFILE.md` from a per-request virtual document to a
locally maintained profile. Rime userdb sync text provides long-term word
frequency, while recent KnowType commits and selections provide short-term
preference. The profile is read by AI continuation only and stays off the IMK
keydown hot path.

## Implementation

- Extend the Rime bridge with guarded `sync_user_data`, user-data-dir, and
  sync-dir accessors.
- Resolve the active schema's Rime user dictionary name and parse its
  `*.userdb.txt` sync snapshot rather than `.ldb` files.
- Persist canonical profile JSON under Application Support and mirror readable
  markdown to `~/.knowtype/LEXICAL_PROFILE.md`.
- Merge current Rime candidates, selection history, recent commits, and Rime
  userdb terms into a top-K lexical snapshot whose hash participates in AI cache
  keys.
- Prefer the local `installation_id` sync snapshot, use deterministic fallback
  ordering for parallel sync folders, and guard writes with a refresh generation
  without holding the gate lock across filesystem writes.
- Detect the text column in metadata snapshot rows so code strings are not
  persisted as lexical terms when row order differs across Rime exports.
- Treat Rime sync as best-effort: if sync fails but a matching exported snapshot
  already exists, parse that snapshot instead of disabling profile refresh.
- Share the lexical profile store and refresh gate process-wide across IMK
  controller sessions, and merge persisted terms only when their schema matches
  the active Rime schema.
- Repair duplicate `ENV.md` generated markers during load so polluted context
  files are cleaned before prompt use; repair write-back is best-effort so reads
  still succeed on read-only or transiently restricted filesystems.

## Validation

- Parser, store, merge, protected-filtering, ENV repair, schema filtering,
  sync-failure snapshot fallback, shared IMK runtime, and coordinator
  no-hot-path-sync tests.
- Required commands: `swift test --quiet`,
  `./scripts/smoke-inputmethod-install.sh`, `./scripts/perf-input-hotpath.sh`,
  and `git diff --check`.
