# KnowType v0.2.7 Developer Preview Release

## Summary

Release `v0.2.7` as a GitHub Developer Preview from the accepted `dev` branch.
Distribution remains the existing prerelease channel: Developer Preview DMG plus
local MVP zip, both unsigned and not notarized.

## Scope

- Update input method and compatibility PreferencePane short versions to
  `0.2.7`.
- Refresh README download examples from `v0.2.6` to `v0.2.7`.
- Keep `.github/workflows/release.yml` as the tag-triggered prerelease
  publisher.
- Release through a `dev` to `main` release PR, then an annotated `v0.2.7` tag
  on `main`.

## Included Changes

- Provider profiles now use revisioned, transactional cross-process updates,
  immutable Keychain references, privacy-safe diagnostics, and live runtime
  reload with stale-request cancellation and process-wide digest single-flight.
- Provider adapters use current API contracts and deterministic custom-template
  rendering, including revision-aware migration of retired official model IDs.
- InputMethodKit mouse commits and serve-only cold starts are restored, while
  install, rollback, PreferencePane replacement, and input-source selection are
  verified through explicit helpers and fail-closed integrity checks.
- Repeated-prefix repair preserves punctuation, and native Rime sessions now
  synchronize text, punctuation, and character-width modes with contextual
  quote and numeric-period behavior.
- Candidate anchoring has bounded probe budgets, scoped fallback caches, and
  throttled accessibility lookup; candidate interaction now handles host
  shortcuts, VoiceOver activation, and trackpad or wheel paging safely.
- The experimental `Option+R` rewrite workflow is fully removed. KnowType no
  longer offers an explicit polish action, and continuation remains
  prefix-locked.

## Implementation

- Release branch: `release/0.2.7`.
- Commit message: `chore(release): prepare 0.2.7 developer preview`.
- Merge release PR into `main` with a merge commit, not squash, so `dev` remains
  an ancestor of the release commit.
- Tag command after the release commit reaches `main`:
  `git tag -a v0.2.7 -m "KnowType v0.2.7 Developer Preview"`.
- Push the tag to trigger `.github/workflows/release.yml`.

## Test Plan

- `swift build --configuration release`
- `swift test`
- `./scripts/smoke-inputmethod-install.sh`
- `./scripts/smoke-inputmethod-install.sh --with-prefpane`
- `CODESIGN_IDENTITY=- ./scripts/package-release.sh --version 0.2.7 --build 1 --configuration release`
- `CODESIGN_IDENTITY=- ./scripts/package-dmg.sh --version 0.2.7 --build 1 --configuration release`
- `(cd dist/release && shasum -a 256 -c KnowType-v0.2.7-macos-dev-preview.dmg.sha256)`
- `(cd dist/release && shasum -a 256 -c KnowType-v0.2.7-macos-local-mvp.zip.sha256)`
- `git diff --check`

## Manual Acceptance

- Current `dev` was installed locally as `0.2.6 (20260713102701)` at commit
  `001ec59bbe1d3a4e378df4bc641dc700f73f28dd` before this release.
- `./scripts/diagnose-inputmethod.sh --strict` reported `0 failure(s)` after a
  reboot, with two informational TIS cache warnings and no blocking diagnosis.
- The user completed real-host manual acceptance of the installed build and
  directed the release process to continue without repeating UI typing tests.
- Preserve existing user data under `Application Support/KnowType` and
  `~/.knowtype`; do not run uninstall or repair scripts during release prep.

## Assumptions

- `v0.2.7` is a patch Developer Preview, not a notarized stable distribution.
- `CFBundleVersion` remains a build number supplied by release packaging, while
  `CFBundleShortVersionString` carries the semantic release version.
- If the tag workflow fails before a GitHub Release is created, delete and
  recreate the tag after fixing the release branch. If a published release has
  incorrect assets, ship a follow-up patch release instead of overwriting it.
