# RimeConversionEngine

## Responsibility

Owns KnowType's conversion-engine boundary for mature IME-style basic Chinese
input.

## Boundaries

- `RimeConversionEngine` owns the production base conversion path through a native `librime` session.
- The engine does not fall back to `TraditionalInputEngine`; when Rime is unavailable it reports a degraded raw-input snapshot without candidates.
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
- Native sessions explicitly select `pinyin_simp`, matching the bundled
  shared-data recipe set.
- Numeric selection maps displayed rows to Rime's current-page index before calling `select_candidate_on_current_page`.
- Current-page highlight changes call Rime's `highlight_candidate_on_current_page` so arrow movement and hover keep the engine context authoritative.
- `commitComposition` is exposed for IMK lifecycle commits and uses Rime's native composition commit when available.
- Native snapshots include Rime raw input and preedit; the coordinator uses preedit as marked text and syncs raw input after partial commits.
- Native snapshots copy only the current Rime menu page on the synchronous key path; full candidate-list iteration is intentionally absent from the bridge.
- Explicit segment-candidate selection is retired from the production IMK path.
- The SwiftPM target does not link to librime at build time; `KnowTypeRimeBridge`
  loads `librime.1.dylib` dynamically.
- The bridge requires `rime_get_api_stdbool`; it does not fall back to the
  non-`stdbool` ABI because the local context/status structs use bool fields.
- Calls into versioned Rime API tail members, such as current-page candidate
  selection, highlight changes, composition commit, raw input, and page changes,
  must check `data_size` before reading the mirrored function pointer.
- The C bridge treats `commit_composition`, `highlight_candidate_on_current_page`,
  `select_candidate_on_current_page`, `get_input`, and `change_page` as
  versioned API members; missing members must return `false`/empty snapshots
  instead of dereferencing beyond the runtime ABI.
- Reset clears the native composition instead of tearing down the process-global
  Rime runtime.
- Non-ASCII composition text bypasses the native session until reset and keeps raw input without producing local fallback candidates, preventing Rime's ASCII key API from silently diverging from the coordinator raw buffer.
- While native Rime is active, the Swift engine mirrors text/delete edits so a
  later non-ASCII bypass can preserve the existing raw preedit without invoking
  the retired local converter.
- Runtime lexicon reload no longer initializes or replaces the production conversion engine.

## Tests

- `RimeConversionEngineTests`
- `InputControllerCoordinatorTests`
- `swift test`
