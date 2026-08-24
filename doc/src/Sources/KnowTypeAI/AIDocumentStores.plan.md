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
  backup; markerless User Notes headings are normalized away while text on both
  sides is retained, and repeated loads are idempotent. Unknown ambiguity fails
  closed. Only whole marker lines delimit generated content, so marker words in
  ordinary user text are preserved. Required backup and canonical write-back
  failures remain fail-closed.
- Digest candidates are exactly one non-empty markdown value, at most 4 KiB and
  200 lines, and may not contain KnowType markers or document/User Notes titles.
  Invalid candidates do not write ENV or claim/archive events.
- Scan input is capped at 1 MiB. Generated and User Notes content are each
  capped at 4 KiB, and the ENV projection is capped at 8 KiB. Backup and claim
  files are not included in provider context. Digest schedule state and an
  archive receipt contain only timestamps, counts, and hashes; all are bounded,
  atomically written with mode 0600, and used to recover cleanup without a
  second provider call.
- Provider budgeting counts the structured generated and User Notes bodies
  after removing only their canonical separator newlines, so 4,096 body bytes
  are accepted and 4,097 are rejected without changing the 8 KiB ENV cap.
- `CorrectionInstructionStore` owns `CORRECTION.md` creation and loading; reads
  use a file handle capped at 4 KiB plus one detection byte and reject excess
  content without allocating the whole file. Creation and existing-file loads
  force mode 0600; temporary and final permission failures are fail-closed.
- `AIUserDirectory` also exposes the readable accepted-learning mirror path
  `~/.knowtype/ACCEPTED_AI_LEARNING.md`; canonical accepted-learning JSON files
  live under Application Support.

## Tests

- `EnvironmentDocumentStoreTests`
- `AIContextMemoryRuntimeTests`
- `AIRecommendationRuntimeTests`
