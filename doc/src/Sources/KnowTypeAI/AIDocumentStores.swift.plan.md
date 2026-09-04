# AIDocumentStores.swift

## Responsibility

- Own canonical ENV structure, User Notes preservation, bounded recovery
  metadata, deterministic migration backups, and correction-document reads.

## Boundaries

- It does not persist provider output outside the managed ENV section or expose
  user text through claim, receipt, schedule, or diagnostic metadata.

## Behavior Notes

- Existing ENV files are chmod 0600 before any content read; failure is
  fail-closed.
- A structural User Notes heading is valid only after the unique generated
  marker pair. A heading before or inside that pair is ambiguous and backed up
  without rewriting ENV.
- An existing hash-named backup is opened without following symlinks, verified
  as a regular file, bounded-read, matched by byte count, SHA-256, and content,
  and restricted to 0600 before migration continues.
- `ENV.digest-schedule.json` stores only bounded timestamps and event counts.
  It includes at most 64 successful Context Digest timestamps for rolling
  budget recovery. Older JSON without that field decodes it as an empty list
  and keeps `lastSuccessfulDigestAt` as the legacy cadence anchor.
- `ENV.digest-archive-receipt.json` binds archive evidence to an optional exact
  successful-digest timestamp. Older receipts without that field still decode;
  recovery upgrades a matching receipt before schedule persistence. This
  ordering makes a completed claim's rolling-budget slot idempotent across
  schedule and cleanup failures without storing event or generated content.

## Tests

- `EnvironmentDocumentStoreTests` covers read-before-permission prevention,
  structural ordering, idempotent failure, and authentic or suspicious existing
  backup objects.
