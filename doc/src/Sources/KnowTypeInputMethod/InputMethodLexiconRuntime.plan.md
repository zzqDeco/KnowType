# InputMethodLexiconRuntime

`InputMethodLexiconRuntime` is the input-method boundary for user-owned local lexicon resources.

- It resolves local lexicon directories through `TraditionalInputLexiconDirectoryResolver`.
- It loads existing directories through `TraditionalInputLexiconFileSource`.
- Missing directories are ignored so a fresh install stays on the bundled seed lexicon.
- The resulting catalog is converted into a `TraditionalInputEngine` and can be injected into `InputMethodPipeline` and `InputSessionController`.
- `defaultEngine()` rebuilds from the currently resolved runtime directories when requested, so later default-engine requests are not pinned to a process-start lexicon snapshot.
- `snapshot()` reports directory existence and supported JSON/TSV resource metadata so the IMK frontend can refresh at new-composition boundaries without per-key reloads.
- `initialEngineState()` returns the snapshot and matching engine used by the production controller. It uses the bundled seed engine when no runtime resources exist, reuses a cached runtime engine when possible, and loads installed runtime resources before accepting the first composition when no cache is available.
- `prewarmDefaultEngine()` lets the input-method app build the default runtime engine on a utility task immediately after launch, reducing the chance that the first controller init has to load a large lexicon synchronously.
- The IMK controller reuses the same runtime engine for immediate local suggestions and stale/no-suggestion commit fallback, so custom lexicon entries do not disappear when the async suggestion snapshot is unavailable.

This type does not own dictionary licensing. It only wires already-authorized JSON/TSV resources into the local engine.
