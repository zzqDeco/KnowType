# KnowType v0.2.8 Developer Preview Release

## Summary

Release `v0.2.8` as a GitHub Developer Preview from the accepted `dev` branch.
Distribution remains the existing prerelease channel: Developer Preview DMG plus
local MVP zip, both unsigned and not notarized.

## Scope

- Update input method and compatibility PreferencePane short versions to
  `0.2.8`.
- Refresh README download examples from `v0.2.7` to `v0.2.8`.
- Keep `.github/workflows/release.yml` as the tag-triggered prerelease
  publisher.
- Release through a `dev` to `main` release PR, then an annotated `v0.2.8` tag
  on `main`.

## Included Changes

- Context Digest now keeps pending typing events and processed archives within
  hard event, byte, age, and file-count limits. Provider failure cooldown no
  longer repeatedly decodes the pending JSONL backlog, while provider
  generation changes and prefix claims preserve the existing retry semantics.
- InputMethodKit command-selector callbacks now consume direction and paging
  commands while punctuation or symbol candidates are active, including at
  selection boundaries, without moving the host caret or selection.

## Implementation

- Release branch: `release/0.2.8`.
- Commit message: `chore(release): prepare 0.2.8 developer preview`.
- Merge the release PR into `main` with a merge commit, not squash, so `dev`
  remains an ancestor of the release commit.
- Tag command after the release commit reaches `main`:
  `git tag -a v0.2.8 -m "KnowType v0.2.8 Developer Preview"`.
- Push the tag to trigger `.github/workflows/release.yml`.

## Test Plan

- Reuse the green current-head CI and full Swift test results from PRs `#202`
  and `#204`; do not repeat manual host typing tests during release prep.
- Require the release PR CI to pass on the exact release head.
- Require the tag workflow to run `swift build --configuration release`,
  `swift test`, both install smoke variants, release packaging, and asset upload.
- Verify the published DMG and zip checksum files plus
  `release-manifest.json` after the workflow completes.
- Run `git diff --check` for the release-only version and documentation diff.

## Manual Acceptance

- The installed release build contains both PR `#202` and PR `#204` changes.
- The user completed real-host manual acceptance after PR `#204` and directed
  the release process to continue without repeating UI typing tests.
- Preserve existing user data under `Application Support/KnowType` and
  `~/.knowtype`; do not run uninstall or repair scripts during release prep.

## Assumptions

- `v0.2.8` is a patch Developer Preview, not a notarized stable distribution.
- `CFBundleVersion` remains a build number supplied by release packaging, while
  `CFBundleShortVersionString` carries the semantic release version.
- If the tag workflow fails before a GitHub Release is created, delete and
  recreate the tag after fixing the release branch. If a published release has
  incorrect assets, ship a follow-up patch release instead of overwriting it.
