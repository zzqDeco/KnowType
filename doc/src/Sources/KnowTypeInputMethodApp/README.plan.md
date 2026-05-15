# Sources/KnowTypeInputMethodApp

`KnowTypeInputMethodApp` is the macOS background process entry point for the installable MVP bundle.

It starts `IMKServer` with the connection name from `Info.plist` and keeps an accessory `NSApplication` run loop alive. The actual per-client composition behavior lives in `KnowTypeInputController` inside `KnowTypeInputMethod`.

Local bundle assembly is intentionally script-based for v1:

- `scripts/build-inputmethod-bundle.sh` builds the executable and writes `dist/KnowType.app`.
- SwiftPM resource bundles such as `KnowType_KnowTypeCore.bundle` are copied into `Contents/Resources`, where the signed app bundle can contain them.
- `scripts/install-inputmethod.sh` copies the bundle into `~/Library/Input Methods`.
- `scripts/uninstall-inputmethod.sh` removes that local bundle.
