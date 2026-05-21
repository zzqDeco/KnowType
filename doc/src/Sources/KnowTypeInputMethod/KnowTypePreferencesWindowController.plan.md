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
- The window uses native macOS settings chrome where available, including
  preference toolbar style, autosaved frame placement, a fixed minimum size, and
  disabled tabbing.
- The IMK preferences window is the primary user-facing settings entry. The
  developer settings app and compatibility PreferencePane should share the same
  SwiftUI root view and stores without becoming the default install path.

## Tests

- `InputMethodMenuBuilderTests`
- Settings ViewModel tests for behavior behind the hosted UI
