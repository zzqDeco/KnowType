# Source Notes

This directory contains short notes for important source files and subsystems.
The notes record ownership boundaries, invariants, and testing concerns that are
easy to lose during branch work. They are not a replacement for the source code.

The directory layout mirrors the repository layout. Put notes for Swift package
targets under `Sources/<target>/`, and notes for local shell tooling under
`scripts/`. Use [the source note template](../templates/source-note.template.md)
when adding a new note.

Source notes are required for public contracts, cross-module boundaries,
InputMethodKit or AppKit seams, provider adapters, persistence formats, scripts,
and files with non-obvious privacy or prefix-lock behavior. They are not
required for every test file.

## Sources/KnowTypeCore

- [Overview](Sources/KnowTypeCore/README.plan.md)
- [CorrectionEngine](Sources/KnowTypeCore/CorrectionEngine.plan.md)
- [InputMethodRuntimePreferences](Sources/KnowTypeCore/InputMethodRuntimePreferences.plan.md)
- [InputModePreferences](Sources/KnowTypeCore/InputModePreferences.plan.md)
- [ManagedLexiconPack](Sources/KnowTypeCore/ManagedLexiconPack.plan.md)
- [Models](Sources/KnowTypeCore/Models.plan.md)
- [PinyinTables](Sources/KnowTypeCore/PinyinTables.plan.md)
- [PrefixContinuationEngine](Sources/KnowTypeCore/PrefixContinuationEngine.plan.md)
- [TextProtection](Sources/KnowTypeCore/TextProtection.plan.md)
- [TraditionalInputEngine](Sources/KnowTypeCore/TraditionalInputEngine.plan.md)
- [TraditionalInputLexiconCatalog](Sources/KnowTypeCore/TraditionalInputLexiconCatalog.plan.md)
- [TraditionalInputLexiconDirectoryResolver](Sources/KnowTypeCore/TraditionalInputLexiconDirectoryResolver.plan.md)
- [TraditionalInputLexiconFileSource](Sources/KnowTypeCore/TraditionalInputLexiconFileSource.plan.md)
- [TraditionalInputLexiconResourceLoader](Sources/KnowTypeCore/TraditionalInputLexiconResourceLoader.plan.md)
- [TraditionalInputSeedLexicon](Sources/KnowTypeCore/TraditionalInputSeedLexicon.plan.md)

## Sources/KnowTypeProviders

- [Overview](Sources/KnowTypeProviders/README.plan.md)
- [AnthropicMessagesProvider](Sources/KnowTypeProviders/AnthropicMessagesProvider.plan.md)
- [CustomHTTPProvider](Sources/KnowTypeProviders/CustomHTTPProvider.plan.md)
- [GeminiNativeProvider](Sources/KnowTypeProviders/GeminiNativeProvider.plan.md)
- [HTTPClient](Sources/KnowTypeProviders/HTTPClient.plan.md)
- [KeychainSecretStore](Sources/KnowTypeProviders/KeychainSecretStore.plan.md)
- [LLMOutputContract](Sources/KnowTypeProviders/LLMOutputContract.plan.md)
- [Local OpenAI-Compatible Provider Runtime](Sources/KnowTypeProviders/provider-runtime-local.plan.md)
- [OllamaNativeProvider](Sources/KnowTypeProviders/OllamaNativeProvider.plan.md)
- [OpenAIChatProvider](Sources/KnowTypeProviders/OpenAIChatProvider.plan.md)
- [OpenAIResponsesProvider](Sources/KnowTypeProviders/OpenAIResponsesProvider.plan.md)
- [PromptBuilder](Sources/KnowTypeProviders/PromptBuilder.plan.md)
- [ProviderConfiguration](Sources/KnowTypeProviders/ProviderConfiguration.plan.md)
- [ProviderConnectionDiagnostic](Sources/KnowTypeProviders/ProviderConnectionDiagnostic.plan.md)
- [ProviderModelDiscovery](Sources/KnowTypeProviders/ProviderModelDiscovery.plan.md)
- [ProviderProfile](Sources/KnowTypeProviders/ProviderProfile.plan.md)
- [ProviderProfileTemplates](Sources/KnowTypeProviders/ProviderProfileTemplates.plan.md)
- [ProviderRuntimeLoader](Sources/KnowTypeProviders/ProviderRuntimeLoader.plan.md)
- [ResponseNormalizer](Sources/KnowTypeProviders/ResponseNormalizer.plan.md)
- [StructuredResponseNormalizer](Sources/KnowTypeProviders/StructuredResponseNormalizer.plan.md)

