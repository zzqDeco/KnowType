# KnowType v0.2.9 Developer Preview Release

## Summary

Release `v0.2.9` as a GitHub Developer Preview from the accepted `dev` branch.
Distribution remains the existing prerelease channel: Developer Preview DMG plus
local MVP zip, both unsigned and not notarized.

## Scope

- Update input method and compatibility PreferencePane short versions to
  `0.2.9`.
- Refresh README download examples from `v0.2.8` to `v0.2.9`.
- Keep `.github/workflows/release.yml` as the tag-triggered prerelease
  publisher.
- Release through a `dev` to `main` release PR, then create an annotated
  `v0.2.9` tag on `main`.

## Included Changes

- Symbol input now uses one mutually exclusive active-session model for direct
  output, text composition, and symbol composition. Commit, cancel, focus,
  shortcut, navigation, and printable fallthrough transitions share the same
  state owner instead of a panel-only symbol session.
- Symbol candidates now preview through inline marked text or the existing
  commit-only placeholder. Exact client/composition ownership prevents stale
  cleanup, while keyboard, pointer, accessibility, and IMK lifecycle paths
  commit or cancel each symbol exactly once.

## Implementation

- Release branch: `release/0.2.9`.
- Commit message: `chore(release): prepare 0.2.9 developer preview`.
- Merge the release PR into `main` with a merge commit, not squash, so both the
  accepted `dev` history and the previous `main` release history remain
  ancestors of the release commit.
- Tag command after the release commit reaches `main`:
  `git tag -a v0.2.9 -m "KnowType v0.2.9 Developer Preview"`.
- Push the tag to trigger `.github/workflows/release.yml`.

## Test Plan

- Reuse the green exact-head CI, full Swift test, performance, and Codex review
  evidence from PRs `#209` and `#210`; do not repeat host typing tests during
  release-only metadata preparation.
- Require the release PR CI to pass on the exact release head.
- Require the tag workflow to run `swift build --configuration release`,
  `swift test`, both install smoke variants, release packaging, and asset upload.
- Verify the published DMG and zip checksum files plus
  `release-manifest.json` after the workflow completes.
- Run `git diff --check` for the release-only version and documentation diff.

## Manual Acceptance

- A local Release build from `dev@899fd70` installed successfully with
  `diagnose-inputmethod.sh --strict --json` reporting no failures or warnings.
- The user completed real-host manual typing acceptance of the symbol-session
  and marked-text changes and reported no issues.
- Preserve existing user data under `Application Support/KnowType` and
  `~/.knowtype`; do not run uninstall or repair scripts during release prep.

## Assumptions

- `v0.2.9` is a patch Developer Preview, not a notarized stable distribution.
- `CFBundleVersion` remains a build number supplied by release packaging, while
  `CFBundleShortVersionString` carries the semantic release version.
- If the tag workflow fails before a GitHub Release is created, delete and
  recreate the tag after fixing the release branch. If a published release has
  incorrect assets, ship a follow-up patch release instead of overwriting it.
