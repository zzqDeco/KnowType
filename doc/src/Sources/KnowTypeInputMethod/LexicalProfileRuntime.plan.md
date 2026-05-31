# LexicalProfileRuntime

Status: Active

`Sources/KnowTypeInputMethod/LexicalProfileRuntime.swift` owns the input-method side of persistent lexical profile refresh.

It keeps userdb snapshot reads, Rime userdb parsing, accepted-AI summary merging, lexical profile merging, profile file writes, and AI diagnostic logging outside `InputControllerCoordinator`. The coordinator may pass recent commit/selection snapshots and a schema id after a commit or selection, but the runtime schedules the delayed background work and writes `LEXICAL_PROFILE.md` through `LexicalProfileStore`.

Accepted-AI summary rebuilds can finish after the first commit-triggered profile refresh. The runtime subscribes to summary-ready metadata and schedules a second background refresh for the latest matching schema so the persistent markdown/JSON mirrors eventually include `accepted-ai` source counts.

Summary-ready observation is process-wide for the shared accepted-learning store. The event is dispatched only to the runtime that most recently scheduled a refresh, and refresh task cancellation/generation updates are serialized so inactive controllers cannot replace the shared profile with stale commit or selection context. `cancelRefresh()` also clears the latest refresh context and unregisters the runtime from the process-wide summary observer so controller close cannot be followed by a summary-triggered stale profile write.

The runtime reads only existing Rime userdb text snapshots through `RimeMaintenanceService`'s `RimeUserDBTextSnapshotProviding` surface. It must not call explicit `sync_user_data`; sync remains a maintenance/manual/idle concern owned by `RimeMaintenanceService`.

AI request construction may ask this runtime for a request-local `LexicalContextSnapshot`, which merges persisted profile terms, accepted-AI summaries, and in-memory recent commits/selections. Current-page Rime candidates and full accepted-AI history are not sent. This read is memory-only and safe for the IMK hot path.