## Sources/KnowTypeAI

- [Overview](Sources/KnowTypeAI/README.plan.md)
- [AIAcceptedLearning](Sources/KnowTypeAI/AIAcceptedLearning.plan.md)
- [AIDocumentStores](Sources/KnowTypeAI/AIDocumentStores.plan.md)
- [RimeUserDBLexicalProfile](Sources/KnowTypeAI/RimeUserDBLexicalProfile.plan.md)

## Sources/KnowTypeInputMethod

- [Overview](Sources/KnowTypeInputMethod/README.plan.md)
- [CandidateAnchorPolicy](Sources/KnowTypeInputMethod/CandidateAnchorPolicy.plan.md)
- [CandidateAnchorResolver](Sources/KnowTypeInputMethod/CandidateAnchorResolver.plan.md)
- [CandidatePanelAppearance](Sources/KnowTypeInputMethod/CandidatePanelAppearance.plan.md)
- [CandidatePanelLayoutEngine](Sources/KnowTypeInputMethod/CandidatePanelLayoutEngine.plan.md)
- [CandidatePanelRenderer](Sources/KnowTypeInputMethod/CandidatePanelRenderer.plan.md)
- [CandidatePanelRowBuilder](Sources/KnowTypeInputMethod/CandidatePanelRowBuilder.plan.md)
- [CandidatePanelState](Sources/KnowTypeInputMethod/CandidatePanelState.plan.md)
- [CandidatePanelWindowController](Sources/KnowTypeInputMethod/CandidatePanelWindowController.plan.md)
- [CompositionBuffer](Sources/KnowTypeInputMethod/CompositionBuffer.plan.md)
- [InputAIAcceptanceRuntime](Sources/KnowTypeInputMethod/InputAIAcceptanceRuntime.plan.md)
- [InputAIRecommendationRuntime](Sources/KnowTypeInputMethod/InputAIRecommendationRuntime.plan.md)
- [InputAIRecommendationSchedulePolicy](Sources/KnowTypeInputMethod/InputAIRecommendationSchedulePolicy.plan.md)
- [InputActions](Sources/KnowTypeInputMethod/InputActions.plan.md)
- [InputCandidatePanelPublicationRuntime](Sources/KnowTypeInputMethod/InputCandidatePanelPublicationRuntime.plan.md)
- [InputCandidateListBuilder](Sources/KnowTypeInputMethod/InputCandidateListBuilder.plan.md)
- [InputCommitResultPolicy](Sources/KnowTypeInputMethod/InputCommitResultPolicy.plan.md)
- [InputClientCompatibilityPolicy](Sources/KnowTypeInputMethod/InputClientCompatibilityPolicy.plan.md)
- [InputClientCompositionWriter](Sources/KnowTypeInputMethod/InputClientCompositionWriter.plan.md)
- [InputClientWriteCoordinator](Sources/KnowTypeInputMethod/InputClientWriteCoordinator.plan.md)
- [HostCompatibilityProfile](Sources/KnowTypeInputMethod/HostCompatibilityProfile.plan.md)
- [InputNativeCandidateNavigationRuntime](Sources/KnowTypeInputMethod/InputNativeCandidateNavigationRuntime.plan.md)
- [InputController](Sources/KnowTypeInputMethod/InputController.plan.md)
- [InputControllerCoordinator](Sources/KnowTypeInputMethod/InputControllerCoordinator.plan.md)
- [InputControllerHostClientSeams](Sources/KnowTypeInputMethod/InputControllerHostClientSeams.plan.md)
- [InputSelectionHistoryRuntime](Sources/KnowTypeInputMethod/InputSelectionHistoryRuntime.plan.md)
- [InputRuntimeBoundaries](Sources/KnowTypeInputMethod/InputRuntimeBoundaries.plan.md)
- [InputKeyCommandMapper](Sources/KnowTypeInputMethod/InputKeyCommandMapper.plan.md)
- [InputMethodMenuBuilder](Sources/KnowTypeInputMethod/InputMethodMenuBuilder.plan.md)
- [InputMethodHost](Sources/KnowTypeInputMethod/InputMethodHost.plan.md)
- [InputMethodLexiconRuntime](Sources/KnowTypeInputMethod/InputMethodLexiconRuntime.plan.md)
- [InputSessionController](Sources/KnowTypeInputMethod/InputSessionController.plan.md)
- [InputSymbolMode](Sources/KnowTypeInputMethod/InputSymbolMode.plan.md)
- [KnowTypePreferencesWindowController](Sources/KnowTypeInputMethod/KnowTypePreferencesWindowController.plan.md)
- [LexicalProfileRuntime](Sources/KnowTypeInputMethod/LexicalProfileRuntime.plan.md)
- [RimeConversionEngine](Sources/KnowTypeInputMethod/RimeConversionEngine.plan.md)
- [RimeMaintenanceService](Sources/KnowTypeInputMethod/RimeMaintenanceService.plan.md)
- [SessionSuggestionPipeline](Sources/KnowTypeInputMethod/SessionSuggestionPipeline.plan.md)
- [SuggestionPublicationGuard](Sources/KnowTypeInputMethod/SuggestionPublicationGuard.plan.md)
- [SuggestionRefreshPolicy](Sources/KnowTypeInputMethod/SuggestionRefreshPolicy.plan.md)
- [UserSelectionHistoryStore](Sources/KnowTypeInputMethod/UserSelectionHistoryStore.plan.md)

