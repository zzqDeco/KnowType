# Provider Profile Concurrency And Diagnostic Redaction

Status: Active

## Summary

Make provider settings updates transactional across the input-method settings
window, standalone Settings app, and compatibility PreferencePane. Prevent a
stale endpoint snapshot from resolving a newer credential, and keep provider
endpoints useful but credential-free in settings and shell diagnostics.

This slice closes GitHub issues #175 and #182 without changing provider adapter
wire formats or adding a runtime reload observer.

## Scope

- Upgrade `ProviderProfilesFile` to schema version 2 with a monotonic revision.
- Move schema-v2 metadata to generation-separated `providers.v2.json`; retain
  `providers.json` only as a migration source and incompatible tombstone so an
  already-running pre-v2 Settings binary cannot overwrite canonical state.
- Coordinate production file mutations through a sidecar `flock` and
  expected-revision compare-and-swap transaction.
- Reject stale settings saves, default changes, and connection tests; refresh
  saved profiles while preserving the user's draft and showing localized
  conflict copy.
- Store every changed API key under an immutable
  `knowtype.provider.<profileID>.credential.<UUID>` reference.
- Reject Base URLs containing userinfo or fragments while preserving query
  compatibility at runtime.
- Redact userinfo, query, and fragment from Settings and shell diagnostic
  endpoint summaries.
- Post a privacy-safe cross-process revision notification after each successful
  production file commit.

## Implementation

- Schema-v1 files decode with revision `0`; the installer migrates numeric v1
  or v2 legacy files to canonical schema v2 and increments revision once.
  Versions newer than v2 fail decoding.
- `FileProviderProfileStore` locks `providers.v2.json.lock`, reloads the current
  file under the lock, checks the expected revision, applies one mutation,
  increments the revision, atomically replaces JSON, releases the lock, and
  posts the revision signal.
- Migration preserves the exact legacy payload as `providers.legacy.json`,
  copies each available Keychain value to a fresh immutable credential
  reference, atomically claims the exact source payload, publishes a deliberately
  nonnumeric tombstone without overwriting a competing writer, writes canonical
  metadata, then verifies that no late pre-v2 writer replaced the tombstone.
  A late writer payload is retained and migration fails closed instead of
  discarding it; a three-way race preserves the intermediate claim as a
  permission-restricted `providers.legacy-conflict.<UUID>.json`. Legacy credentials remain intact for
  downgrade safety; canonical metadata never references them.
- The installer closes standalone Settings and System Settings before running
  the installed app's explicit migration command. Migration completes before
  LaunchServices/TIS registration; failure enters the existing artifact
  rollback path.
- Failed-install recovery checks the backup app's storage generation before it
  is published. For pre-v2 backups, the new app's compare-and-claim rollback or
  downgrade command prepares compatible metadata; the shell never copies an
  earlier provider snapshot over a late legacy writer. Uncertain rollback keeps
  the new binary instead of pairing an old binary with a tombstone.
- Explicit user-requested rollback reads the target app's declared provider
  storage generation. A pre-v2 target is not published until the current app
  has converted the latest canonical profile set to a verified numeric legacy
  payload; values and Keychain secrets are preserved.
- ViewModels compare their complete loaded baseline before each operation and
  use the store CAS again at commit time. In-flight connection results also
  recheck the baseline before publication.
- Secret replacement writes the new unique Keychain item first. Metadata failure
  deletes that new item; success publishes the new reference before deleting an
  old unreferenced item. Legacy references remain readable until a key changes.
- `ProviderEndpointURLPolicy` owns Swift validation and privacy-safe summaries.
  `scripts/lib/provider_endpoint_summary.py` owns the equivalent shell contract;
  both are checked against `Tests/Fixtures/provider-endpoint-summary.json`.

## Test Plan

- `swift test --filter ProviderProfileTests`
- `swift test --filter ProviderProfileEditingPolicyTests`
- `swift test --filter ProviderProfilesViewModelTests`
- `swift test --filter InstallationDiagnosticsStatusTests`
- `swift test --filter InputMethodBundleInfoTests/testProviderEndpointFixturesAndDiagnosticOutputsAreRedacted`
- `python3 scripts/lib/provider_endpoint_summary.py --verify-fixtures Tests/Fixtures/provider-endpoint-summary.json`
- `bash -n scripts/diagnose-inputmethod.sh scripts/package-dmg.sh`
- `swift test`
- `git diff --check`

## Assumptions

- Runtime consumers continue loading provider state on their existing lifecycle;
  this slice emits the cross-process signal but intentionally adds no observer.
- Query parameters remain accepted for compatibility but are always omitted from
  diagnostics; summaries append `[query redacted]` when a query was removed.
- Failure to remove an old unreferenced credential is reported after a successful
  metadata commit; the active metadata/credential pair is not rolled back.
- A pre-v2 Settings binary cannot read the tombstone. If an already-open legacy
  writer recreates `providers.json`, canonical runtime reads remain unchanged,
  new saves fail closed, diagnostics report the divergence, and both payloads
  remain intact for conflict resolution. The installer never discards the late
  writer payload.
