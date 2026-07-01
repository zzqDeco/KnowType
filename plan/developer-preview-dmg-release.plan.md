# KnowType Developer Preview DMG Release

Status: Active

## Summary

KnowType's GitHub Release artifact now includes a Developer Preview DMG as the
default user-facing download. The DMG is not Developer ID signed or notarized,
so it remains a preview distribution for users who can explicitly allow the
build in macOS Gatekeeper.

## Delivered Behavior

- `scripts/package-dmg.sh` builds `KnowType-vX.Y.Z-macos-dev-preview.dmg`, a
  basename-only `.sha256`, and `release-manifest.json`.
- The DMG contains command-file install/uninstall entry points, `Payload/`,
  `Resources/release-manifest.json`, and the minimum scripts/helper binary
  needed to install without the source tree.
- `scripts/install-inputmethod.sh --from-dmg-payload` records
  `source=dmg-dev-preview`, release commit/tag, and manifest digest in
  `install-state.json`.
- Release workflow uploads the DMG first and keeps the local MVP zip as a
  developer/debug asset.

## Validation

- `scripts/package-dmg.sh --version 0.2.1 --build 1 --configuration release`
- `hdiutil verify dist/release/KnowType-v0.2.1-macos-dev-preview.dmg`
- `shasum -a 256 -c dist/release/KnowType-v0.2.1-macos-dev-preview.dmg.sha256`
- `./scripts/smoke-inputmethod-install.sh`
