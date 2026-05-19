# Sources/KnowTypeInputMethodApp

`KnowTypeInputMethodApp` is the macOS agent process entry point for the installable MVP bundle.

It starts `IMKServer` with the connection name from `Info.plist` and keeps an `LSUIElement` `NSApplication` run loop alive during normal input-method launch. Its command-line activation flags run before `IMKServer` starts: `--knowtype-install-activate` registers, enables, and selects the visible `.Hans` input mode from the signed installed app context, `--knowtype-disable-input-source` disables KnowType records through TIS before a System Settings re-add, `--knowtype-purge-legacy` disables legacy `.Mode` sources and cleans LaunchServices state, `--knowtype-switch-away` moves away from KnowType before replacement, and the narrower register/enable/select flags support script retries. Stale `.Mode` registrations are counted for logs but are not activation targets. The actual per-client composition behavior lives in `KnowTypeInputController` inside `KnowTypeInputMethod`.

Local bundle assembly is intentionally script-based for v1:

- `scripts/build-inputmethod-bundle.sh` builds the executable and writes `dist/KnowType.app`.
- SwiftPM resource bundles such as `KnowType_KnowTypeCore.bundle` are copied into `Contents/Resources`, where the signed app bundle can contain them.
- `scripts/install-inputmethod.sh` copies the bundle into `~/Library/Input Methods`, then executes the installed app with purge and activation flags so cleanup, registration, enabling, and best-effort selection run from the app context before the server starts.
- `scripts/repair-inputmethod-selection.sh` cleans stale local LaunchServices records and visible legacy TIS modes when repeated development installs make the input menu bounce back to another source. It also invokes the helper's explicit `repair-preferences` fallback to keep HIToolbox/history on `.Hans` and keep `com.apple.inputsources` on the System Settings-compatible parent anchor plus `.Hans` rows while leaving unrelated input sources untouched.
- `scripts/uninstall-inputmethod.sh` removes that local bundle.
