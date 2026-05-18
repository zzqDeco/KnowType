# Sources/KnowTypePreferencePane

`KnowTypePreferencePane` is the System Settings entry for KnowType configuration.

The target builds a dynamic library that is packaged as `KnowType.prefPane` by `scripts/build-preference-pane.sh`. Its `NSPreferencePane` principal class installs an `NSHostingView` with `KnowTypeSettingsRootView`, so PreferencePane settings are the same controls used by the settings app and IMK preferences window.

The pane is installed into `~/Library/PreferencePanes/KnowType.prefPane` by `scripts/install-inputmethod.sh`. Diagnostics verify its bundle identifier, executable, principal class, and codesign status.
