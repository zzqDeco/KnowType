# InputMethodLexiconRuntime

`InputMethodLexiconRuntime` is the legacy/demo boundary for user-owned local lexicon resources.

- It resolves local lexicon directories through `TraditionalInputLexiconDirectoryResolver`.
- It loads existing directories through `TraditionalInputLexiconFileSource`.
- Missing directories are ignored so a fresh install stays on the bundled seed lexicon.
- The resulting catalog is converted into a `TraditionalInputEngine` and can be injected into `InputMethodPipeline` and `InputSessionController`.
- `defaultEngine()` rebuilds from the currently resolved runtime directories when requested, so later default-engine requests are not pinned to a process-start lexicon snapshot.
- `snapshot()` reports directory existence and supported JSON/TSV resource metadata for settings diagnostics and legacy tests.
- `initialEngineState()` returns a snapshot and matching engine for legacy package/demo callers. The production IMK controller no longer calls it after the Rime-only transition.
- `prewarmDefaultEngine()` is retained for legacy callers, but the input-method app no longer prewarms a traditional runtime engine after launch.
- The IMK controller does not use this runtime for immediate suggestions or stale/no-suggestion commit fallback; Rime owns the production conversion path.

This type does not own dictionary licensing. It only wires already-authorized JSON/TSV resources into the local engine.
