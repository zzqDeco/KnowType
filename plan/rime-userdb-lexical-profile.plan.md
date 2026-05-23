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
- Parse Rime `*.userdb.txt` sync snapshots rather than `.ldb` files.
- Persist canonical profile JSON under Application Support and mirror readable
  markdown to `~/.knowtype/LEXICAL_PROFILE.md`.
- Merge current Rime candidates, selection history, recent commits, and Rime
  userdb terms into a top-K lexical snapshot whose hash participates in AI cache
  keys.
- Derive the userdb snapshot name from the active Rime schema and guard writes
  with a refresh generation so stale background tasks cannot overwrite newer
  profiles.
- Repair duplicate `ENV.md` generated markers during load so polluted context
  files are cleaned before prompt use.

## Validation

- Parser, store, merge, protected-filtering, ENV repair, and coordinator
  no-hot-path-sync tests.
- Required commands: `swift test --quiet`,
  `./scripts/smoke-inputmethod-install.sh`, `./scripts/perf-input-hotpath.sh`,
  and `git diff --check`.
