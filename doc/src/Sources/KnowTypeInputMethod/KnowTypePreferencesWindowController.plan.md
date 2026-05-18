# KnowTypePreferencesWindowController

## Responsibility

`KnowTypePreferencesWindowController` hosts the shared SwiftUI settings root
inside the InputMethodKit preferences window.

## Boundaries

- Settings behavior and persistence stay in `KnowTypeSettingsUI`.
- The controller owns AppKit window hosting only.

## Behavior Notes

- The input-method menu opens KnowType settings without relying on a nib-backed
  default preferences loader.
- The settings app, preference pane, and IMK preferences window should share the
  same SwiftUI root view and stores.

## Tests

- `InputMethodBundleInfoTests`
- Settings ViewModel tests for behavior behind the hosted UI
