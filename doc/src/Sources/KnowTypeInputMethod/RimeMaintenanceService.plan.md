# RimeMaintenanceService

## Responsibility

Owns Rime userdb maintenance outside the active input session.

## Boundaries

- `RimeUserDBTextSnapshotProvider.userDBTextSnapshot` reads an existing
  exported `*.userdb.txt` snapshot only.
- `syncedUserDBTextSnapshot` is the explicit path that may call
  `sync_user_data`.
- `RimeMaintenanceService.syncUserDataIfIdle` serializes sync policy and is the
  future manual/idle maintenance entry point.
- `InputControllerCoordinator` may request existing snapshots for lexical
  profile refresh, but it must not call `sync_user_data` or
  `syncedUserDBTextSnapshot`.

## Behavior Notes

- Commit and candidate-selection events update in-memory recent history first,
  then refresh `LEXICAL_PROFILE.md` from the last available Rime userdb export.
- Missing, stale, locked, or unreadable snapshots fall back through the existing
  lexical-profile error path; they must not affect Rime key handling or
  candidate-panel visibility.
- Userdb `.ldb` files remain private to Rime and are not parsed directly.

## Tests

- `RimeConversionEngineTests`
- `InputControllerCoordinatorTests`
- `InputHotPathPerformanceTests`
- `swift test`
