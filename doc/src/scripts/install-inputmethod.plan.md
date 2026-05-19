# scripts/install-inputmethod.sh

## Responsibility

Installs the locally built KnowType input method bundle into
`~/Library/Input Methods/KnowType.app`.

## Boundaries

- The script copies and prepares the local development bundle.
- It does not prove target-app typing behavior; manual acceptance still must
  type in real host apps.

## Behavior Notes

- The script switches away from any current KnowType source, replaces
  `~/Library/Input Methods/KnowType.app`, clears quarantine, and refreshes the
  installed path with `lsregister -f`.
- It terminates any running `KnowTypeInputMethodApp`, replaces the bundle, then
  asks the newly installed app to disable stale `.Mode` TIS modes and unregister
  older KnowType LaunchServices paths.
- Local installs inject a timestamp `CFBundleVersion` by default so
  LaunchServices and TIS do not keep reusing stale metadata from a previous
  development build with the same source-controlled version.
- It executes the installed app with
  `--knowtype-install-activate` so registration, enabling, and best-effort
  selection happen from the signed app context before `IMKServer` starts.
- It uses `knowtype-inputsource-tool repair-preferences --add-active` before
  and after app activation to keep local development caches aligned with the
  System Settings add result: `.Hans` in HIToolbox/history and parent anchor
  plus `.Hans` in `com.apple.inputsources`.
- After activation, it opens the installed app as a background agent so the
  `IMKServer` connection is available to Text Input clients.
- TIS registration, enablement, and selection remain attributed to
  `KnowType.app`; the SwiftPM helper is used only for scoped preference repair.
- macOS 15 local policy issues may still require the SystemPolicyRule profile
  flow before selection works reliably.

## Tests

- `scripts/smoke-inputmethod-install.sh`
- Manual `doc/mvp-acceptance.plan.md` install gate
