# Input Source Display Name

## Goal

Make the installed KnowType input source appear in macOS UI as `KnowType` / `知键` instead of the raw input-source id.

## Behavior

- Package `en.lproj/InfoPlist.strings` and `zh-Hans.lproj/InfoPlist.strings` into the input-method bundle resources.
- Localize the single active input source id `com.knowtype.inputmethod.KnowType`.
- Keep the menu icon label as `知`; the full menu/settings name comes from `InfoPlist.strings`.
- Warn in diagnostics when `kTISPropertyLocalizedName` still resolves to the raw bundle id.
- Warn when TIS reports multiple registrations for the same input-source id, because repeated local installs can leave stale menu/cache entries until logout or reboot.
- Keep the dedicated `knowtype-inputsource-tool` executable for status, dump, and manual selection retries instead of inline `swift -` snippets, so diagnostics identify a KnowType-specific helper rather than `swift-frontend`.
- Let the default install path launch the installed signed app with its activation flag so registration/enabling is attributed to the input-method bundle context.
- Report persisted HIToolbox selected/enabled input-source preferences separately from the helper process's current TIS context, so Apple Pinyin is not mistaken for a successful KnowType typing test.

## Verification

```bash
swift test --filter InputMethodBundleInfoTests
swift build --product knowtype-inputsource-tool
bash -n scripts/lib/inputsource-tool.sh scripts/build-inputmethod-bundle.sh scripts/diagnose-inputmethod.sh
./scripts/build-inputmethod-bundle.sh
find dist/KnowType.app/Contents/Resources -name InfoPlist.strings -print
```

After reinstalling, run:

```bash
./scripts/diagnose-inputmethod.sh --strict
```

The localized input-source name should be `KnowType` on English systems or `知键` on Simplified Chinese systems. `com.knowtype.inputmethod.KnowType` is the current visible source id; `com.knowtype.inputmethod.KnowType.Hans` and `.Mode` are legacy cleanup only. If the input menu still shows stale duplicate rows, run the repair script and then log out or reboot to force HIToolbox/TIS to rebuild its cached input-source menu.
