# KnowTypeInputSourceTool

`KnowTypeInputSourceTool` builds the `knowtype-inputsource-tool` executable used by diagnostics, install/rollback registration, provider-storage maintenance, and scoped Text Input Source cleanup.

The current registration model is a mode-enabled input method with one visible user mode:

- parent input method / IMK server identity: `com.knowtype.inputmethod.KnowType`
- active user-selectable input mode: `com.knowtype.inputmethod.KnowType.Hans`
- legacy cleanup mode: `com.knowtype.inputmethod.KnowType.Mode`

The helper owns explicit debug TIS calls for:

- `status`: emit read-only key/value TIS status and persisted HIToolbox selected/enabled preference status for diagnostics. `inputSource.*` describes the visible `.Hans` mode; parent fields describe the non-selectable anchor, and `legacy.mode.count` reports stale `.Mode` session-cache rows separately.
- `switch-away`: moves the active input source away from KnowType before app bundle replacement without starting the installed host. It also removes KnowType rows from HIToolbox `AppleSelectedInputSources` so stale selected preferences do not relaunch the host after install tooling refreshes TIS state.
- `inspect-preferences` / compatibility `dedupe-preferences`: read local Text Input Source preference arrays and report duplicate KnowType rows without mutating protected system preference domains.
- `repair-preferences`: explicit local development fallback used by install, rollback, uninstall, and `scripts/repair-inputmethod-selection.sh`. It removes stale `.Mode` and parent-only selected/history rows, restores enabled parent anchor plus `.Hans` mode when `--add-active` is used, and keeps selected/history pointed only at `.Hans`. `--remove-parent-anchor` is retained for uninstall cleanup after the bundle has been removed. `--legacy-parent-anchor` is accepted as a deprecated compatibility no-op.
- `bootstrap --path ... [--select]`: registers the installed bundle URL, enables the parent anchor and visible `.Hans` mode through TIS, skips direct enabled-preference writes, and optionally requests helper-local selection of `.Hans`.
- `purge-legacy --path ...`: disables stale `.Mode` TIS records and unregisters stale LaunchServices records outside the installed path.
- `register --path ... [--select]`: compatibility alias for the bootstrap path.
- `select [--require-selected]`: debug-only helper-local selection.
- `migrate-provider-profiles`: run the generation-2 provider profile migration.
- `rollback-provider-profile-migration --expected-revision ...`: roll back only
  the exact migration revision recorded by the installer.
- `downgrade-provider-profiles`: transactionally publish schema-v1 metadata
  before restoring a pre-v2 input-method bundle.

Low-level TIS source lookup, source property reads, source dedupe, activation/selection ordering, notification posting, wait helpers, and LaunchServices stale-record cleanup are delegated to `KnowTypeInputSourceSupport`. This executable owns command parsing, stdout/stderr key/value compatibility, scoped preference repair, and command exit semantics; it should not reimplement the shared TIS or LaunchServices primitives locally.

Scripts should call this helper instead of inline `swift -` snippets or the
installed app's main executable for diagnostics, registration, provider-storage
maintenance, and scoped preference cleanup. The main app retains compatible
maintenance flags for direct development use, but install, rollback, and repair
must remain helper-only so they cannot be terminated by IMK launch policy.
Manual selection still goes through `scripts/select-inputmethod.sh`. The helper
deliberately labels selection verification as helper-local because another app
or the menu bar can keep its own current input source until the user activates
that app and selects KnowType.

The implementation follows the mature IMK boundary that registration and enablement go through `TISRegisterInputSource` and `TISEnableInputSource`, while user-facing selection remains an explicit preflight before real typing. The helper reads protected input-source preference arrays for diagnostics, and only explicit repair commands write scoped KnowType rows.

This executable is install/debug plumbing only. It may call the shared
provider-storage command surface, but it must not contain correction, candidate
ranking, provider transport, or AI continuation logic.
