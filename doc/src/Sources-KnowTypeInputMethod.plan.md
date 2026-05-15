# Sources/KnowTypeInputMethod

`KnowTypeInputMethod` owns input-method interaction behavior.

Current package-level implementation covers:

- explicit IME session mode modeling for empty, composing, candidate, AI-pending, polish, and protected ASCII/no-correction input
- candidate panel view model
- session commit policy for raw/prefix numeric shortcuts and native candidate selections
- candidate anchor range policy for IMK clients with known or unknown selection ranges
- candidate anchor resolver for IMK rects, line-height rects, Accessibility rects, scoped last-anchor fallback, and debug tracing
- custom AppKit candidate presentation styled as a compact macOS candidate list
- candidate panel renderer with raw input, locked prefix, and continuation rows
- shortcut-to-commit behavior
- key intent modeling for key down, key up, modifier flag changes, cancel, delete, navigation keys, punctuation, and numeric candidate selection
- session-local Chinese/English punctuation mode with `Option + .` toggle
- async suggestion pipeline wiring
- Level 0 no-provider routing for protected input
- minimal InputMethodKit server bootstrap guarded by `canImport(InputMethodKit)`
- `KnowTypeInputMethodApp` bundle entry assembled by `scripts/build-inputmethod-bundle.sh`

The AppKit candidate panel is the active candidate presentation for the IMK bundle. This avoids the `IMKCandidates` failure mode where the system panel accepts data but does not become visible in some host apps. Prefix rows are rendered first, continuation rows after them, and raw input is rendered only while no suggestion exists.

The IMK controller directly marks composing text with `IMKTextInput.setMarkedText` and replaces the active marked range on commit. Candidate anchor lookup is delegated to `CandidateAnchorResolver`, which prefers fresh IMK text rects, then line-height rects, then Accessibility focused-range bounds if permission is already granted, and finally a same-composition scoped last usable anchor. The panel no longer follows the mouse pointer when host text geometry is temporarily unavailable; if no valid anchor exists, the panel state is hidden so invisible rows do not consume navigation or numeric candidate shortcuts.

Product commit decisions are shared through the session commit policy: `Space` commits the best prefix, `Tab` commits prefix plus first continuation, `Option+number` commits a continuation, numeric candidate shortcuts commit raw/prefix rows, punctuation commits the current composition plus mapped punctuation, and `Option+R` requests explicit polish only. The IMK controller remains responsible for host integration details such as client lookup, marked text, insertion, palette visibility, punctuation mode, and window anchoring.

MVP manual acceptance still must verify candidate window behavior in host apps because IMK text input behavior varies across AppKit, browser, Electron, and terminal contexts.
