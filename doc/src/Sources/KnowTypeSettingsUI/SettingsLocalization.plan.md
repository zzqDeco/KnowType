# SettingsLocalization

`SettingsLocalization` owns settings-facing localized string lookup for
`KnowTypeSettingsUI` and the input-method settings menu.

## Responsibility

- Resolve settings copy from the bundled `Localizable.strings` resources.
- Default normal UI lookup to Simplified Chinese by checking `zh-Hans` before
  system preferred languages.
- Preserve explicit English lookup through `localeIdentifier: "en"` or
  region-specific English identifiers such as `en-US`.
- Fall back from missing Simplified Chinese keys to English, then to the key.

## Boundaries

- This type does not choose input-source display names; those stay in
  InputMethodKit bundle resources.
- Provider output, system errors, and external diagnostic text are not
  translated here.
- Settings views should consume keys through this helper instead of hard-coding
  user-visible copy.

## Tests

- `ProviderProfilesPresentationTests`
- `InputMethodMenuBuilderTests`
