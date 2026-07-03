# KnowType v0.2.4 Developer Preview Release

## Summary

Release `v0.2.4` as a GitHub Developer Preview after the input turn
sequencing hardening, debug diagnostics consolidation, and AI recommendation
placeholder fixes were manually verified from the current `dev` branch.
Distribution stays unchanged: unsigned and not notarized Developer Preview DMG
plus local MVP zip.

## Scope

- Update source bundle short versions to `0.2.4` for the input method and
  compatibility PreferencePane.
- Keep `.github/workflows/release.yml` as the tag-triggered prerelease
  publisher; it already marks Developer Preview releases as prereleases and
  avoids the `latest` marker.
- Refresh README download examples from `v0.2.3` to `v0.2.4`.
- Release through a `dev` to `main` release PR, then an annotated `v0.2.4` tag
  on `main`.

## Included Changes

- Input turn sequencing validation and privacy-safe turn diagnostics.
- Consolidated debug/performance diagnostics for input, panel, AI, startup,
  client write, and anchor paths.
- AI recommendation stability updates: input-method debounce, stale-result
  dropping, pending placeholder, and spinner-only pending row.

## Implementation

- Release PR branch: `release/0.2.4`.
- Commit message: `chore(release): prepare 0.2.4 developer preview`.
- Merge release PR into `main` with a merge commit, not squash, so `dev` remains
  an ancestor of the release commit.
- Tag command after the release commit reaches `main`:
  `git tag -a v0.2.4 -m "KnowType v0.2.4 Developer Preview"`.
- Push the tag to trigger `.github/workflows/release.yml`.

## Test Plan

- `swift build --configuration release`
- `swift test`
- `./scripts/smoke-inputmethod-install.sh`
- `./scripts/smoke-inputmethod-install.sh --with-prefpane`
- `CODESIGN_IDENTITY=- ./scripts/package-release.sh --version 0.2.4 --build 1 --configuration release`
- `CODESIGN_IDENTITY=- ./scripts/package-dmg.sh --version 0.2.4 --build 1 --configuration release`
- `shasum -a 256 -c dist/release/KnowType-v0.2.4-macos-dev-preview.dmg.sha256`
- `shasum -a 256 -c dist/release/KnowType-v0.2.4-macos-local-mvp.zip.sha256`
- `git diff --check`

## Manual Acceptance

- Installed current `dev` build was manually verified before this release plan:
  AI pending/ready behavior is visible again, spinner-only pending rows are
  acceptable, and fast candidate-panel interactions did not reproduce stale
  frame residue.
- Release candidate acceptance should repeat TextEdit, Chrome, Codex, and
  Spotlight typing checks after installing from the `v0.2.4` package.
- Preserve existing user data under `Application Support/KnowType` and
  `~/.knowtype`; do not run uninstall or repair scripts unless diagnosing a
  release-candidate install issue.

## Assumptions

- `v0.2.4` is a patch Developer Preview, not a notarized stable distribution.
- `CFBundleVersion` remains a build number supplied by release packaging, while
  `CFBundleShortVersionString` carries the semantic release version.
- If the tag workflow fails before a GitHub Release is created, delete and
  recreate the tag after fixing the release branch. If a published release has
  incorrect assets, ship a follow-up patch release instead of overwriting it.
