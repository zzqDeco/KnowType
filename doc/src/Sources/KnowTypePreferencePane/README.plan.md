# Sources/KnowTypePreferencePane

`KnowTypePreferencePane` is the System Settings entry for KnowType configuration.

The target builds a dynamic library that is packaged as `KnowType.prefPane` by `scripts/build-preference-pane.sh`. Its `NSPreferencePane` principal class overrides `loadMainView()` and installs an `NSHostingView` with `KnowTypeSettingsRootView`, so the pane works without a nib and exposes the same controls used by the settings app and IMK preferences window.

The pane is installed into `~/Library/PreferencePanes/KnowType.prefPane` by `scripts/install-inputmethod.sh`. Diagnostics verify its bundle identifier, executable, principal class, and codesign status.
