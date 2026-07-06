# KnowType v0.2.5 Developer Preview Release

## Summary

Release `v0.2.5` as a GitHub Developer Preview from the current `dev` branch.
Distribution remains the existing prerelease channel: Developer Preview DMG plus
local MVP zip, both unsigned and not notarized.

## Scope

- Update input method and compatibility PreferencePane short versions to
  `0.2.5`.
- Refresh README download examples from `v0.2.4` to `v0.2.5`.
- Keep `.github/workflows/release.yml` as the tag-triggered prerelease
  publisher.
- Release through a `dev` to `main` release PR, then an annotated `v0.2.5` tag
  on `main`.

## Included Changes

- User-facing Settings control center with Chinese default copy, overview-first
  navigation, AI service summary, input experience controls, lexicon actions,
  privacy status, and advanced troubleshooting.
- Local input method installer hardening: quiesce existing host/input-source
  state before replacement, register only the canonical installed app path, and
  restore the existing source if source preparation or validation fails.
- Diagnostics and README guidance for canonical local installs, menu acceptance,
  and stale LaunchServices state.

## Implementation

- Release branch: `release/0.2.5`.
- Commit message: `chore(release): prepare 0.2.5 developer preview`.
- Merge release PR into `main` with a merge commit, not squash, so `dev` remains
  an ancestor of the release commit.
- Tag command after the release commit reaches `main`:
  `git tag -a v0.2.5 -m "KnowType v0.2.5 Developer Preview"`.
- Push the tag to trigger `.github/workflows/release.yml`.

## Test Plan

- `swift build --configuration release`
- `swift test`
- `./scripts/smoke-inputmethod-install.sh`
- `./scripts/smoke-inputmethod-install.sh --with-prefpane`
- `CODESIGN_IDENTITY=- ./scripts/package-release.sh --version 0.2.5 --build 1 --configuration release`
- `CODESIGN_IDENTITY=- ./scripts/package-dmg.sh --version 0.2.5 --build 1 --configuration release`
- `shasum -a 256 -c dist/release/KnowType-v0.2.5-macos-dev-preview.dmg.sha256`
- `shasum -a 256 -c dist/release/KnowType-v0.2.5-macos-local-mvp.zip.sha256`
- `git diff --check`

## Manual Acceptance

- Current `dev` was manually accepted before starting this release: the user
  confirmed the recent typing and Settings behavior, and PR #166 was validated
  with strict diagnostics after local install failure recovery.
- Release candidate acceptance should verify the real macOS input menu shows
  the `K` icon and `知键` entry after installing from the release package.
- Preserve existing user data under `Application Support/KnowType` and
  `~/.knowtype`; do not run uninstall or repair scripts unless diagnosing a
  release-candidate install issue.

## Assumptions

- `v0.2.5` is a patch Developer Preview, not a notarized stable distribution.
- `CFBundleVersion` remains a build number supplied by release packaging, while
  `CFBundleShortVersionString` carries the semantic release version.
- If the tag workflow fails before a GitHub Release is created, delete and
  recreate the tag after fixing the release branch. If a published release has
  incorrect assets, ship a follow-up patch release instead of overwriting it.
