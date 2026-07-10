# InputControllerHostClientSeams

`InputControllerHostClientSeams` defines the internal protocols that make the IMK controller boundary unit-testable.

Current seams:

- `InputClientMarkedText` preserves the carrier type for IMK marked writes.
  Inline composition and compatibility placeholders are forwarded as
  `NSAttributedString` values with marked-text attributes; plain strings remain
  available only as an explicit carrier for tests or future narrow uses.
- `InputControllerClient` covers the host text client operations used by the
  input method: bundle id lookup, selected/marked ranges, geometry probes,
  marked text writes, commit insertion, and an optional character-before-caret
  query.
- `InputControllerHost` covers operations owned by the IMK wrapper or AppKit host: current client lookup, fallback composition updates, ordered candidate-panel frame application, delayed main-queue candidate re-anchor scheduling, and immediate post-insert caret verification scheduling.
- Candidate-panel visibility uses a single `applyCandidatePanelFrame(_:locale:)`
  seam. Visible, hidden, layout-impossible, and stale-update frames keep their
  presentation generation across the host/AppKit boundary so the window layer
  can drop old frames that arrive after a newer hide.
- Candidate re-anchor and post-insert caret verification are intentionally separate host operations. Re-anchor may be delayed and stale-gated for panel placement; AI accepted-feedback verification must run on the next main-queue turn so a fast Delete after accepting AI text is not dropped as `delete_before_verified`.
- `InputControllerUserSelectionHistoryPersisting` lets lifecycle tests assert flush behavior without depending on the file-backed persistence queue.
- `IMKInputControllerClientAdapter` is the production adapter from
  `IMKTextInput` to `InputControllerClient`; it forwards attributed marked
  payloads as attributed objects instead of flattening them to plain strings.
  For a collapsed known caret, it can request exactly one preceding UTF-16 unit
  through `attributedSubstring(from:)`. The coordinator invokes this only for
  idle period punctuation; ordinary keys never read document context.

The context seam returns only a `Character?` and diagnostics classify it as
digit, other, or unknown. Raw surrounding text must not cross into logs.

Provider adapters and product logic must not depend on these seams. They are only for the input-method host/client boundary.
