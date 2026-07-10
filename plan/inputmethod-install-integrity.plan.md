# Input Method Install Integrity

Status: Active

## Summary

- Make local install backups fail closed when rollback integrity or identity
  cannot be established.
- Protect a same-name foreign PreferencePane from install, uninstall, rollback,
  and failed-install recovery while preserving the existing IMK registration
  and user-data boundaries.

## Scope

- Upgrade the install backup manifest and rollback preflight.
- Share canonical PreferencePane path and bundle-identity guards across all
  destructive installer paths.
- Keep locally built app and PreferencePane version/build metadata aligned.
- Replace stale release numbers in settings diagnostics guidance.
- Do not change input-source IDs, registration order, selection policy, or any
  Rime/provider/learning/user-data persistence behavior.

## Implementation

- Backup manifest schema `2` records app checksum, bundle identifier, short
  version, build version, designated signing requirement, and normalized
  signing identity. When a pane is included, the same fields are required for
  `KnowType.prefPane`; otherwise every pane integrity field is explicitly null.
- Rollback validates manifest shape and backup ID, artifact presence, checksum,
  bundle ID, short version/build, signing requirement/identity,
  `codesign --verify --deep --strict`, and the staged copy before removing an
  installed artifact.
- Schema `1` backups are rejected by default. The explicit
  `--allow-unverified-backup` option applies only to schema `1`, emits prominent
  warnings, remains visible in dry-run output, and still requires structurally
  valid self-consistent code signatures. It cannot bypass schema `2` failures.
- PreferencePane removal is restricted to the canonical local
  `KnowType.prefPane`, rejects symlinks, and requires
  `CFBundleIdentifier=com.knowtype.preferencepane`.
- PreferencePane install and failed-install recovery validate a staged copy
  before atomically replacing the canonical target, so a partial copy cannot
  block or defeat rollback.
- Local builders receive the same resolved short version and timestamp build.
  Debug guidance uses `X.Y.Z`/`N` placeholders instead of an obsolete release.
- Packaged DMG installs resolve version metadata from their payload and release
  manifest; only source-build mode reads the repository input-method plist.

## Test Plan

- `bash -n` for every touched shell script.
- `swift test --filter InputMethodBundleInfoTests`
- `swift test --filter DebugInstallGuidanceTests`
- `swift test --filter InstallationDiagnosticsStatusTests`
- `./scripts/smoke-inputmethod-install.sh --with-prefpane`
- `swift test`
- `git diff --check`

## Assumptions

- Backup manifests protect rollback from corruption and artifact substitution;
  they are not a replacement for notarized distribution or privileged storage.
- Legacy override is intentionally noisy and remains a local recovery tool.
