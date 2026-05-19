# scripts/build-preference-pane.sh

`scripts/build-preference-pane.sh` packages the `KnowTypePreferencePane` dynamic product into `dist/KnowType.prefPane`.

The script copies the PreferencePane `Info.plist`, places the SwiftPM-built `libKnowTypePreferencePane.dylib` in `Contents/Frameworks`, and links a small `MH_BUNDLE` executable at `Contents/MacOS/KnowTypePreferencePane` with an `@loader_path/../Frameworks` rpath. This keeps System Settings on the normal PreferencePane bundle/principal-class loading path instead of asking it to load a raw dylib as the pane executable.

The script adds the KnowType icon resource, signs the bundle with the same Apple Development fallback behavior used by the input-method bundle, and prints the built pane path.

`--version` and `--build` override the copied `Info.plist` before signing. The
source plist stays stable while release artifacts can carry the tag version and
CI build number.
