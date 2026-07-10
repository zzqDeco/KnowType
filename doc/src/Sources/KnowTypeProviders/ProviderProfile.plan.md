# ProviderProfile

## Responsibility

`ProviderProfile` and its stores define persisted provider metadata.

## Boundaries

- API key values are never stored in provider JSON.
- Draft UI state belongs in settings ViewModels.
- Adapter-native payloads belong in individual providers.

## Behavior Notes

- Persisted fields include display name, kind, base URL, model, timeout,
  headers, custom HTTP mapping, default status, and `secretName`.
- `ProviderProfilesFile` schema v2 adds a monotonic `revision`. Schema-v1 files
  without that field decode as revision `0`. Unknown future schemas are rejected
  instead of partially decoded.
- `FileProviderProfileStore` coordinates readers and writers with the
  `providers.v2.json.lock` sidecar. Mutations reload under an exclusive `flock`,
  compare the expected revision, atomically replace JSON, and increment the
  revision exactly once.
- `providers.v2.json` is canonical. The installer migrates numeric legacy
  `providers.json`, snapshots its exact bytes to `providers.legacy.json`, rekeys
  available credentials to fresh immutable Keychain references, and leaves an
  incompatible tombstone at the legacy path. This storage-generation boundary
  prevents a pre-v2 Settings binary from overwriting canonical metadata.
- Canonical reads ignore a stale legacy rewrite. New writes fail closed until
  the conflict is resolved, and migration never overwrites the late writer's
  payload. A missing canonical file after a completed migration is reported
  rather than treated as empty settings.
- Migration holds the canonical sidecar lock, rejects occupied credential
  destinations, refreshes the legacy snapshot on retry, publishes the legacy
  tombstone through an atomic compare-and-claim before canonical metadata, and
  verifies that no pre-v2 writer replaced it during cutover. Normal canonical
  saves use the same non-overwriting tombstone preparation. If two legacy writes
  race around the claim, the intermediate payload remains permission-restricted
  as `providers.legacy-conflict.<UUID>.json` instead of being discarded. It
  never deletes a newly copied credential unless
  failed metadata was conclusively rolled back. The explicit install rollback restores legacy
  metadata before removing canonical-only credentials and requires the exact
  migration revision, so later Settings saves make a stale rollback fail closed.
- Explicit app rollback uses `downgradeCanonicalProfilesForLegacyRuntime()`
  before publishing a pre-v2 binary. It writes the current canonical profile set
  as schema v1, preserves current Keychain references, and removes canonical
  metadata only after the legacy payload is verified.
- A successful production commit posts only the new revision through
  `ProviderProfileRevisionSignaling`; the default signal crosses process
  boundaries and exposes no profile or credential contents.
- Validation differs for local and remote OpenAI-compatible profiles: local
  profiles may leave model blank for discovery, remote profiles may not.
- Saved profiles override seeded defaults.
- The default file store has an explicit no-create mode for runtime cold start:
  a genuinely new profile store loads empty without creating the `KnowType`
  Application Support directory. Legacy or incomplete migrated state fails
  closed. Saves still create the directory.

## Tests

- `ProviderProfileTests`
- `ProviderProfilesViewModelTests`
