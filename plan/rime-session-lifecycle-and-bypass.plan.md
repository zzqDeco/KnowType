# Rime Session Lifecycle, Prewarm Reuse, and Snapshot Read Optimization

## Delivered Behavior

- `NativeRimeSession.prewarm(configuration:)` caches the prewarmed
  `(NativeRimeConfiguration, NativeRimeSession)` in `NativeRimeSession`'s
  thread-safe `CreationState` instead of immediately destroying the session when
  `RimeConversionEngine.prewarmNativeSession(configuration:)` returns.
  Matching foreground `NativeRimeSession.createForeground(configuration:...)`
  and `NativeRimeSession(configuration:)` calls claim the cached session and
  clear the cache slot without invoking `ktb_rime_session_create` a second time.
- `NativeRimeSession.processText(_:)` and
  `RimeConversionEngine.replayNativeRawInputMirrorIfNeeded(into:)` restrict
  key replay/forwarding to printable ASCII scalars (`0x20...0x7e`), and
  `NativeRawInputMirrorPolicy.updatedMirror` clears stale mirror state whenever
  `!result.snapshot.hasComposition`.
- Default unsynced `RimeUserDBTextSnapshotProvider.userDBTextSnapshot(schemaID:)`
  resolves user data/sync directories and schema dictionary names directly from
  disk (`installation.yaml` and `<schemaID>.schema.yaml`) without creating a
  `NativeRimeSession`, reserving native session creation for
  `syncedUserDBTextSnapshot(schemaID:)` (or injected test session factories).

## Verification

- `swift test --filter RimeConversionEngineTests`
- `testPrewarmCachesAndReusesSessionOnMatchingForegroundCreation`
- `testDefaultUserDBTextSnapshotProviderReadsSnapshotWithoutCreatingNativeSession`
- `testNativeRawInputMirrorClearsWhenUnhandledNativeActionHasNoComposition`
- `testNativeRimePrewarmKeepsFirstProcessUsableWhenArtifactsAreAvailable`

## Docs Absorbed By

- [RimeConversionEngine.swift](../doc/src/Sources/KnowTypeInputMethod/RimeConversionEngine.swift.plan.md)
- [RimeConversionEngine](../doc/src/Sources/KnowTypeInputMethod/RimeConversionEngine.plan.md)

## Retirement Criteria

- Retire once the prewarm session cache and session-free unsynced userdb
  snapshot behavior are indexed in current source notes and verified on `dev`.
