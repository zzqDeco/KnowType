# InputControllerHostClientSeams

`InputControllerHostClientSeams` defines the internal protocols that make the IMK controller boundary unit-testable.

Current seams:

- `InputClientMarkedText` preserves the carrier type for IMK marked writes.
  Inline composition and compatibility placeholders are forwarded as
  `NSAttributedString` values with marked-text attributes; plain strings remain
  available only as an explicit carrier for tests or future narrow uses.
- `InputControllerClient` covers the host text client operations used by the input method: bundle id lookup, selected/marked ranges, geometry probes, marked text writes, and commit insertion.
- `InputControllerHost` covers operations owned by the IMK wrapper or AppKit host: current client lookup, fallback composition updates, candidate panel updates, panel hiding, and delayed main-queue re-anchor scheduling.
- `InputControllerUserSelectionHistoryPersisting` lets lifecycle tests assert flush behavior without depending on the file-backed persistence queue.
- `IMKInputControllerClientAdapter` is the production adapter from
  `IMKTextInput` to `InputControllerClient`; it forwards attributed marked
  payloads as attributed objects instead of flattening them to plain strings.

Provider adapters and product logic must not depend on these seams. They are only for the input-method host/client boundary.
