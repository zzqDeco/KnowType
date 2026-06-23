# Sources/KnowTypeInputSourceSupport

`KnowTypeInputSourceSupport` owns the shared identifiers used by the traditional InputMethodKit bundle and local input-source tooling.

Current IDs:

- active single input source / IMK server identity: `com.knowtype.inputmethod.KnowType`
- legacy modes kept only for cleanup: `com.knowtype.inputmethod.KnowType.Hans`, `com.knowtype.inputmethod.KnowType.Mode`
- IMK connection name: `KnowType_Connection`

Swift code must import this target instead of hardcoding these IDs. Shell scripts mirror the same values in `scripts/lib/inputsource-ids.sh`, and tests check the Swift constants, shell constants, and `Resources/InputMethod/Info.plist` stay aligned.
