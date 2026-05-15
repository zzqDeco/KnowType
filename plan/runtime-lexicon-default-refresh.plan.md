# Runtime Lexicon Default Refresh

## Summary

This fix removes the process-wide static cache from `InputMethodLexiconRuntime.defaultEngine()`.

The runtime lexicon directory path is now user-visible in settings, and users can create the directory and add JSON/TSV lexicon files without changing Swift source. A static default-engine cache would keep later default-engine requests on the first loaded directory snapshot for the lifetime of the process, which makes local lexicon iteration confusing.

## Scope

- Rebuild the default runtime engine from the currently resolved lexicon directories whenever `defaultEngine()` is requested.
- Keep explicit `InputMethodLexiconRuntime(directories:).makeEngine()` behavior unchanged.
- Keep missing directories silent.
- Add a regression test that writes a lexicon file after an initial default-engine request and verifies a later default-engine request sees it.
- Do not add active per-keystroke hot reload inside an already-created `KnowTypeInputController`; this branch only removes stale process-level default cache behavior.

## Test Plan

- `swift test --filter InputMethodLexiconRuntimeTests`
- `swift test`
- `git diff --check`
