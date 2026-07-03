# System Settings Preference Pane

## Summary

KnowType now exposes its configuration through Apple-supported system-level settings surfaces instead of relying only on the standalone SwiftPM settings executable:

- `KnowType.prefPane` can be installed into `~/Library/PreferencePanes` for System Settings access.
- The InputMethodKit menu exposes a localized settings item through
  `showPreferences:`.
- The settings app, preference pane, and IMK preferences window share the same SwiftUI root view and shared preference stores.

Apple does not provide a public API for embedding third-party input-method controls inside the Keyboard/Input Sources detail page, so the supported System Settings path is a user-installed PreferencePane.

## Delivered Changes

- Added `KnowTypeSettingsUI` as the reusable settings module.
- Added `KnowTypePreferencePane` and `Resources/PreferencePane/Info.plist`.
- Added `scripts/build-preference-pane.sh` and updated `scripts/install-inputmethod.sh` to install `KnowType.prefPane`.
- Added `InputMethodServerPreferencesWindowControllerClass` and `KnowTypePreferencesWindowController` for IMK preferences.
- Added runtime preferences for candidate page size, candidate layout mode, AI continuation enablement, continuation length, and continuation count. The legacy input-scheme value remains persisted for compatibility but is not exposed by the Rime-only settings UI.
- The input method reads runtime preferences at startup and new composition boundaries, then applies them without changing an active composition.

## Verification

```bash
swift test
scripts/build-preference-pane.sh
git diff --check
```
