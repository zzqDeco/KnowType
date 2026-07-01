# scripts/package-release.sh

## Responsibility

Builds the local MVP GitHub Release artifact set: a zip containing
`KnowType.app` and the compatibility `KnowType.prefPane`, a SHA256 file, and
`release-manifest.json`. The user-facing GitHub Release download is the
Developer Preview DMG from `scripts/package-dmg.sh`; this zip remains a
developer/debug asset.

## Boundaries

- It creates local MVP archives only; it must not claim notarization, installer,
  updater, or App Store distribution behavior.
- It does not package a standalone `KnowType Settings.app`; user settings are
  opened from the input-method menu.
- Installation and target-app typing acceptance remain owned by the local install
  and acceptance scripts.

## Behavior Notes

- The script injects `CFBundleShortVersionString` and `CFBundleVersion` through
  the existing bundle builders, then verifies both packaged bundles with
  `codesign --verify --deep --strict`.
- The zip is named `KnowType-vX.Y.Z-macos-local-mvp.zip`.
- The manifest records tag, commit, Swift version, artifact names, bundle
  identifiers, short versions, and build versions.
- `release-manifest.json` is written beside the archive and copied into the zip
  staging directory so `scripts/install-inputmethod.sh --from-release-zip` can
  record release source metadata after download.
- The checksum file uses the archive basename so direct download-directory
  verification works with `shasum -a 256 -c`.

## Tests

- `scripts/package-release.sh --version 0.1.0 --build 1 --configuration release`
- `shasum -a 256 -c dist/release/*.sha256`
- `.github/workflows/release.yml`
