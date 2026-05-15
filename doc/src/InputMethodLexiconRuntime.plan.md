# InputMethodLexiconRuntime

`InputMethodLexiconRuntime` is the input-method boundary for user-owned local lexicon resources.

- It resolves local lexicon directories through `TraditionalInputLexiconDirectoryResolver`.
- It loads existing directories through `TraditionalInputLexiconFileSource`.
- Missing directories are ignored so a fresh install stays on the bundled seed lexicon.
- The resulting catalog is converted into a `TraditionalInputEngine` and can be injected into `InputMethodPipeline` and `InputSessionController`.
- `defaultEngine()` rebuilds from the currently resolved runtime directories when requested, so later default-engine requests are not pinned to a process-start lexicon snapshot.
- The IMK controller reuses the same runtime engine for immediate local suggestions and stale/no-suggestion commit fallback, so custom lexicon entries do not disappear when the async suggestion snapshot is unavailable.

This type does not own dictionary licensing. It only wires already-authorized JSON/TSV resources into the local engine.
