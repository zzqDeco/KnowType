# Sources/KnowTypeInputMethod

`KnowTypeInputMethod` owns input-method interaction behavior.

Current package-level implementation covers:

- explicit IME session mode modeling for empty, composing, candidate, AI-pending, polish, and protected ASCII/no-correction input
- candidate panel view model
- session commit policy for raw/prefix numeric shortcuts and native candidate selections
- candidate anchor range policy for IMK clients with known or unknown selection ranges
- custom AppKit candidate presentation styled as a compact macOS candidate list
- candidate panel renderer with raw input, locked prefix, continuation rows, and native-style 9-item candidate pages
- shortcut-to-commit behavior
- key intent modeling for key down, key up, modifier flag changes, cancel, delete, navigation keys, and numeric candidate selection
- async suggestion pipeline wiring
- Level 0 no-provider routing for protected input
- minimal InputMethodKit server bootstrap guarded by `canImport(InputMethodKit)`
- `KnowTypeInputMethodApp` bundle entry assembled by `scripts/build-inputmethod-bundle.sh`

The AppKit candidate panel is the active candidate presentation for the IMK bundle. This avoids the `IMKCandidates` failure mode where the system panel accepts data but does not become visible in some host apps. Prefix rows are rendered first, continuation rows after them, and raw input is rendered only while no suggestion exists.

The IMK controller directly marks composing text with `IMKTextInput.setMarkedText` and replaces the active marked range on commit. Candidate anchor lookup prefers marked range end, falls back through marked/selected range starts and ends, tries line-height rectangles at the same indexes, asks the client for the IMK current insertion-point range, then keeps the last usable text anchor. The panel no longer follows the mouse pointer when text geometry is temporarily unavailable.

Product commit decisions are shared through the session commit policy: `Space` commits the best prefix, `Tab` commits prefix plus first continuation, `Option+number` commits a continuation, numeric candidate shortcuts commit prefix rows from the current candidate page, `PageDown` / `PageUp`, `-` / `=`, and `[` / `]` page through larger candidate lists, and `Option+R` requests explicit polish only. The IMK controller remains responsible for host integration details such as client lookup, marked text, insertion, palette visibility, and window anchoring.

MVP manual acceptance still must verify candidate window behavior in host apps because IMK text input behavior varies across AppKit, browser, Electron, and terminal contexts.
