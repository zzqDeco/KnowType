# KnowTypeInputSourceTool

`KnowTypeInputSourceTool` builds the `knowtype-inputsource-tool` executable used by local install, selection, and diagnostic scripts for Text Input Source registration.

The helper owns macOS TIS calls for:

- `status`: emit read-only key/value TIS status and persisted HIToolbox selected/enabled preference status for diagnostics.
- `switch-away`: move the active input source away from KnowType before replacing the bundle.
- `register --path ... [--select]`: register the installed input method bundle, enable parent and mode sources, and optionally request selection.
- `select [--require-selected]`: request KnowType mode selection and verify the current helper TIS context.

Scripts should call this helper instead of inline `swift -` snippets. That keeps first-run macOS permission prompts attributed to a KnowType-specific executable rather than `swift-frontend`.

The helper deliberately labels `select` verification as helper-local. `TISSelectInputSource` can succeed inside the helper process while another app or the menu bar remains on Apple Pinyin; diagnostics therefore also read HIToolbox preferences so local acceptance does not confuse Apple Pinyin output with KnowType output.

This executable is install/debug plumbing only. It must not contain correction, candidate ranking, provider, or AI continuation logic.
