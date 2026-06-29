# Sources/KnowTypeInputMethod

`KnowTypeInputMethod` owns input-method interaction behavior.

Current package-level implementation covers:

- explicit IME session mode modeling for empty, composing, candidate, AI-pending, polish, and protected ASCII/no-correction input
- candidate panel view model
- session commit policy for raw/prefix numeric shortcuts and native candidate selections
- legacy segmented composition buffering for package/session tests; production Chinese conversion is Rime-only
- candidate anchor range policy for IMK clients with known or unknown selection ranges
- candidate anchor resolver for IMK rects, line-height rects, Accessibility rects, scoped last-anchor fallback, safe screen fallback, and debug tracing
- custom AppKit candidate presentation styled as a compact macOS candidate list
- candidate panel row builder and renderer with raw input, commit-only preedit,
  locked prefix, AI status, and continuation rows
- candidate panel mouse hover, click commit, scroll paging, row accessibility, and PNG snapshot regression tests
- shortcut-to-commit behavior
- key intent modeling for key down, key up, modifier flag changes, cancel, delete, navigation keys, punctuation, and numeric candidate selection
- persisted `InputModeState` for text mode, punctuation language, and symbol width, refreshed from saved preferences at new composition/direct symbol boundaries and focused-bundle changes, with `Option + .` toggling punctuation language and `Option + /` toggling Chinese/ASCII text mode for the active session
- host compatibility write modes for inline composition, commit-only
  composition, ASCII passthrough, and missing-client disabled handling
- runtime loading of user-owned JSON/TSV lexicon directories into the local Chinese engine
- runtime lexicon snapshot refresh at new-composition boundaries so local dictionary file changes can be picked up without reinterpreting active marked text
- persisted prefix selection history used as a local-only ranking signal
- optional `RimeConversionEngine` boundary with a dynamic `librime` bridge and deterministic `TraditionalInputEngine` fallback
- lexical profile snapshots for AI recommendation that exclude Level 0/protected app commits and protected-app selection history
- `InputTaskSupervisor` cancellation for local candidates, AI, runtime lexicon reload, and panel rendering work
- testable host/client seams for the IMK controller boundary
- async suggestion pipeline wiring
- Level 0 no-provider routing for protected input
- minimal InputMethodKit server bootstrap guarded by `canImport(InputMethodKit)`
- `KnowTypeInputMethodApp` bundle entry assembled by `scripts/build-inputmethod-bundle.sh`

The AppKit candidate panel is the active candidate presentation for the IMK bundle. This avoids the `IMKCandidates` failure mode where the system panel accepts data but does not become visible in some host apps. `CandidatePanelRowBuilder` owns row ordering and selection identity for both state and rendering. Commit-only preedit rows render above candidates when the host text field receives only a placeholder carrier. Prefix rows are rendered first after any preedit row, continuation rows after them, and raw input is rendered only while no suggestion exists. The panel uses native AppKit material, system colors, compact row metrics, row hit-testing, and accessibility elements. `Space` commits the visible snapshot for the current raw input; mouse click commits the same `CandidatePanelSelection` as keyboard selection and never commits disabled status rows.

When a provider is configured, the IMK controller publishes raw marked text and current-page Rime prefix candidates synchronously; provider-backed AI recommendation rows remain asynchronous. The first candidate publication does not include local fallback continuation rows. If the provider fails or returns no usable continuation, the async update keeps the AI slot unavailable instead of substituting local fallback text, so `Space` still commits through Rime while `Tab` does not present fake AI output. Ready AI remains the second shortcutable slot; pending, unavailable, and ineligible AI states are disabled status rows with muted styling, no shortcut, no hover selection, and no click commit. Without a provider, the product input path still uses Rime only for Chinese conversion.

The IMK controller marks composing text with `IMKTextInput.setMarkedText`. Inline-compatible hosts, including browsers, text editors, IDEs, Electron shells, and JetBrains-style clients by default, receive Rime preedit as attributed marked text. Terminal-style or explicit override commit-only hosts receive a full-width-space attributed placeholder so IMK composition ownership and candidate anchoring stay stable without exposing raw pinyin in the host field. Their real preedit is shown in the candidate panel instead. Candidate anchor lookup is delegated to `CandidateAnchorResolver`, which prefers fresh IMK text rects, then line-height rects, then Accessibility focused-range bounds if permission is already granted, then a same-composition scoped last usable anchor, and finally a stable safe point inside the screen visible frame. The panel no longer follows the mouse pointer when host text geometry is temporarily unavailable.

Product commit decisions are shared through the session commit policy and coordinator: `Space` commits the highlighted/current Rime candidate, selects a non-highlighted native row by stable current-page Rime index before falling through to generic native Rime space handling, or commits raw input when Rime is degraded; `Return` commits the raw composition, `Tab` commits AI only when that slot is ready, numeric candidate shortcuts call Rime current-page selection without recomputing candidates, punctuation commits the current Rime candidate/composition plus mapped punctuation, `Option+/` toggles Chinese/ASCII text mode for the active session, and `Option+R` requests explicit polish only. Idle printable ASCII can be returned unhandled when the session is in ASCII mode; Terminal-style hosts default to that mode, while editor/Electron/IDE-style hosts default to Chinese inline composition so candidates can appear immediately without a separate preedit row. Duplicate native surface forms keep their Rime stable index, and runtime lexicon reload no longer replaces the production conversion session. The IMK controller remains responsible for host integration details such as client lookup, marked text, insertion, palette visibility, input mode state ownership, and window anchoring, but those details now route through `InputControllerCoordinator` and small host/client seams so controller-adjacent behavior can be unit-tested without installing the input method.

Candidate paging keeps 6 visible rows per page in adaptive horizontal mode so short candidates do not force a vertical panel. Vertical-list mode can show up to 9 visible rows per page. Arrow keys move one selectable row, PageDown/PageUp preserve the selected row's visible offset on the target page, and short final pages clamp to their last available row. Scroll-wheel paging maps to PageDown/PageUp with a small delta threshold to avoid trackpad jitter. Screenshot baselines under `Tests/KnowTypeInputMethodTests/__Snapshots__/` cover light horizontal, dark vertical, and AI status panel states.

The IMK controller records recently committed prefix candidates in memory, persists them through `UserSelectionHistoryPersistence`, and feeds a top-K lexical snapshot into background AI recommendation context. Persistence appends newly selected prefixes on a shared serial queue and controller shutdown waits for pending writes, so stale snapshots do not overwrite newer selections from another host app. The ranking signal stays local; AI requests receive only summarized lexical context, not the full selection log.

MVP manual acceptance still must verify candidate window behavior in host apps because IMK text input behavior varies across AppKit, browser, Electron, and terminal contexts.
