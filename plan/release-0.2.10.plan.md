# KnowType v0.2.10 Developer Preview Release

Status: Active

## Summary

Release `v0.2.10` as a GitHub Developer Preview from the accepted `dev` branch
at exact base `903777cf31b7abd4f0374e8c19c468ac7ccd43d5` (`dev@903777c`).
Distribution remains the existing prerelease channel: Developer Preview DMG plus
local MVP zip, both unsigned and not notarized.

## Scope

- Update the input method and compatibility PreferencePane short versions to
  `0.2.10`, while preserving the existing `CFBundleVersion` template values.
- Refresh only the current README DMG checksum and local MVP zip installation
  examples from `v0.2.9` to `v0.2.10`.
- Carry the accepted issue `#212` implementation from PR `#213` and the test
  stability changes from PR `#214` already present in the exact `dev` base.
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
- Add one independent provenance follow-up commit with message
  `fix(ci): require release tag at main tip`; do not amend the metadata commit.
- Limit the follow-up to `.github/workflows/release.yml` and this plan.
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

## Assets and Validation Gates

- Developer Preview DMG: `KnowType-v0.2.10-macos-dev-preview.dmg` and its
  `sha256` checksum file.
- Local MVP zip: `KnowType-v0.2.10-macos-local-mvp.zip` and its checksum file.
- Workflow metadata: `release-manifest.json` accompanying the published
  assets.
- Require release PR CI to pass on the exact candidate head.
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
- Locally run only static YAML parsing, `bash -n` for the embedded validation
  shell, and `git diff --check`. Do not run `swift build`, `swift test`,
  performance tests, installation, packaging, asset generation, or publication.
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

- `v0.2.10` is a patch Developer Preview, not a notarized stable distribution.
- `CFBundleVersion` remains a build number supplied by release packaging, while
  `CFBundleShortVersionString` carries the semantic release version.
- No issue `#206` update or historical changelog is included in this candidate.
- Main-tip equality is point-in-time provenance validation; version monotonicity
  and historical tag reuse remain outside this release slice.
- If a remote gate fails before publication, repair the release process in a
  follow-up candidate; do not generate local assets or bypass the exact tag-tip
  and main-merge validation gates.
