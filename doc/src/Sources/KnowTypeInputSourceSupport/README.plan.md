# Sources/KnowTypeInputSourceSupport

`KnowTypeInputSourceSupport` owns shared identifiers and pure support helpers used by the traditional InputMethodKit bundle and local input-source tooling.

Current IDs:

- parent input method / IMK server identity: `com.knowtype.inputmethod.KnowType`
- active visible input mode: `com.knowtype.inputmethod.KnowType.Hans`
- legacy modes kept only for cleanup: `com.knowtype.inputmethod.KnowType.Mode`
- stable IMK connection name: `com.knowtype.inputmethod.KnowType_Connection`

Swift code must import this target instead of hardcoding these IDs. Shell scripts mirror the same values in `scripts/lib/inputsource-ids.sh`, and tests check the Swift constants, shell constants, and `Resources/InputMethod/Info.plist` stay aligned.

This target also contains the shared LaunchServices and Text Input Source helper layer for install/debug plumbing:

- Input-method startup routing: `KnowTypeInputMethodStartupPolicy.run` keeps normal serve-only host launch mutually exclusive from explicit installer/repair command execution. Its injected closures let tests model parent and mode records that never become visible without performing a real wait.
- LaunchServices parsing and cleanup: `stripLSRegisterSuffix`, `expandedPath`, `canonicalBundlePath`, `parseLaunchServicesPaths`, `launchServicesPaths`, and `unregisterStaleLaunchServices`.
- TIS source access: id, bundle id, current-source lookup, string/bool/input-mode property reads, distributed notification posting, source signatures, dedupe, activation/selection target preference, parent-before-mode enable ordering, mode-before-parent disable ordering, visible user-mode counting, and bounded wait helpers.

The LaunchServices helper accepts a process runner and warning sink so tests can cover stale-record cleanup without invoking the real `lsregister` tool. TIS helpers expose pure `KnowTypeInputSourceProperties` rules for ordering/counting tests; code that touches real `TISInputSource` records remains limited to install, app activation, and diagnostics boundaries.

This target must not grow input-method composition, candidate panel, Rime, provider, AI, or Settings UI logic. It is shared install/source support only.
