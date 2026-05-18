# scripts/smoke-inputmethod-install.sh

## Responsibility

Runs CI-safe smoke checks for local input-method scripts and bundle packaging.

## Boundaries

- The smoke script must avoid mutating CI Text Input Source state.
- It does not install, select, or type through the input method in CI.

## Behavior Notes

- It checks shell syntax, help paths, bundle packaging resources, ad-hoc signing
  smoke, and local SystemPolicyRule profile payload shape.
- Passing CI smoke supports packaging confidence but not host-app behavior
  claims.

## Tests

- GitHub Actions `CI` workflow
- `doc/mvp-test-acceptance-matrix.plan.md`
