# Main Tag Release CI

## Summary

- Add the release path that promotes `dev` to `main` and publishes local MVP
  archives from annotated `vX.Y.Z` tags.
- Keep the release artifact aligned with current product status: ad-hoc signed
  local bundles, not a notarized installer, updater, or App Store package.

## Scope

- Add a tag-triggered GitHub Actions release workflow.
- Add a local release packaging script for `KnowType.app` and
  `KnowType.prefPane`.
- Let bundle builder scripts inject release version and build number into copied
  plists before signing.
- Document release gates and local MVP zip boundaries.

## Implementation

- `main` is the stable branch. `dev` remains the integration branch.
- Release tags must be annotated `vX.Y.Z` tags whose commits are on `origin/main`.
- The release workflow rejects tag/plist version mismatches before building.
- The published assets are `KnowType-vX.Y.Z-macos-local-mvp.zip`,
  its `.sha256`, and `release-manifest.json`.
- The publish job sets `GH_REPO` explicitly because it downloads artifacts
  without checking out the repository before calling `gh release create`.

## Test Plan

- `swift test`
- `./scripts/smoke-inputmethod-install.sh`
- `CODESIGN_IDENTITY=- ./scripts/package-release.sh --version 0.1.0 --build 1 --configuration release`
- `shasum -a 256 -c dist/release/*.sha256`
- `git diff --check`

## Assumptions

- No Developer ID certificate, notarization, pkg, or dmg is part of this slice.
- `CFBundleShortVersionString` remains source-controlled and must match the tag.
- `CFBundleVersion` is injected during packaging from the CI build number.
