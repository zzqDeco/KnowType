# RimeConversionEngine

## Responsibility

Owns KnowType's conversion-engine boundary for mature IME-style basic Chinese
input.

## Boundaries

- `RimeConversionEngine` prefers a native `librime` session when a verified
  runtime and shared data are available.
- The engine falls back to `TraditionalInputEngine` so local development and CI
  stay deterministic without binary artifacts.
- Source-tree artifacts under `Vendor/Rime` are enabled only with
  `KNOWTYPE_RIME_ENABLED=1` or explicit Rime paths; installed app bundles use
  bundled Frameworks/Resources automatically.
- AI continuation, context memory, and prefix-lock behavior stay outside the
  base conversion session.

## Behavior Notes

- The native bridge follows the mature Squirrel pattern: process a key, consume
  commit text, then read context/candidates.
- Native sessions explicitly select `pinyin_simp`, matching the bundled
  shared-data recipe set.
- Numeric selection maps displayed full-candidate rows back to the current Rime
  context page before calling current-page candidate selection. Conversion rows
  encode the native current-page index in source metadata so duplicate surface
  forms still select the intended Rime candidate.
- Explicit segment-candidate selection stays a KnowType composition action and
  is handled before native `Space` processing.
- The SwiftPM target does not link to librime at build time; `KnowTypeRimeBridge`
  loads `librime.1.dylib` dynamically.
- The bridge requires `rime_get_api_stdbool`; it does not fall back to the
  non-`stdbool` ABI because the local context/status structs use bool fields.
- Calls into versioned Rime API tail members, such as current-page candidate
  selection and page changes, must check `data_size` before reading the mirrored
  function pointer.
- Reset clears the native composition instead of tearing down the process-global
  Rime runtime.
- When the coordinator replaces the conversion engine after a runtime lexicon
  reload, it replays the active raw input into the new session before native
  Space or candidate selection can run.

## Tests

- `RimeConversionEngineTests`
- `InputControllerCoordinatorTests`
- `swift test`
