# Input Source Display Name

## Goal

Make the installed KnowType input source appear in macOS UI as `KnowType` / `知键` instead of the raw mode id `com.knowtype.inputmethod.KnowType.Mode`.

## Behavior

- Package `en.lproj/InfoPlist.strings` and `zh-Hans.lproj/InfoPlist.strings` into the input-method bundle resources.
- Localize both the parent input method id and the visible mode id.
- Keep the menu icon label as `知`; the full menu/settings name comes from `InfoPlist.strings`.
- Warn in diagnostics when `kTISPropertyLocalizedName` still resolves to the raw mode id.
- Warn when TIS reports multiple registrations for the same mode id, because repeated local installs can leave stale menu/cache entries until logout or reboot.
- Route TIS registration, enabling, selection, and status checks through the dedicated `knowtype-inputsource-tool` executable instead of inline `swift -` snippets, so macOS permission prompts identify a KnowType helper rather than `swift-frontend`.
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

The localized mode name should be `KnowType` on English systems or `知键` on Simplified Chinese systems. If the input menu still shows stale duplicate rows, log out or reboot to force HIToolbox/TIS to rebuild its cached input-source menu.
