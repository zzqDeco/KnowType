# KnowTypeSettingsApp

## Responsibility

`KnowTypeSettingsApp` is the standalone macOS app host for the shared settings
UI.

## Boundaries

- Reusable settings views and ViewModels stay in `KnowTypeSettingsUI`.
- Input-method menu hosting belongs to `KnowTypeInputMethod`; System Settings
  hosting belongs to `KnowTypePreferencePane`.

## Behavior Notes

- The app should present the same provider, input behavior, privacy, lexicon,
  and debug install surfaces as the other settings hosts.
- Product behavior must not fork between settings entry points.

## Tests

- `ProviderProfilesViewModelTests`
- `LexiconSettingsViewModelTests`
- `RuntimePreferencesViewModelTests`
