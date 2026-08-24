# KnowType v0.2.10 Developer Preview Release

Status: Active

## Summary

Release `v0.2.10` as a GitHub Developer Preview from the accepted `dev` branch
at exact base `903777cf31b7abd4f0374e8c19c468ac7ccd43d5` (`dev@903777c`).
Distribution remains the existing prerelease channel: Developer Preview DMG plus
local MVP zip. Both use ad-hoc signing (`CODESIGN_IDENTITY=-`), are not Developer
ID signed, and are not notarized.

## Scope

- Update the input method and compatibility PreferencePane short versions to
  `0.2.10`, while preserving the existing `CFBundleVersion` template values.
- Refresh only the current README DMG checksum and local MVP zip installation
  examples from `v0.2.9` to `v0.2.10`.
- Carry the accepted issue `#212` implementation from PR `#213` and the test
  stability changes from PR `#214` already present in the exact `dev` base.
- Add the strict `"release/**"` selector to the existing CI push branches so
  each release branch push runs the unchanged full CI job on the exact branch
  head; retain the `main`, `dev`, and pull-request selectors.
- Strengthen only the existing release validation step so the annotated tag's
  release commit must equal the fetched `origin/main` tip.
- Keep the tag trigger, build templates, packaging logic, asset publication,
  and all product, provider, input-method, and test implementation unchanged.
- Release through a `release/0.2.10` to `main` release PR based on exact
  `main` base `e7a27adcdd59c3b50e042a038635af8541091752` (`main@e7a27ad`).

## Included Changes

- Issue `#212`, delivered by PR `#213`, bounds AI request amplification through
  the accepted shared request budget, provider gate, and request lifecycle
  controls in `dev`.
- PR `#214` stabilizes context-digest timeout retry test synchronization. It is
  included as accepted test stability history and does not add a product fix in
  this release-only candidate.

## Implementation

- Release branch: `release/0.2.10` at exact `dev@903777c`.
- Release metadata commit:
  `8de68b13cc59a409137914b1cfd359c01525f2e5`
  (`chore(release): prepare 0.2.10 developer preview`).
- Release provenance commit:
  `31fbfd126805dbd2d296d2eac1e2a6f93a1b68f0`
  (`fix(ci): require release tag at main tip`).
- Add one independent release-head CI follow-up commit with message
  `fix(ci): validate release branch heads`; do not amend either prior commit.
- Limit the current follow-up to `.github/workflows/ci.yml` and this plan.
- Merge the release PR into `main` with a merge commit, not squash, so the exact
  accepted `dev` base and previous `main` release history remain ancestors.
- Create the annotated `v0.2.10` tag only after the release merge. The tag must
  resolve exactly to that `main` merge commit, not to the release branch
  candidate commit; verify `git rev-parse v0.2.10^{commit}` equals the merged
  `main` SHA.
- In the existing tag validation step, fetch `origin/main`, resolve
  `refs/remotes/origin/main`, and require its tip SHA to equal the annotated
  tag's `release_commit` exactly.
- Fail closed on any mismatch and include both the release commit and fetched
  main tip in the error. The existing tag shape, annotated-tag, plist-version,
  build, package, asset, and publish gates remain unchanged.
- Add `"release/**"` only to the existing CI `push.branches`. Its default
  checkout provides exact release branch head evidence without changing the CI
  job or steps.
- Preserve the existing `pull_request` selectors and default checkout. That run
  validates GitHub's generated main merge ref and is integration evidence, not
  a substitute for exact release branch head CI.

## Assets and Validation Gates

- Developer Preview DMG: `KnowType-v0.2.10-macos-dev-preview.dmg` and its
  `sha256` checksum file.
- Local MVP zip: `KnowType-v0.2.10-macos-local-mvp.zip` and its checksum file.
- Workflow metadata: `release-manifest.json` accompanying the published
  assets.
- Require the full `release/**` push CI run to pass on the exact release branch
  head.
- Require the pull-request CI run on GitHub's generated main merge ref to pass
  as separate integration evidence; both CI runs are release gates.
- Require tag validation to reject an annotated tag resolving to an older main
  ancestor or the release candidate instead of the fetched `origin/main` tip.
- Require a valid annotated `v0.2.10` tag at the fetched main tip to continue
  through the existing plist-version and downstream workflow gates.
- Require the tag workflow to run the release build, full Swift tests, both
  install smoke variants, release packaging, and asset upload.
- After publication, verify the DMG, zip, checksum files, manifest, and that the
  tag resolves to the `main` merge commit.

## Test Plan

- Reuse the accepted exact-head evidence for issue `#212` / PR `#213` and test
  stability PR `#214`; do not repeat host typing or product behavior testing
  during release-only metadata preparation.
- For the release-head CI follow-up, locally run only static YAML parsing,
  selector text checks, and `git diff --check`. Do not run `swift build`,
  `swift test`, performance tests, installation, packaging, asset generation,
  workflow execution, or publication.
- In the remote tag workflow, verify that an annotated tag at the fetched main
  tip passes provenance, while a tag at an older ancestor or release candidate
  fails with both SHAs in the error. Malformed, lightweight, and plist-mismatched
  tags must remain rejected by the existing gates.
- Leave functional, release-build, packaging, install-smoke, and asset checks
  to the GitHub Pipeline gates above.

## Manual Acceptance

- No new product behavior is introduced by this candidate, so no local manual
  acceptance or installation is part of release preparation.
- Preserve existing user data under `Application Support/KnowType` and
  `~/.knowtype`; do not run uninstall or repair scripts.

## Assumptions

- `v0.2.10` is a patch Developer Preview that uses ad-hoc signing
  (`CODESIGN_IDENTITY=-`), is not Developer ID signed, and is not notarized.
- `CFBundleVersion` remains a build number supplied by release packaging, while
  `CFBundleShortVersionString` carries the semantic release version.
- No issue `#206` update or historical changelog is included in this candidate.
- Main-tip equality is point-in-time provenance validation; version monotonicity
  and historical tag reuse remain outside this release slice.
- If a remote gate fails before publication, repair the release process in a
  follow-up candidate; do not generate local assets or bypass the exact tag-tip
  and main-merge validation gates.
