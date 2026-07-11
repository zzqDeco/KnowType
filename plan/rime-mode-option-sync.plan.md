# Rime Mode Option Synchronization

## Summary

Synchronize KnowType's process-wide text, punctuation, and character-width state
with the active native Rime session. This Wave 2 PR 7 slice closes issue #177
without changing Rime schemas, candidate ordering, AI behavior, providers, or
installation.

## Scope

- Export guarded session option get/set operations from `KnowTypeRimeBridge`.
- Apply `ascii_mode`, `ascii_punct`, and `full_shape` after native session schema
  selection and whenever the shared mode generation changes.
- Treat full width as a character transform for ASCII `!` through `~` and normal
  space, while leaving controls, Tab, and newline unchanged.
- Choose Chinese opening/closing quotes from the character before the caret when
  available, with session alternation only for unknown context.
- Reset quote fallback state after external delete, selection/focus changes, and
  process-mode generation changes.

Non-goals: AI, provider adapters, installer behavior, candidate ordering, host
carrier policy, and Rime schema or dictionary changes.

## Implementation

- The C bridge checks both `RimeApi.data_size` and option function pointers
  before reading or calling `set_option` or `get_option`; older librime builds
  fail closed instead of dereferencing unavailable members.
- `KnowTypeConversionEngine.synchronizeInputMode(_:)` is a default no-op seam.
  `RimeConversionEngine` caches the desired snapshot without forcing cold-start
  initialization, applies it after each new native session selects its schema,
  and reapplies it on generation changes.
- `InputSymbolTransformer` uses the Unicode full-width offset for printable
  ASCII and maps U+0020 to U+3000. The existing ASCII-digit-plus-period rule runs
  before width conversion.
- `InputPunctuationContextResolver` classifies whitespace/open punctuation as
  opening and text/digits/closing punctuation as closing. Missing document
  context remains unknown and uses coordinator-local alternation.
- The process-global state remains authoritative across apps. Legacy default and
  code-app preference fields remain compatibility data only.

## Test Plan

- `swift test --filter InputMethodBundleInfoTests`
- `swift test --filter RimeConversionEngineTests`
- `swift test --filter InputSymbolModeTests`
- `swift test --filter InputPunctuatorRuntimeTests`
- `swift test --filter InputPunctuationContextResolverTests`
- `swift test --filter InputControllerCoordinatorTests`
- `swift test --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`
- Prepare pinned Rime artifacts and run native option/session tests plus the
  relevant input-method bundle smoke when local signing/runtime state allows.

## Assumptions

- Process-global means one input-method host lifetime; only the global width is
  restored after a host restart.
- A host librime that predates session option access remains usable, but cannot
  provide native mode synchronization.
- Full-width quote keys remain full-width ASCII forms when full-width conversion
  is enabled; contextual Chinese quote pairing applies in Chinese punctuation
  half-width mode.
