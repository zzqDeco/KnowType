# LexicalProfileRuntime

Status: Active

`Sources/KnowTypeInputMethod/LexicalProfileRuntime.swift` owns the input-method side of persistent lexical profile refresh.

It keeps userdb snapshot reads, Rime userdb parsing, accepted-AI summary merging, lexical profile merging, profile file writes, and AI diagnostic logging outside `InputControllerCoordinator`. The coordinator may pass recent commit/selection snapshots and a schema id after a commit or selection, but the runtime schedules the delayed background work and writes `LEXICAL_PROFILE.md` through `LexicalProfileStore`.

The runtime reads only existing Rime userdb text snapshots through `RimeMaintenanceService`'s `RimeUserDBTextSnapshotProviding` surface. It must not call explicit `sync_user_data`; sync remains a maintenance/manual/idle concern owned by `RimeMaintenanceService`.

AI request construction may ask this runtime for a request-local `LexicalContextSnapshot`, which merges persisted profile terms, accepted-AI summaries, and in-memory recent commits/selections. Current-page Rime candidates and full accepted-AI history are not sent. This read is memory-only and safe for the IMK hot path.