## App And Tool Targets

- [KnowTypeDemo](Sources/KnowTypeDemo/README.plan.md)
- [KnowTypeInputMethodApp](Sources/KnowTypeInputMethodApp/README.plan.md)
- [KnowTypeInputSourceSupport](Sources/KnowTypeInputSourceSupport/README.plan.md)
- [KnowTypeInputSourceTool](Sources/KnowTypeInputSourceTool/README.plan.md)
- [KnowTypeLexiconTool](Sources/KnowTypeLexiconTool/README.plan.md)
- [KnowTypePreferencePane](Sources/KnowTypePreferencePane/README.plan.md)
- [KnowTypePreferencePane Entry](Sources/KnowTypePreferencePane/KnowTypePreferencePane.plan.md)
- [KnowTypeSettingsApp](Sources/KnowTypeSettingsApp/KnowTypeSettingsApp.plan.md)

## Sources/KnowTypeSettingsUI

- [Overview](Sources/KnowTypeSettingsUI/README.plan.md)
- [DebugInstallGuidance](Sources/KnowTypeSettingsUI/DebugInstallGuidance.plan.md)
- [InputModePreferencesViewModel](Sources/KnowTypeSettingsUI/InputModePreferencesViewModel.plan.md)
- [KnowTypeSettingsRootView](Sources/KnowTypeSettingsUI/KnowTypeSettingsRootView.plan.md)
- [LexiconSettingsPresentation](Sources/KnowTypeSettingsUI/LexiconSettingsPresentation.plan.md)
- [LexiconSettingsViewModel](Sources/KnowTypeSettingsUI/LexiconSettingsViewModel.plan.md)
- [ProviderProfilesPresentation](Sources/KnowTypeSettingsUI/ProviderProfilesPresentation.plan.md)
- [ProviderProfilesView](Sources/KnowTypeSettingsUI/ProviderProfilesView.plan.md)
- [ProviderProfilesViewModel](Sources/KnowTypeSettingsUI/ProviderProfilesViewModel.plan.md)
- [RuntimePreferencesViewModel](Sources/KnowTypeSettingsUI/RuntimePreferencesViewModel.plan.md)
- [Settings Install Debug](Sources/KnowTypeSettingsUI/settings-install-debug.plan.md)

## scripts

- [Acceptance Harness](scripts/accept-inputmethod-local.plan.md)
- [Input Method Bundle Builder](scripts/build-inputmethod-bundle.plan.md)
- [PreferencePane Builder](scripts/build-preference-pane.plan.md)
- [Local System Policy Profile Generator](scripts/create-local-system-policy-profile.plan.md)
- [Input Method Diagnostic Scripts](scripts/inputmethod-diagnostics.plan.md)
- [Input Method Installer](scripts/install-inputmethod.plan.md)
- [Managed Lexicon Pack Installer](scripts/install-lexicon-pack.plan.md)
- [Developer Preview DMG Packager](scripts/package-dmg.plan.md)
- [Release Packager](scripts/package-release.plan.md)
- [Rime Artifact Preparer](scripts/prepare-rime-artifacts.plan.md)
- [Input Method Installation Helpers](scripts/lib/inputmethod-installation.plan.md)
- [Input Source Tool Shell Helpers And IDs](scripts/lib/inputsource-tool.plan.md)
- [Input Method Selection Repair](scripts/repair-inputmethod-selection.plan.md)
- [Input Method Rollback](scripts/rollback-inputmethod.plan.md)
- [Input Method Selector](scripts/select-inputmethod.plan.md)
- [Input Method Script Smoke](scripts/smoke-inputmethod-install.plan.md)
- [Input Method Uninstaller](scripts/uninstall-inputmethod.plan.md)
