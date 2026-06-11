# KnowTypeInputSourceTool

`KnowTypeInputSourceTool` builds the `knowtype-inputsource-tool` executable used by diagnostics, install/rollback registration, and scoped Text Input Source cleanup.

The helper owns explicit debug TIS calls for:

- `status`: emit read-only key/value TIS status and persisted HIToolbox selected/enabled preference status for diagnostics.
- `switch-away`: moves the active input source away from KnowType before app
  bundle replacement without starting the installed host. It also removes
  KnowType rows from HIToolbox `AppleSelectedInputSources` so stale selected
  preferences do not relaunch the host after install tooling refreshes TIS state.
- `inspect-preferences` / compatibility `dedupe-preferences`: read local Text Input Source preference arrays and report duplicate KnowType rows without mutating protected system preference domains.
- `repair-preferences`: explicit local development fallback used by `scripts/repair-inputmethod-selection.sh`; removes stale parent rows from HIToolbox, removes stale `.Mode` rows from all tracked input-source preferences, restores the `.Hans` mode in HIToolbox/history, and restores the System Settings-compatible third-party parent anchor plus `.Hans` mode when `--add-active` is used.
- `bootstrap --path ... [--select]`: registers the installed bundle only when the parent or active mode is missing, enables the active mode through TIS, skips direct enabled-preference writes, and optionally requests helper-local selection. Install and rollback use this without `--select`; explicit repair may pass `--select`.
- `purge-legacy --path ...`: disables stale `.Mode` TIS modes and unregisters stale LaunchServices records outside the installed path. User-facing install, rollback, and repair scripts use this helper path.
- `register --path ... [--select]`: compatibility alias for the bootstrap path.
- `select [--require-selected]`: debug-only helper-local selection. User-facing scripts should use the installed app's command-line selection path so macOS authorization prompts name `KnowTypeInputMethodApp`.

Scripts should call this helper instead of inline `swift -` snippets for diagnostics and default install/rollback registration. Manual selection can still go through the installed app when the user explicitly runs `scripts/select-inputmethod.sh`. The helper's `repair-preferences --add-active` path mirrors the rows System Settings writes on this macOS build: active `.Hans` in HIToolbox/history, and parent anchor plus `.Hans` in `com.apple.inputsources`.

The active public input-source id is `com.knowtype.inputmethod.KnowType.Hans`.
`com.knowtype.inputmethod.KnowType.Mode` is a cleanup input only and must not
appear in the packaged `Info.plist`. Default installation prepares TIS records
through the helper without launching `KnowTypeInputMethodApp` or initializing
Rime user data.

The helper deliberately labels `select` verification as helper-local. `TISSelectInputSource` can succeed inside the helper process while another app or the menu bar remains on Apple Pinyin; diagnostics therefore also read HIToolbox and `com.apple.inputsources` preferences so local acceptance does not confuse Apple Pinyin output with KnowType output.

The implementation intentionally follows mature IMK input methods such as Squirrel, OpenVanilla, and McBopomofo: registration and enablement go through `TISRegisterInputSource` and `TISEnableInputSource`, while user-facing selection remains an explicit preflight before real typing. The helper reads protected input-source preference arrays for diagnostics, and only explicit repair commands write scoped KnowType rows.

This executable is install/debug plumbing only. It must not contain correction, candidate ranking, provider, or AI continuation logic.
