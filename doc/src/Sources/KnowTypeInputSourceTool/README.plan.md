# KnowTypeInputSourceTool

`KnowTypeInputSourceTool` builds the `knowtype-inputsource-tool` executable used by diagnostics and manual Text Input Source registration checks.

The helper owns explicit debug TIS calls for:

- `status`: emit read-only key/value TIS status and persisted HIToolbox selected/enabled preference status for diagnostics.
- `switch-away`: debug-only fallback for moving the active input source away from KnowType; install scripts use the installed app path instead.
- `inspect-preferences` / compatibility `dedupe-preferences`: read local Text Input Source preference arrays and report duplicate KnowType rows without mutating protected system preference domains.
- `repair-preferences`: explicit local development fallback used by `scripts/repair-inputmethod-selection.sh`; removes stale parent rows from HIToolbox, removes stale `.Mode` rows from all tracked input-source preferences, restores the `.Hans` mode in HIToolbox/history, and restores the System Settings-compatible third-party parent anchor plus `.Hans` mode when `--add-active` is used.
- `bootstrap --path ... [--select]`: compatibility/debug command that registers the installed bundle only when the parent or active mode is missing, enables the active mode through TIS, skips direct enabled-preference writes, and optionally requests helper-local selection.
- `purge-legacy --path ...`: debug-only fallback for disabling stale `.Mode` TIS modes and unregistering stale LaunchServices records outside the installed path. User-facing install and repair scripts use `KnowTypeInputMethodApp --knowtype-purge-legacy`.
- `register --path ... [--select]`: compatibility alias for the bootstrap path.
- `select [--require-selected]`: debug-only helper-local selection. User-facing scripts should use the installed app's command-line selection path so macOS authorization prompts name `KnowTypeInputMethodApp`.

Scripts should call this helper instead of inline `swift -` snippets for diagnostics. Installation and normal selection still go through the installed app for TIS registration, enablement, and selection. The helper's `repair-preferences --add-active` path mirrors the rows System Settings writes on this macOS build: active `.Hans` in HIToolbox/history, and parent anchor plus `.Hans` in `com.apple.inputsources`.

The active public input-source id is `com.knowtype.inputmethod.KnowType.Hans`.
`com.knowtype.inputmethod.KnowType.Mode` is a cleanup input only and must not
appear in the packaged `Info.plist`. Activation runs from the installed app so
macOS attributes the authorization prompt to KnowType instead of the helper.

The helper deliberately labels `select` verification as helper-local. `TISSelectInputSource` can succeed inside the helper process while another app or the menu bar remains on Apple Pinyin; diagnostics therefore also read HIToolbox and `com.apple.inputsources` preferences so local acceptance does not confuse Apple Pinyin output with KnowType output.

The implementation intentionally follows mature IMK input methods such as Squirrel, OpenVanilla, and McBopomofo: registration and enablement go through `TISRegisterInputSource`, `TISEnableInputSource`, and `TISSelectInputSource`; user-facing selection is attributed to the installed app. The helper reads protected input-source preference arrays for diagnostics, and only the explicit repair command writes scoped KnowType rows.

This executable is install/debug plumbing only. It must not contain correction, candidate ranking, provider, or AI continuation logic.
