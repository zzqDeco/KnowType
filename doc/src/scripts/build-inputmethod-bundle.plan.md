# scripts/build-inputmethod-bundle.sh

## Responsibility

Builds the local `dist/KnowType.app` InputMethodKit bundle from SwiftPM
products and repository resources.

## Boundaries

- It packages the development bundle; it is not a notarized installer.
- Input-source selection and installation are handled by separate scripts.

## Behavior Notes

- The bundle must include SwiftPM resource bundles such as
  `KnowType_KnowTypeCore.bundle`.
- Bundle metadata should match the IMK frontend shape documented in local
  acceptance docs.
- `--version` and `--build` override the copied `Info.plist` before signing so
  release artifacts can carry tag and CI build metadata without mutating source
  plists.
- CI smoke checks this script without installing the bundle.

## Tests

- `scripts/smoke-inputmethod-install.sh`
- `swift test` for bundle metadata tests
