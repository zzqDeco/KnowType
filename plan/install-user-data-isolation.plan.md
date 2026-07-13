# KnowType Install User Data Isolation

## Summary

- Fix the local installer so installation, rollback, and repair do not start the
  input-method host or initialize user data.
- Keep install responsibilities limited to replacing `KnowType.app`, optional
  `KnowType.prefPane`, install-state metadata, app backups, LaunchServices, and
  scoped Text Input Source registration state.

## Scope

- `scripts/install-inputmethod.sh` uses `knowtype-inputsource-tool` for
  switch-away, legacy mode cleanup, preference repair, and bootstrap.
- `scripts/rollback-inputmethod.sh` restores app/prefPane artifacts and refreshes
  registration through the helper without starting the restored app.
- `scripts/repair-inputmethod-selection.sh` remains an explicit local repair path
  and uses helper `bootstrap --select` instead of installed app activation flags.
- README, interface docs, architecture docs, and script source notes document the
  install/runtime boundary.

Non-goals:

- Do not change Rime runtime behavior, AI learning, provider prompts, candidate
  panel behavior, or release versioning.
- Do not add user-data migration, cleanup, or restoration tooling.

## Implementation

- Remove default installer calls to installed `KnowTypeInputMethodApp`
  command-line activation flags and remove background `open -g` host launch.
- Keep the app CLI flags as compatibility/debug entry points, but default local
  scripts must not call them.
- If `KnowTypeInputMethodApp` is already running, abort before build/replace
  rather than killing it. Forced shutdown can flush Rime LevelDB/user.yaml and is
  therefore not a user-data-isolated install operation.
- Register and enable the copied bundle with `knowtype-inputsource-tool
  bootstrap --path ...` without `--select`; user selection stays explicit through
  `scripts/select-inputmethod.sh` or manual macOS input menu selection.
- Treat these as protected user-data surfaces during install validation:
  `~/Library/Application Support/KnowType/AI`,
  `~/Library/Application Support/KnowType/Rime`,
  `~/Library/Application Support/KnowType/providers.v2.json`, its legacy
  migration snapshot/tombstone files, and `~/.knowtype`.

## Test Plan

- Static/unit coverage:
  - `InputMethodBundleInfoTests` asserts install/rollback/repair scripts use
    helper purge/bootstrap paths and do not call installed app activation flags
    or `open -g`.
  - `scripts/smoke-inputmethod-install.sh` repeats the same script-contract guard.
- Script checks:
  - `bash -n scripts/install-inputmethod.sh scripts/rollback-inputmethod.sh
    scripts/repair-inputmethod-selection.sh scripts/smoke-inputmethod-install.sh`
  - `./scripts/smoke-inputmethod-install.sh`
  - `./scripts/smoke-inputmethod-install.sh --with-prefpane`
  - `git diff --check`
- Local guarded acceptance:
  - Hash and back up protected user-data paths.
  - Run `./scripts/install-inputmethod.sh --configuration release`.
  - Confirm protected hashes are unchanged, diagnostics have no failures, and no
    input-method host remains from the install step.

## Assumptions

- `install-state.json`, app backup manifests, LaunchServices state, and macOS
  input-source registration state are install metadata, not language/user-data
  history.
- Rime user-data initialization after the user manually selects KnowType and
  types is normal product use, not an installer side effect.
