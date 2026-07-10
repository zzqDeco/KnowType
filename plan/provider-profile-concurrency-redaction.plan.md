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

- Schema-v1 files decode with revision `0`; the first successful mutation writes
  schema v2 and revision `1`. Versions newer than v2 fail decoding.
- `FileProviderProfileStore` locks `providers.json.lock`, reloads the current
  file under the lock, checks the expected revision, applies one mutation,
  increments the revision, atomically replaces JSON, releases the lock, and
  posts the revision signal.
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
  diagnostics.
- Failure to remove an old unreferenced credential is reported after a successful
  metadata commit; the active metadata/credential pair is not rolled back.
