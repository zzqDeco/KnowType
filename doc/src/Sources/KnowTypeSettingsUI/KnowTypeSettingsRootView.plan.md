# KnowTypeSettingsRootView

## Responsibility

`KnowTypeSettingsRootView` composes the shared SwiftUI settings surface used by
the standalone app, preference pane, and IMK preferences window.

## Boundaries

- View composition stays here; business rules belong in ViewModels and shared
  models.
- Host-specific AppKit wrappers should not fork settings behavior.

## Behavior Notes

- The root view should keep provider, input behavior, privacy, lexicon, and
  debug install areas available from all settings hosts.
- Keep user-facing copy concise and current-state focused.

## Tests

- ViewModel tests for each settings area
- Manual local settings launch when UI layout changes
