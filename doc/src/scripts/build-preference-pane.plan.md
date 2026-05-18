# scripts/build-preference-pane.sh

`scripts/build-preference-pane.sh` packages the `KnowTypePreferencePane` dynamic product into `dist/KnowType.prefPane`.

The script copies the PreferencePane `Info.plist`, installs the SwiftPM-built `libKnowTypePreferencePane.dylib` as `Contents/MacOS/KnowTypePreferencePane`, adds the KnowType icon resource, signs the bundle with the same Apple Development fallback behavior used by the input-method bundle, and prints the built pane path.
