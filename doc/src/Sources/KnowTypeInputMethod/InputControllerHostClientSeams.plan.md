# InputControllerHostClientSeams

`InputControllerHostClientSeams` defines the internal protocols that make the IMK controller boundary unit-testable.

Current seams:

- `InputClientMarkedText` preserves the carrier type for IMK marked writes.
  Inline composition and compatibility placeholders are forwarded as
  `NSAttributedString` values with marked-text attributes; plain strings remain
  available only as an explicit carrier for tests or future narrow uses.
- `InputControllerClient` covers the host text client operations used by the input method: bundle id lookup, selected/marked ranges, geometry probes, marked text writes, and commit insertion.
- `InputControllerHost` covers operations owned by the IMK wrapper or AppKit host: current client lookup, fallback composition updates, candidate panel updates, panel hiding, delayed main-queue candidate re-anchor scheduling, and immediate post-insert caret verification scheduling.
- Candidate re-anchor and post-insert caret verification are intentionally separate host operations. Re-anchor may be delayed and stale-gated for panel placement; AI accepted-feedback verification must run on the next main-queue turn so a fast Delete after accepting AI text is not dropped as `delete_before_verified`.
- `InputControllerUserSelectionHistoryPersisting` lets lifecycle tests assert flush behavior without depending on the file-backed persistence queue.
- `IMKInputControllerClientAdapter` is the production adapter from
  `IMKTextInput` to `InputControllerClient`; it forwards attributed marked
  payloads as attributed objects instead of flattening them to plain strings.

Provider adapters and product logic must not depend on these seams. They are only for the input-method host/client boundary.
