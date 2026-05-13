# Sources/KnowTypeInputMethod

`KnowTypeInputMethod` owns input-method interaction behavior.

Current package-level implementation covers:

- candidate panel view model
- custom candidate selection policy for raw/prefix numeric shortcuts
- candidate anchor range policy for IMK clients with known or unknown selection ranges
- custom AppKit candidate panel window
- shortcut-to-commit behavior
- async suggestion pipeline wiring
- minimal InputMethodKit server bootstrap guarded by `canImport(InputMethodKit)`

The custom panel is the active candidate presentation for the IMK bundle. Native `IMKCandidates` remains available only as protocol surface for legacy candidate callbacks; KnowType avoids showing both panels at once.
