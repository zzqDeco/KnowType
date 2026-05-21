# KnowTypeSettingsApp

## Responsibility

`KnowTypeSettingsApp` is a developer preview macOS app host for the shared
settings UI.

## Boundaries

- Reusable settings views and ViewModels stay in `KnowTypeSettingsUI`.
- Primary user hosting belongs to `KnowTypeInputMethod` through the input-method
  menu. Compatibility System Settings hosting belongs to `KnowTypePreferencePane`.

## Behavior Notes

- The app should present the same provider, input behavior, privacy, user-data,
  and diagnostics surfaces as the other settings hosts.
- It is not installed by default and is not packaged into the local MVP release
  artifact.
- Product behavior must not fork between settings entry points.

## Tests

- `ProviderProfilesViewModelTests`
- `LexiconSettingsViewModelTests`
- `RuntimePreferencesViewModelTests`
