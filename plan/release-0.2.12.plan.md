# KnowType v0.2.12 Developer Preview Release

Status: Active

## Summary

Release `v0.2.12` as a GitHub Developer Preview from the accepted `dev` branch
at exact base `45133e75b3c1e943205f1285466e91fb6e57d526` (`dev@45133e7`).
Because the `v0.2.11` release merge had not been synchronized back to `dev`, the
release branch starts from integration merge
`fc9e824922dd91b953fcc1de690b6d98acadc41d` (`fc9e824`), whose parents are
exact accepted `dev@45133e7` and exact current
`main@eb67a675cc05d701f7aef89bfb1be26a979f9ad2` (`main@eb67a67`). This retains
both accepted histories. Distribution remains the existing prerelease channel:
Developer Preview DMG plus local MVP zip. Both use ad-hoc signing
(`CODESIGN_IDENTITY=-`), are not Developer ID signed, and are not notarized.

## Scope

- Update the input method and compatibility PreferencePane short versions to
  `0.2.12`, while keeping both source plist templates at `CFBundleVersion` `2`.
  Tag packaging injects GitHub `GITHUB_RUN_NUMBER` into both generated bundle
  builds and records that same value in their manifest `buildVersion` entries.
- Refresh only the current README DMG checksum and local MVP zip installation
  examples from `v0.2.11` to `v0.2.12`.
- Carry Issue `#220`, delivered by PR `#221`, the independently validated
  release-review fix delivered by PR `#223`, PR `#224`'s test-only CI
  stabilization, and PR `#225`'s completion-time cadence fix, all present in
  the exact accepted `dev` base.
- Include the accepted `v0.2.11` release history through the clean integration
  merge of exact `main@eb67a67` without changing its release contract.
- Limit the release-only commit to release metadata; do not edit workflows,
  build templates, packaging logic, product implementation, provider behavior,
  persistence schemas, or tests in that commit.
- Release through a new release PR to `main`, based on exact `main@eb67a67`.

## Included Changes

- Issue `#220`, delivered by PR `#221`, gives Context Digest a minimum six-hour
  successful cadence, at most four successful summaries in a rolling 24-hour
  window, and provider eligibility only at 50 pending events or 24 hours of
  oldest-pending age.
- The same change honors bounded 429 reset hints, persists the escalating
  no-hint 429 backoff, and preserves bounded pending backlog, claim, archive,
  cleanup, and restart-recovery behavior.
- The prior release PR `#222` GitHub Codex review found a registry
  fallback-retention P1, and an independent review validated it. PR `#223`
  fixed it at exact head `4cf2cb4dd580b826979c558c123b983c61e2f092`
  (`4cf2cb4`) and merged it into the accepted dev history.
- When request-gate persistence is blocked, the registry-backed fallback does
  not retain a typing event if the registry Provider is missing or disabled. A
  usable Provider retains only the existing prefix-protected bounded
  append-only event and starts no network request.
- After the registry lease await, recovery is revalidated: a newly installed
  claim-recovery backoff remains fail-closed, the still-blocked path preserves
  its current retry timer and append-only behavior, and ready recovery returns
  to normal append and scheduling without reviving a stale timer.
- The legacy EOF test change removes only a `JSONEncoder` key-order flake; it
  retains EOF/newline, decoded event-content, event-count, and byte-count
  semantics.
- PR `#224` changes only the cooldown-recovery test: after the second event is
  recorded, it waits for the coalesced generation rerun and then guards the
  first recorded request before inspecting it. This removes the CI
  out-of-range failure while preserving the recovery assertions; the production
  contract is unchanged.
- PR `#225`, exact head
  `1bf4affe4dbca503d6881985c841d0f8ed28b436` (`1bf4aff`), timestamps a successful
  Context Digest at the final bounded completion anchor after provider work and
  registry generation/revision waits, rather than at request start.
- The completion anchor consistently drives the receipt, rolling history,
  last-success state, pending-tail bounds, and next deadline. Provider latency
  therefore cannot shorten the six-hour interval or rolling 24-hour budget;
  unsupported clock movement fails closed before success-state mutation.
- The accepted code and automated evidence do not constitute local runtime cost
  acceptance; that remains a post-release external evidence gate.

## Implementation

- Candidate branch: `release/0.2.12-final-20260904`.
- Integration merge: `fc9e824922dd91b953fcc1de690b6d98acadc41d`
  has first parent exact accepted dev
  `45133e75b3c1e943205f1285466e91fb6e57d526` and second parent exact current main
  `eb67a675cc05d701f7aef89bfb1be26a979f9ad2`.
