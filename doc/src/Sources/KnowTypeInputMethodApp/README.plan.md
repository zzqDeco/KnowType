# Sources/KnowTypeInputMethodApp

`KnowTypeInputMethodApp` is the macOS background process entry point for the installable MVP bundle.

It starts `IMKServer` with the connection name from `Info.plist` and keeps a background `NSApplication` run loop alive. On launch it registers the installed input source only when TIS has no existing KnowType sources, enables the parent/mode records from the signed app bundle context, then emits unified logs under `com.knowtype.inputmethod.KnowType/input-method-app`. When launched by the install script with `--knowtype-install-activate`, it also requests selection of the visible KnowType input mode and logs the app-local `TISSelectInputSource` status plus current input source. The actual per-client composition behavior lives in `KnowTypeInputController` inside `KnowTypeInputMethod`.

Local bundle assembly is intentionally script-based for v1:

- `scripts/build-inputmethod-bundle.sh` builds the executable and writes `dist/KnowType.app`.
- SwiftPM resource bundles such as `KnowType_KnowTypeCore.bundle` are copied into `Contents/Resources`, where the signed app bundle can contain them.
- `scripts/install-inputmethod.sh` copies the bundle into `~/Library/Input Methods` and launches the installed app with the activation flag so TIS registration and enabling are attributed to the signed bundle context.
- `scripts/uninstall-inputmethod.sh` removes that local bundle.
