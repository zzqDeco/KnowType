# scripts/package-dmg.sh

## Responsibility

Builds the Developer Preview DMG used as KnowType's default GitHub Release
download while Developer ID notarization is unavailable.

## Behavior Notes

- The script builds `KnowType.app`, `KnowType.prefPane`, and the
  `knowtype-inputsource-tool` helper, then stages them under a self-contained
  DMG root.
- The DMG contains `Install KnowType.command`, `Uninstall KnowType.command`,
  `Payload/`, `Resources/release-manifest.json`, `Scripts/`, and
  `README_FIRST.txt`.
- The packaged `Scripts/lib/` includes `provider_endpoint_summary.py` so text and
  JSON diagnostics keep the same endpoint-redaction contract outside the repo.
- The install command calls `scripts/install-inputmethod.sh --from-dmg-payload`
  from inside the mounted image and records `source=dmg-dev-preview`.
  This self-contained path reads version/provenance from the payload and release
  manifest rather than requiring source-tree plist files.
  It inherits the installer boundary: no input-method host launch, no automatic
  typing probe, and no Rime/user-profile initialization during install.
- The DMG is ad-hoc signed/not notarized. Gatekeeper rejection is expected for
  this preview channel and must not be described as a trusted production
  installer.
- The checksum file uses the DMG basename so `shasum -a 256 -c *.sha256` works
  in a normal download directory.

## Tests

- `scripts/package-dmg.sh --version 0.2.1 --build 1 --configuration release`
- `hdiutil verify dist/release/KnowType-v0.2.1-macos-dev-preview.dmg`
- `shasum -a 256 -c dist/release/KnowType-v0.2.1-macos-dev-preview.dmg.sha256`
- `./scripts/smoke-inputmethod-install.sh`
