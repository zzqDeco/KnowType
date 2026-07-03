# Sources/KnowTypePreferencePane

`KnowTypePreferencePane` is the compatibility System Settings entry for
KnowType configuration. The primary user-facing settings entry is the
InputMethodKit menu item localized by `SettingsLocalization`, defaulting to
`KnowType 设置...`.

The target builds a dynamic library that is packaged as `KnowType.prefPane` by `scripts/build-preference-pane.sh`. The installed pane uses a loadable bundle executable in `Contents/MacOS` and keeps the SwiftPM library in `Contents/Frameworks`, so System Settings can instantiate the `NSPreferencePane` principal class normally.

`KnowTypePreferencePane` overrides `loadMainView()` and installs an `NSHostingView` with `KnowTypeSettingsRootView`, so the pane works without a nib and exposes the same controls used by the settings app and IMK preferences window.

The pane is installed into `~/Library/PreferencePanes/KnowType.prefPane` only
when `scripts/install-inputmethod.sh --with-prefpane` is used. Diagnostics
verify its bundle identifier, loadable-bundle executable, principal class,
packaged SwiftPM library, and codesign status when present.
