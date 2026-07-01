# RimeConversionEngine

## Responsibility

Owns KnowType's conversion-engine boundary for mature IME-style basic Chinese
input.

## Boundaries

- `RimeConversionEngine` owns the production base conversion path through a native `librime` session.
- The engine does not fall back to `TraditionalInputEngine`; when Rime is unavailable it reports a degraded raw-input snapshot without candidates.
- Engine initialization is cold-start read-only. It stores the native Rime
  configuration but does not create the `NativeRimeSession`, user data
  directory, or log directory until the first real `process(_:)` call.
- `RimeConversionEngine.prewarmNativeSession(configuration:)` is the explicit
  exception used after the IMK controller is live. It creates and releases a
  temporary native session to move cold Rime/dyld cost off the user's first
  key, while normal engine construction, `snapshot`, `activeSchemaID`,
  `isNativeActive`, and `reset()` remain read-only.
- Source-tree artifacts under `Vendor/Rime` require explicit `KNOWTYPE_RIME_ENABLED=1`; installed app bundles use bundled Frameworks/Resources automatically.
- xctest processes use temporary Rime user/log directories to avoid locking the user's live Rime DB.
- Explicit Rime environment paths expand leading `~` before URL conversion, so
  shell-friendly overrides resolve to the same filesystem locations as absolute
  paths.
- AI continuation, context memory, and prefix-lock behavior stay outside the
  base conversion session.

## Behavior Notes

- The native bridge follows the mature Squirrel pattern: process a key, consume
  commit text, then read context/candidates.
- `snapshot`, `activeSchemaID`, `isNativeActive`, and `reset()` must not force
  native session creation. This lets macOS prelaunch the IMK host without
  initializing Rime user data.
- With `KNOWTYPE_STARTUP_DEBUG=1`, first native session creation logs elapsed
  time, schema id, and success state without logging input text.
- With `KNOWTYPE_STARTUP_DEBUG=1`, native prewarm logs start/done events with
  elapsed time, schema id, and success state without logging input text.
- Native session creation serializes entry into the C bridge because librime
  setup and the cached API handle are process-global. The background prewarm
  uses a speculative try-lock path and skips prewarm when foreground creation is
  already in progress, while foreground lazy creation remains authoritative.
- Native sessions initially select the configured schema, but
  `activeSchemaID` is read back from the live Rime session through
  `get_current_schema`/status so runtime schema switches feed the correct
  lexical-profile refresh and merge gates.
- Raw-bypass state is checked before native session creation. If a composition
  entered non-ASCII bypass before a native session existed, later ASCII or
  navigation keys continue through the raw-bypass path until reset and still do
  not create Rime user/log directories.
- Numeric selection maps displayed rows to Rime's current-page index before calling `select_candidate_on_current_page`.
- Current-page highlight changes call Rime's `highlight_candidate_on_current_page` so arrow movement and hover keep the engine context authoritative.
- `commitComposition` is exposed for IMK lifecycle commits and uses Rime's native composition commit when available.
- Native snapshots include Rime raw input and preedit; the coordinator uses preedit as marked text and syncs raw input after partial commits.
- Native suggestion snapshots expose current-page Rime candidates as prefix
  candidates only; they do not set `lockedPrefix` from the first unselected
  candidate.
- Native snapshots copy only the current Rime menu page on the synchronous key path; full candidate-list iteration is intentionally absent from the bridge.
- Userdb snapshot reads resolve the live active schema's user dictionary name,
  then scan deterministically for that dictionary's existing `*.userdb.txt`
  export; they never parse `.ldb` files and are not called from the synchronous
  key path.
- `sync_user_data` is no longer part of the default snapshot read. It is exposed
  only through the explicit synced snapshot path owned by
  `RimeMaintenanceService`.
- Explicit segment-candidate selection is retired from the production IMK path.
- The SwiftPM target does not link to librime at build time; `KnowTypeRimeBridge`
  loads `librime.1.dylib` dynamically.
- The bridge requires `rime_get_api_stdbool`; it does not fall back to the
  non-`stdbool` ABI because the local context/status structs use bool fields.
- Calls into versioned Rime API tail members, such as current-page candidate
  selection, highlight changes, composition commit, raw input, current schema,
  and page changes, must check `data_size` before reading the mirrored function
  pointer.
- Sync/user-data directory bridge calls also guard versioned API members before
  dereferencing function pointers and return fallback errors when unavailable.
- The C bridge treats `commit_composition`, `highlight_candidate_on_current_page`,
  `select_candidate_on_current_page`, `get_input`, `get_current_schema`, and
  `change_page` as versioned API members; missing members must return
  `false`/empty snapshots or fall back to status/configured values instead of
  dereferencing beyond the runtime ABI.
- Reset clears the native composition instead of tearing down the process-global
  Rime runtime.
- Non-ASCII composition text bypasses the native session until reset and keeps raw input without producing local fallback candidates, preventing Rime's ASCII key API from silently diverging from the coordinator raw buffer.
- While native Rime is active, the Swift engine mirrors text/delete edits so a
  later non-ASCII bypass can preserve the existing raw preedit without invoking
  the retired local converter.
- When a host librime ABI does not expose `get_input`, handled native actions
  that can change composition text (`Space`, candidate selection, and
  composition commit) rebuild the raw-input mirror from Rime preedit instead of
  reusing a stale mirror. Highlight and page-only actions preserve the existing
  mirror because they do not edit composition text.
- Runtime lexicon reload no longer initializes or replaces the production conversion engine.

## Tests

- `RimeConversionEngineTests`
- `InputControllerCoordinatorTests`
- `swift test`
