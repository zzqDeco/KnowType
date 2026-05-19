# Sources/KnowTypeInputMethod

`KnowTypeInputMethod` owns input-method interaction behavior.

Current package-level implementation covers:

- explicit IME session mode modeling for empty, composing, candidate, AI-pending, polish, and protected ASCII/no-correction input
- candidate panel view model
- session commit policy for raw/prefix numeric shortcuts and native candidate selections
- segmented composition buffering so raw pinyin, resolved candidate spans, marked-text display, and final commit text stay separate
- candidate anchor range policy for IMK clients with known or unknown selection ranges
- candidate anchor resolver for IMK rects, line-height rects, Accessibility rects, scoped last-anchor fallback, safe screen fallback, and debug tracing
- custom AppKit candidate presentation styled as a compact macOS candidate list
- candidate panel renderer with raw input, locked prefix, and continuation rows
- shortcut-to-commit behavior
- key intent modeling for key down, key up, modifier flag changes, cancel, delete, navigation keys, punctuation, and numeric candidate selection
- persisted `InputModeState` for text mode, punctuation language, and symbol width, refreshed from saved preferences at new composition/direct symbol boundaries, with `Option + .` toggling punctuation language for the active session
- runtime loading of user-owned JSON/TSV lexicon directories into the local Chinese engine
- runtime lexicon snapshot refresh at new-composition boundaries so local dictionary file changes can be picked up without reinterpreting active marked text
- persisted prefix selection history used as a local-only ranking signal
- `InputTaskSupervisor` cancellation for local candidates, AI, runtime lexicon reload, and panel rendering work
- testable host/client seams for the IMK controller boundary
- async suggestion pipeline wiring
- Level 0 no-provider routing for protected input
- minimal InputMethodKit server bootstrap guarded by `canImport(InputMethodKit)`
- `KnowTypeInputMethodApp` bundle entry assembled by `scripts/build-inputmethod-bundle.sh`

The AppKit candidate panel is the active candidate presentation for the IMK bundle. This avoids the `IMKCandidates` failure mode where the system panel accepts data but does not become visible in some host apps. Prefix rows are rendered first, continuation rows after them, and raw input is rendered only while no suggestion exists. `Space` commits the visible snapshot for the current raw input; it does not commit hidden fallback candidates that are absent from the panel.

When a provider is configured, the IMK controller publishes raw marked text immediately and waits for local prefix candidates and provider-backed AI recommendation rows asynchronously. The first candidate publication does not include local fallback continuation rows. If the provider fails or returns no usable continuation, the async update keeps the AI slot unavailable instead of substituting local fallback text, so `Space` still commits the visible traditional prefix when it exists while `Tab` does not present fake AI output. Without a provider, local fallback continuations are controlled only by the local fallback preference, not by the cloud continuation toggle.

The IMK controller directly marks composing text with `IMKTextInput.setMarkedText` and replaces the active marked range on commit. Candidate anchor lookup is delegated to `CandidateAnchorResolver`, which prefers fresh IMK text rects, then line-height rects, then Accessibility focused-range bounds if permission is already granted, then a same-composition scoped last usable anchor, and finally a stable safe point inside the screen visible frame. The panel no longer follows the mouse pointer when host text geometry is temporarily unavailable.

Product commit decisions are shared through the session commit policy and coordinator: `Space` commits a full prefix or applies a selected segment when visible, pending `Space` commits the current raw/composition display without waiting for hidden candidates, `Return` commits the raw composition, `Tab` commits AI only when that slot is ready, `Option+number` commits a continuation, numeric candidate shortcuts commit full rows or apply segment rows, punctuation commits the current composition display plus mapped punctuation, and `Option+R` requests explicit polish only. The IMK controller remains responsible for host integration details such as client lookup, marked text, insertion, palette visibility, input mode state ownership, and window anchoring, but those details now route through `InputControllerCoordinator` and small host/client seams so controller-adjacent behavior can be unit-tested without installing the input method.

Candidate paging keeps 6 visible rows per page in adaptive horizontal mode so short candidates do not force a vertical panel. Vertical-list mode can show up to 9 visible rows per page. Arrow keys move one selectable row, PageDown/PageUp preserve the selected row's visible offset on the target page, and short final pages clamp to their last available row.

The IMK controller records recently committed prefix candidates in memory, persists them through `UserSelectionHistoryPersistence`, and passes a snapshot through `InputContext.userSelectionHistory` to both immediate local suggestions and async provider-backed suggestion loading. Persistence appends newly selected prefixes on a shared serial queue and controller shutdown waits for pending writes, so stale snapshots do not overwrite newer selections from another host app. The ranking signal stays local; providers still receive only the normalized request fields defined by `LLMRequest`.

MVP manual acceptance still must verify candidate window behavior in host apps because IMK text input behavior varies across AppKit, browser, Electron, and terminal contexts.