- Candidate commit message: `chore(release): prepare 0.2.12 developer preview`.
- Create one release-only candidate commit after the integration merge,
  containing the two plist version updates, two README example updates, this
  plan, the previous plan status, and the plan-index transition.
- The final candidate therefore contains both exact accepted `dev@45133e7` and
  exact current `main@eb67a67` release history, with candidate parent
  `fc9e824`.
- Merge the future release PR into `main` with a merge commit, not squash. The
  PR base must remain exact `main@eb67a67`.
- Create the annotated `v0.2.12` tag only after the release merge. The tag must
  resolve exactly to that `main` merge commit, not to the release candidate.
- Use the existing branch, pull-request, and tag workflows without modification
  as the remote functional validation gates.

## Assets And Validation Gates

- Developer Preview DMG: `KnowType-v0.2.12-macos-dev-preview.dmg` and
  `KnowType-v0.2.12-macos-dev-preview.dmg.sha256`.
- Local MVP zip: `KnowType-v0.2.12-macos-local-mvp.zip` and
  `KnowType-v0.2.12-macos-local-mvp.zip.sha256`.
- Workflow metadata: `release-manifest.json` accompanying the published assets.
- PR `#225` exact head `1bf4affe4dbca503d6881985c841d0f8ed28b436`
  passed pull-request CI run `33853462552`.
- Accepted merged dev `45133e75b3c1e943205f1285466e91fb6e57d526`
  passed push CI run `33854297607`.
- Those accepted-change runs establish PR `#225` and merged-dev evidence; they
  are not CI or review evidence for this release-only candidate.
- Require an independent exact-head review of the current candidate. It has not
  yet been completed.
- Require the full `release/**` push CI run on the exact candidate head and the
  pull-request CI run on GitHub's generated `main` merge ref. Neither has been
  run for the current candidate.
- Require the latest GitHub Codex review to complete against the exact current
  candidate head. No such current-candidate review is complete yet.
- Annotated tag creation, the Release workflow, published assets, checksum and
  manifest verification, installation, strict diagnostics, and runtime-cost
  manual acceptance all remain incomplete.
- Require the annotated tag to resolve exactly to fetched `origin/main`, and
  require the tag workflow to pass release build, full tests, both install smoke
  variants, packaging, asset upload, and GitHub Release publication.
- After publication, verify all five assets, both checksums, manifest version,
  release commit provenance, and tag-to-main equality. In both the DMG and local
  MVP zip, both generated bundle `CFBundleVersion` values and their corresponding
  manifest `buildVersion` entries must equal the tag Release workflow's GitHub
  run number.

## Test Plan

- Reuse the accepted code history for PRs `#221`, `#223`, and `#224`, plus the
  exact-head and merged-dev CI evidence recorded above for PR `#225`. The
  release-only commit itself changes only the seven release metadata paths;
  product changes are inherited from exact accepted dev history.
- Locally run only plan text, link, and provenance checks, plist syntax checks,
  `git diff --check`, `git show --check`, Git status, and commit-parent/path
  verification.
- Leave Swift build, full tests, performance, install smoke, packaging, and asset
  generation to the exact-head branch, PR, and tag workflows.
- Do not claim local runtime cost acceptance from static checks or remote CI.

## Installation Acceptance

- After the release assets are published and verified, download the published
  DMG, verify its checksum and manifest, then install that artifact rather than
  a local build.
- Run strict diagnostics and deep code-sign validation, verify the installed
  version/build/release commit, and confirm `知键` remains registered, enabled,
  selectable, and hosted by the newly installed process.
- Preserve `Application Support/KnowType` and `~/.knowtype`; do not uninstall,
  repair, reset, or otherwise mutate user data as part of the release install.
- Treat manual cost acceptance as a post-release external evidence gate. Using
  the published artifact, prove successful summaries are at least six hours
  apart, no rolling 24-hour window contains more than four successes, fewer
  than 50 pending events younger than 24 hours cause no provider request, 429
  reset hints are not truncated, and cooldown periods contain no periodic
  probes.

## Assumptions

- `v0.2.12` is a patch Developer Preview using ad-hoc signing and is not a
  notarized stable distribution.
- Both source plist templates retain `CFBundleVersion` `2`, while tag packaging
  uses GitHub `GITHUB_RUN_NUMBER` for both generated bundle builds and their
  manifest `buildVersion` entries. The published build number remains unknown
  until the tag Release workflow runs; `CFBundleShortVersionString` carries
  semantic release version `0.2.12`.
- Local runtime/API cost acceptance is not complete until the published
  artifact satisfies the post-release external evidence gate.
- This release does not close Issue `#206` or Issue `#217`.
- Any failed remote gate must be repaired through a new reviewed candidate; do
  not bypass exact-head CI, tag-tip validation, or asset provenance checks.
