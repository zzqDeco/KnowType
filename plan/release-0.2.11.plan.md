# KnowType v0.2.11 Developer Preview Release

Status: Delivered

## Summary

Release `v0.2.11` as a GitHub Developer Preview from the accepted `dev` branch
at exact base `ecaba737f05dd0fb501810fbf8df0b8df19e0928` (`dev@ecaba73`).
Distribution remains the existing prerelease channel: Developer Preview DMG plus
local MVP zip. Both use ad-hoc signing (`CODESIGN_IDENTITY=-`), are not Developer
ID signed, and are not notarized.

## Scope

- Update the input method and compatibility PreferencePane short versions to
  `0.2.11`, while preserving the existing `CFBundleVersion` template values.
- Refresh only the current README DMG checksum and local MVP zip installation
  examples from `v0.2.10` to `v0.2.11`.
- Carry the accepted Context Digest test synchronization from PR `#216` and
  Provider request-gate self-healing from PR `#218` already present in the
  exact `dev` base.
- Keep workflows, build templates, packaging logic, product implementation,
  provider protocols, input-method behavior, persistence schemas, and tests
  unchanged.
- Release through a `release/0.2.11` to `main` PR based on exact `main` base
  `cd65fe93c4eeb7ce3847c42f3bbda78f4c3f1d8b` (`main@cd65fe9`).

## Included Changes

- PR `#216` stabilizes Context Digest generation-rerun test synchronization.
- Issue `#217`, delivered by PR `#218`, replaces process-lifetime Provider gate
  persistence latches with bounded fail-closed recovery shared by real-time
  recommendations and Context Digest.

## Implementation

- Release branch: `release/0.2.11` at exact `dev@ecaba73`.
- Candidate commit message: `chore(release): prepare 0.2.11 developer preview`.
- Create one release-only candidate commit containing the two plist version
  updates, two README example updates, this plan, the previous plan status, and
  the plan-index transition.
- Merge the release PR into `main` with a merge commit, not squash, so the exact
  accepted `dev` base and previous `main` release history remain ancestors.
- Create the annotated `v0.2.11` tag only after the release merge. The tag must
  resolve exactly to that `main` merge commit, not to the release candidate.
- Use the existing tag workflow without modification to validate provenance,
  build, test, package, and publish the release assets.

## Assets And Validation Gates

- Developer Preview DMG: `KnowType-v0.2.11-macos-dev-preview.dmg` and checksum.
- Local MVP zip: `KnowType-v0.2.11-macos-local-mvp.zip` and checksum.
- Workflow metadata: `release-manifest.json` accompanying the published assets.
- Require the full `release/**` push CI run on the exact candidate head and the
  pull-request CI run on GitHub's generated `main` merge ref to pass.
- Require the annotated tag to resolve exactly to fetched `origin/main`, and
  require the tag workflow to pass release build, full tests, both install smoke
  variants, packaging, asset upload, and GitHub Release publication.
- After publication, verify all five assets, both checksums, manifest version,
  release commit provenance, and tag-to-main equality.

## Test Plan

- Reuse the accepted exact-head CI and review evidence for PRs `#216` and `#218`;
  this release candidate introduces no product behavior.
- Locally run only plist/version checks, plan/README link checks, YAML parsing,
  and `git diff --check`.
- Leave Swift build, full tests, performance, install smoke, packaging, and asset
  generation to the exact-head branch, PR, and tag workflows.

## Installation Acceptance

- After the release assets are published and verified, download the published
  DMG, verify its checksum and manifest, then install that artifact rather than
  a local build.
- Run strict diagnostics and deep code-sign validation, verify the installed
  version/build/release commit, and confirm `知键` remains registered, enabled,
  selectable, and hosted by the newly installed process.
- Preserve `Application Support/KnowType` and `~/.knowtype`; do not uninstall or
  repair user data as part of the release install.

## Assumptions

- `v0.2.11` is a patch Developer Preview using ad-hoc signing and is not a
  notarized stable distribution.
- `CFBundleVersion` remains a workflow build number, while
  `CFBundleShortVersionString` carries the semantic release version.
- Issue `#217` remains open until the published artifact is installed and its
  same-process recovery behavior is manually accepted.
- Any failed remote gate must be repaired through a new reviewed candidate; do
  not bypass exact-head CI, tag-tip validation, or asset provenance checks.
