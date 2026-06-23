# KnowTypeInputSourceTool

`KnowTypeInputSourceTool` builds the `knowtype-inputsource-tool` executable used by diagnostics, install/rollback registration, and scoped Text Input Source cleanup.

The current registration model is a single non-mode-enabled input source:

- active user-selectable input source: `com.knowtype.inputmethod.KnowType`
- legacy cleanup modes: `com.knowtype.inputmethod.KnowType.Hans` and `com.knowtype.inputmethod.KnowType.Mode`

The helper owns explicit debug TIS calls for:

- `status`: emit read-only key/value TIS status and persisted HIToolbox selected/enabled preference status for diagnostics. `inputSource.*` fields describe the single active source; `legacy.mode.count` reports stale `.Hans` / `.Mode` session-cache rows separately.
- `switch-away`: moves the active input source away from KnowType before app bundle replacement without starting the installed host. It also removes KnowType rows from HIToolbox `AppleSelectedInputSources` so stale selected preferences do not relaunch the host after install tooling refreshes TIS state.
- `inspect-preferences` / compatibility `dedupe-preferences`: read local Text Input Source preference arrays and report duplicate KnowType rows without mutating protected system preference domains.
- `repair-preferences`: explicit local development fallback used by install, rollback, uninstall, and `scripts/repair-inputmethod-selection.sh`. It removes stale `.Hans` / `.Mode` rows from tracked input-source preferences and restores the single active `Keyboard Input Method` row when `--add-active` is used. `--include-history` repairs history to the single active source without reordering the current retained source unless selected repair is also requested; `--include-selected` is reserved for explicit selection repair and rewrites selected preferences to the single active source. `--remove-parent-anchor` is retained for uninstall cleanup after the bundle has been removed so enabled preferences do not keep stale single-source rows. `--legacy-parent-anchor` is accepted as a deprecated compatibility no-op.
- `bootstrap --path ... [--select]`: registers the installed bundle only when the single active source is missing, enables it through TIS, skips direct enabled-preference writes, and optionally requests helper-local selection. Install and rollback use this without `--select`; explicit repair may pass `--select`, which fails unless the helper verifies the current source changed to `com.knowtype.inputmethod.KnowType`.
- `purge-legacy --path ...`: disables stale `.Hans` / `.Mode` TIS records and unregisters stale LaunchServices records outside the installed path.
- `register --path ... [--select]`: compatibility alias for the bootstrap path.
- `select [--require-selected]`: debug-only helper-local selection.

Scripts should call this helper instead of inline `swift -` snippets for diagnostics and default install/rollback registration. Manual selection still goes through `scripts/select-inputmethod.sh`. The helper deliberately labels selection verification as helper-local because another app or the menu bar can keep its own current input source until the user activates that app and selects KnowType.

The implementation follows the mature IMK boundary that registration and enablement go through `TISRegisterInputSource` and `TISEnableInputSource`, while user-facing selection remains an explicit preflight before real typing. The helper reads protected input-source preference arrays for diagnostics, and only explicit repair commands write scoped KnowType rows.

This executable is install/debug plumbing only. It must not contain correction, candidate ranking, provider, or AI continuation logic.
