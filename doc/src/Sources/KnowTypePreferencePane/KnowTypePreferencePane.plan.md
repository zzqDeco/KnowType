# KnowTypePreferencePane

## Responsibility

`KnowTypePreferencePane` hosts the shared SwiftUI settings root inside a
user-installed macOS PreferencePane.

## Boundaries

- Settings state and behavior stay in `KnowTypeSettingsUI`.
- Building and installing the preference pane is handled by
  `scripts/build-preference-pane.sh` and the local install workflow.

## Behavior Notes

- The preference pane is the supported system-level settings surface because
  macOS does not provide a public API for embedding third-party IME controls in
  the Keyboard/Input Sources detail page.
- It must load without requiring nib-backed settings resources.

## Tests

- `swift test`
- `scripts/build-preference-pane.sh`
