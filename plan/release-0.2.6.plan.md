# KnowType v0.2.6 Developer Preview Release

## Summary

Release `v0.2.6` as a GitHub Developer Preview from the current `dev` branch.
Distribution remains the existing prerelease channel: Developer Preview DMG plus
local MVP zip, both unsigned and not notarized.

## Scope

- Update input method and compatibility PreferencePane short versions to
  `0.2.6`.
- Refresh README download examples from `v0.2.5` to `v0.2.6`.
- Keep `.github/workflows/release.yml` as the tag-triggered prerelease
  publisher.
- Release through a `dev` to `main` release PR, then an annotated `v0.2.6` tag
  on `main`.

## Included Changes

- Chinese punctuation and symbol-width policy now keeps Chinese punctuation,
  full-width symbols, and code-app ASCII defaults separate.
- Mode feedback and mature punctuator behavior add visible mode status,
  pair/list punctuation decisions, and panel-backed symbol candidates.
- `Shift+Space` now toggles half-width/full-width symbol output, while
  `Option+/` and `Option+.` remain scoped to text mode and punctuation mode.
- Transient mode status overlays are cleared or replayed before the next real
  input, candidate navigation, no-op shortcuts, and idle punctuation commits so
  mode feedback does not drift or leave stale panel state.

## Implementation

- Release branch: `release/0.2.6`.
- Commit message: `chore(release): prepare 0.2.6 developer preview`.
- Merge release PR into `main` with a merge commit, not squash, so `dev` remains
  an ancestor of the release commit.
- Tag command after the release commit reaches `main`:
  `git tag -a v0.2.6 -m "KnowType v0.2.6 Developer Preview"`.
- Push the tag to trigger `.github/workflows/release.yml`.

## Test Plan

- `swift build --configuration release`
- `swift test`
- `./scripts/smoke-inputmethod-install.sh`
- `./scripts/smoke-inputmethod-install.sh --with-prefpane`
- `CODESIGN_IDENTITY=- ./scripts/package-release.sh --version 0.2.6 --build 1 --configuration release`
- `CODESIGN_IDENTITY=- ./scripts/package-dmg.sh --version 0.2.6 --build 1 --configuration release`
- `shasum -a 256 -c dist/release/KnowType-v0.2.6-macos-dev-preview.dmg.sha256`
- `shasum -a 256 -c dist/release/KnowType-v0.2.6-macos-local-mvp.zip.sha256`
- `git diff --check`

## Manual Acceptance

- Current `dev` was installed locally as `0.2.5 (20260709165251)` before this
  release and selected successfully as `com.knowtype.inputmethod.KnowType.Hans`.
- `./scripts/diagnose-inputmethod.sh --strict` reported `0 failure(s)` after
  local install, with no stale LaunchServices records.
- The user manually accepted the latest input behavior and confirmed the
  immediate mode-switch typing path no longer shows the previously reported
  issues.
- Release candidate acceptance should verify the real macOS input menu shows
  the `K` icon and `知键` entry after installing from the release package.
- Preserve existing user data under `Application Support/KnowType` and
  `~/.knowtype`; do not run uninstall or repair scripts unless diagnosing a
  release-candidate install issue.

## Assumptions

- `v0.2.6` is a patch Developer Preview, not a notarized stable distribution.
- `CFBundleVersion` remains a build number supplied by release packaging, while
  `CFBundleShortVersionString` carries the semantic release version.
- If the tag workflow fails before a GitHub Release is created, delete and
  recreate the tag after fixing the release branch. If a published release has
  incorrect assets, ship a follow-up patch release instead of overwriting it.
