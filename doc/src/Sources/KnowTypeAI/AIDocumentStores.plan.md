# AIDocumentStores

## Responsibility

Maintains bounded, canonical local AI context documents under `~/.knowtype`.

## Boundaries

- `EnvironmentDocumentStore` owns `ENV.md` creation, bounded scanning, migration,
  canonicalization, generated-section replacement, content-hash backups, and
  privacy-safe digest claims.
- Canonical ENV contains one document title, one managed generated marker pair,
  and one User Notes section. Markerless input is user content; duplicate or
  recursively polluted known layouts are repaired after a 0600 hash-deduplicated
  backup; unknown ambiguity fails closed.
- Digest candidates are exactly one non-empty markdown value, at most 4 KiB and
  200 lines, and may not contain KnowType markers or document/User Notes titles.
  Invalid candidates do not write ENV or claim/archive events.
- Scan input is capped at 1 MiB. Generated and User Notes content are each
  capped at 4 KiB, and the ENV projection is capped at 8 KiB. Backup and claim
  files are not included in provider context.
- `CorrectionInstructionStore` owns `CORRECTION.md` creation and loading.
- `AIUserDirectory` also exposes the readable accepted-learning mirror path
  `~/.knowtype/ACCEPTED_AI_LEARNING.md`; canonical accepted-learning JSON files
  live under Application Support.

## Tests

- `EnvironmentDocumentStoreTests`
- `AIContextMemoryRuntimeTests`
- `AIRecommendationRuntimeTests`
