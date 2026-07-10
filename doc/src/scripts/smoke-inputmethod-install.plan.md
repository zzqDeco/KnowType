# scripts/smoke-inputmethod-install.sh

## Responsibility

Runs CI-safe smoke checks for local input-method scripts and bundle packaging.

## Boundaries

- The smoke script must avoid mutating CI Text Input Source state.
- It does not install, select, or type through the input method in CI.

## Behavior Notes

- It checks shell syntax, help paths, bundle packaging resources, ad-hoc signing
  smoke, and local SystemPolicyRule profile payload shape.
- Its SwiftPM Rime runtime check uses `--package-path` with the repository root
  and runs from that root as the working directory, so the smoke can be invoked
  from outside the repo working directory while still resolving source-tree Rime
  resources.
- It uses temporary install/support directories to cover install dry-run,
  install-state backup manifest creation, rollback list/dry-run, uninstall
  backup preservation, and diagnostics JSON without touching real Text Input
  Source state.
- Integrity smoke covers schema `2` metadata, checksum tampering, invalid code
  signatures even when the manifest checksum is refreshed, legacy rejection
  and explicit override visibility, foreign same-name PreferencePane refusal,
  staged rollback preflight, failed staged PreferencePane replacement, and
  shared app/pane short-version and build values.
- A self-contained packaged-DMG fixture runs the copied installer without the
  repository `Resources/InputMethod/Info.plist`, preventing source-only version
  lookup from regressing the mounted-image install command.
- Static and dry-run checks require provider-writer quiescing and the installed
  app's provider migration command to occur before LaunchServices registration.
  A temporary empty-credential fixture executes legacy-to-canonical migration
  and rollback through the bundled app with `KNOWTYPE_APP_SUPPORT_DIR`; CI does
  not access the user's real Keychain or Application Support files.
- The default run validates the primary `KnowType.app` install path. Passing
  `--with-prefpane` additionally builds and load-checks the compatibility
  `KnowType.prefPane`; CI and release workflows run that explicit compatibility
  smoke so release fallback assets stay covered without making prefPane part of
  the default local install path.
- Passing CI smoke supports packaging confidence but not host-app behavior
  claims.

## Tests

- GitHub Actions `CI` workflow
- `doc/mvp-test-acceptance-matrix.plan.md`
