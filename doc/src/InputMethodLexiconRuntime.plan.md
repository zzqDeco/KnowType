# InputMethodLexiconRuntime

`InputMethodLexiconRuntime` is the input-method boundary for user-owned local lexicon resources.

- It resolves local lexicon directories from environment variables and the default Application Support location.
- It loads existing directories through `TraditionalInputLexiconFileSource`.
- Missing directories are ignored so a fresh install stays on the bundled seed lexicon.
- The resulting catalog is converted into a `TraditionalInputEngine` and can be injected into `InputMethodPipeline` and `InputSessionController`.

This type does not own dictionary licensing. It only wires already-authorized JSON/TSV resources into the local engine.
