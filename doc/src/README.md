# Source Notes

This directory contains short notes for important source files and subsystems. These files are not a replacement for source code; they record intent, ownership boundaries, and testing concerns that are easy to lose during branch work.

The directory layout mirrors the repository layout. Put notes for Swift package targets under `Sources/<target>/`, and notes for local shell tooling under `scripts/`.

## Sources/KnowTypeCore

- [Overview](Sources/KnowTypeCore/README.plan.md)
- [ManagedLexiconPack](Sources/KnowTypeCore/ManagedLexiconPack.plan.md)
- [InputMethodRuntimePreferences](Sources/KnowTypeCore/InputMethodRuntimePreferences.plan.md)
- [TraditionalInputEngine](Sources/KnowTypeCore/TraditionalInputEngine.plan.md)
- [TraditionalInputLexiconCatalog](Sources/KnowTypeCore/TraditionalInputLexiconCatalog.plan.md)
- [TraditionalInputLexiconDirectoryResolver](Sources/KnowTypeCore/TraditionalInputLexiconDirectoryResolver.plan.md)
- [TraditionalInputLexiconFileSource](Sources/KnowTypeCore/TraditionalInputLexiconFileSource.plan.md)
- [TraditionalInputLexiconResourceLoader](Sources/KnowTypeCore/TraditionalInputLexiconResourceLoader.plan.md)
- [TraditionalInputSeedLexicon](Sources/KnowTypeCore/TraditionalInputSeedLexicon.plan.md)
- [PinyinTables](Sources/KnowTypeCore/PinyinTables.plan.md)

## Sources/KnowTypeProviders

- [Overview](Sources/KnowTypeProviders/README.plan.md)
- [Local OpenAI-Compatible Provider Runtime](Sources/KnowTypeProviders/provider-runtime-local.plan.md)

## Sources/KnowTypeInputMethod

- [Overview](Sources/KnowTypeInputMethod/README.plan.md)
- [CandidateAnchorResolver](Sources/KnowTypeInputMethod/CandidateAnchorResolver.plan.md)
- [CandidatePanelRenderer](Sources/KnowTypeInputMethod/CandidatePanelRenderer.plan.md)
- [CandidatePanelWindowController](Sources/KnowTypeInputMethod/CandidatePanelWindowController.plan.md)
- [CompositionBuffer](Sources/KnowTypeInputMethod/CompositionBuffer.plan.md)
- [InputControllerCoordinator](Sources/KnowTypeInputMethod/InputControllerCoordinator.plan.md)
- [InputMethodLexiconRuntime](Sources/KnowTypeInputMethod/InputMethodLexiconRuntime.plan.md)
- [InputSessionController](Sources/KnowTypeInputMethod/InputSessionController.plan.md)
- [InputSymbolMode](Sources/KnowTypeInputMethod/InputSymbolMode.plan.md)
- [UserSelectionHistoryStore](Sources/KnowTypeInputMethod/UserSelectionHistoryStore.plan.md)

## Sources/KnowTypeInputMethodApp

- [Overview](Sources/KnowTypeInputMethodApp/README.plan.md)

## Sources/KnowTypeSettingsApp

`KnowTypeSettingsApp` is the standalone launcher for the shared settings UI.

## Sources/KnowTypeSettingsUI

- [Overview](Sources/KnowTypeSettingsUI/README.plan.md)
- [LexiconSettingsPresentation](Sources/KnowTypeSettingsUI/LexiconSettingsPresentation.plan.md)
- [LexiconSettingsViewModel](Sources/KnowTypeSettingsUI/LexiconSettingsViewModel.plan.md)
- [ProviderProfilesPresentation](Sources/KnowTypeSettingsUI/ProviderProfilesPresentation.plan.md)
- [ProviderProfilesViewModel](Sources/KnowTypeSettingsUI/ProviderProfilesViewModel.plan.md)
- [Settings Install Debug](Sources/KnowTypeSettingsUI/settings-install-debug.plan.md)

## Sources/KnowTypePreferencePane

- [Overview](Sources/KnowTypePreferencePane/README.plan.md)

## Sources/KnowTypeDemo

- [Overview](Sources/KnowTypeDemo/README.plan.md)

## scripts

- [Managed Lexicon Pack Installer](scripts/install-lexicon-pack.plan.md)
- [PreferencePane Builder](scripts/build-preference-pane.plan.md)
- [Local System Policy Profile Generator](scripts/create-local-system-policy-profile.plan.md)
- [Input Method Diagnostic Scripts](scripts/inputmethod-diagnostics.plan.md)
