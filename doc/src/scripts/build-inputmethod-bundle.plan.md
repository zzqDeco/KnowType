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
- If `Vendor/Rime` exists, the script copies `librime.1.dylib`, Rime plugins,
  and shared data into the app bundle before signing, and adds
  `@loader_path/../Frameworks` as a runtime search path.
- Rime rpath injection is verified before signing. Duplicate existing rpaths are
  treated as already satisfied, but any failed or missing required rpath aborts
  packaging instead of producing a bundle that cannot load native Rime.
- CI smoke checks this script without installing the bundle.

## Tests

- `scripts/smoke-inputmethod-install.sh`
- `swift test` for bundle metadata tests
