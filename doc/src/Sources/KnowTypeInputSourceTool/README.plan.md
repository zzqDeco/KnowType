# KnowTypeInputSourceTool

`KnowTypeInputSourceTool` builds the `knowtype-inputsource-tool` executable used by local selection retries, diagnostics, and manual Text Input Source registration checks.

The helper owns macOS TIS calls for:

- `status`: emit read-only key/value TIS status and persisted HIToolbox selected/enabled preference status for diagnostics.
- `switch-away`: move the active input source away from KnowType before replacing the bundle.
- `register --path ... [--select]`: manually register the installed input method bundle, enable parent and mode sources, and optionally request selection. The default install script avoids this mutating helper path and lets the installed app perform activation from its signed bundle context.
- `select [--require-selected]`: request KnowType mode selection and verify the current helper TIS context.

Scripts should call this helper instead of inline `swift -` snippets. That keeps diagnostic and manual retry behavior attributed to a KnowType-specific executable rather than `swift-frontend`, but sandboxed hosts can still be denied `user-preference-write com.apple.inputsources`.

The helper deliberately labels `select` verification as helper-local. `TISSelectInputSource` can succeed inside the helper process while another app or the menu bar remains on Apple Pinyin; diagnostics therefore also read HIToolbox preferences so local acceptance does not confuse Apple Pinyin output with KnowType output.

This executable is install/debug plumbing only. It must not contain correction, candidate ranking, provider, or AI continuation logic.
