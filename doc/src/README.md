# Source Notes

This directory contains short notes for important source files and subsystems. These files are not a replacement for source code; they record intent, ownership boundaries, and testing concerns that are easy to lose during branch work.

The directory layout mirrors the repository layout. Put notes for Swift package targets under `Sources/<target>/`, and notes for local shell tooling under `scripts/`.

## Sources/KnowTypeCore

- [Overview](Sources/KnowTypeCore/README.plan.md)
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
- [InputMethodLexiconRuntime](Sources/KnowTypeInputMethod/InputMethodLexiconRuntime.plan.md)
- [InputSessionController](Sources/KnowTypeInputMethod/InputSessionController.plan.md)
- [InputSymbolMode](Sources/KnowTypeInputMethod/InputSymbolMode.plan.md)
- [UserSelectionHistoryStore](Sources/KnowTypeInputMethod/UserSelectionHistoryStore.plan.md)

## Sources/KnowTypeInputMethodApp

- [Overview](Sources/KnowTypeInputMethodApp/README.plan.md)

## Sources/KnowTypeSettingsApp

- [LexiconSettingsViewModel](Sources/KnowTypeSettingsApp/LexiconSettingsViewModel.plan.md)
- [ProviderProfilesViewModel](Sources/KnowTypeSettingsApp/ProviderProfilesViewModel.plan.md)
- [Settings Install Debug](Sources/KnowTypeSettingsApp/settings-install-debug.plan.md)

## Sources/KnowTypeDemo

- [Overview](Sources/KnowTypeDemo/README.plan.md)

## scripts

- [Local System Policy Profile Generator](scripts/create-local-system-policy-profile.plan.md)
- [Input Method Diagnostic Scripts](scripts/inputmethod-diagnostics.plan.md)
