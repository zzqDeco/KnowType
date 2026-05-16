# Local Input Source System Policy

## Goal

Make the local failure mode explicit when KnowType is installed and registered
but macOS keeps the active input source on Apple Pinyin.

## Finding

The local bundle can pass `codesign --verify`, register TIS parent and mode
records, and still fail Gatekeeper execute assessment:

```text
GatekeeperPolicyScanError Code=-67018
Code did not match any currently allowed policy
```

On macOS 15, `spctl --add` exits with the deprecated-operation status and does
not create an allow rule. Directly writing `com.apple.HIToolbox`
`AppleSelectedInputSources` is also not reliable because the system selection
chain can restore Apple Pinyin when the bundle is not allowed by system policy.

## Implementation

- Add `scripts/create-local-system-policy-profile.sh`.
- The script reads the installed bundle's designated code requirement and
  generates `dist/KnowTypeLocalSystemPolicy.mobileconfig`.
- The profile payload type is `com.apple.systempolicy.rule`, operation
  `operation:execute`.
- The script can open the generated profile for manual System Settings
  installation with `--open`.
- `scripts/diagnose-inputmethod.sh` now points to this profile path when
  Gatekeeper rejects a local Apple Development build.
- The input-method bundle metadata is aligned with IMKit expectations:
  `LSBackgroundOnly` is `true`, `LSUIElement` is omitted, and the Chinese
  repertoire uses `zh-Hans` instead of the script-only `Hans`.
- Documentation is kept in `doc/`, not in the product README.

## Verification

```bash
bash -n scripts/create-local-system-policy-profile.sh scripts/diagnose-inputmethod.sh
./scripts/create-local-system-policy-profile.sh --output /tmp/KnowTypeLocalSystemPolicy.mobileconfig
plutil -lint /tmp/KnowTypeLocalSystemPolicy.mobileconfig
swift test
git diff --check
```

Manual verification after profile installation:

```bash
spctl --assess --type execute --verbose=4 "$HOME/Library/Input Methods/KnowType.app"
./scripts/select-inputmethod.sh --require-selected
./scripts/diagnose-inputmethod.sh --strict --logs --log-lookback 10m
```
