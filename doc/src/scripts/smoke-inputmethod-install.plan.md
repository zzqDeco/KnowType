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
