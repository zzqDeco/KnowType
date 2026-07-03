# Native Settings UI Polish

## Summary

- Replace the settings UI's English top-tab layout with a Simplified Chinese,
  macOS-native sidebar and grouped-form layout.
- Keep the primary settings entry in the IMK input menu. The standalone settings
  app and optional prefPane continue to reuse the shared root view, but are not
  default user install surfaces.

## Scope

- Update `KnowTypeSettingsUI` to render a `NavigationSplitView` sidebar with
  `输入`, `候选窗`, `Rime 与用户数据`, `AI 续写`, `隐私`, and `诊断`.
- Add settings localization resources with `zh-Hans` as the default
  user-facing path. English resources remain for explicit English locale
  lookups and missing-key fallback.
- Simplify the AI provider page into one grouped form instead of nesting a
  second split view inside the settings detail.
- Update the IMK preferences window title and chrome to use the same localized
  settings title resources as the settings UI.

## Implementation

- The sidebar owns section search and system-symbol labels; details render
  grouped forms with native SwiftUI controls.
- Provider kinds, model names, URL, API Key, Rime, macOS, and InputMethodKit stay
  in English where they are technical identifiers.
- Diagnostics show concise Chinese setup guidance first and keep long shell
  commands inside a disclosure section.
- Settings persistence and provider validation remain in existing ViewModels;
  this work changes presentation and window hosting only.

## Test Plan

- `ProviderProfilesPresentationTests` covers Chinese sidebar order, search,
  localization resources, and provider presentation labels.
- `LexiconSettingsPresentationTests` and `DebugInstallGuidanceTests` cover
  Chinese settings copy.
- `InputMethodMenuBuilderTests` verifies the preferences window title and native
  toolbar style.
- Full validation: `swift test --quiet`,
  `./scripts/smoke-inputmethod-install.sh`,
  `./scripts/smoke-inputmethod-install.sh --with-prefpane`,
  `./scripts/perf-input-hotpath.sh`, and `git diff --check`.

## Assumptions

- This slice does not change input-source registration, appex behavior,
  Rime-only hot paths, or main/release flow.
- The input menu item, opened window title, and settings content default to
  Simplified Chinese.
