import KnowTypeCore
import KnowTypeProviders
import SwiftUI

private func settingsString(_ key: String) -> String {
    SettingsLocalization.string(key)
}

private func settingsFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: settingsString(key), arguments: arguments)
}

public struct ProviderProfilesView: View {
    @ObservedObject private var viewModel: ProviderProfilesViewModel
    @StateObject private var lexiconViewModel: LexiconSettingsViewModel
    @StateObject private var inputModeViewModel: InputModePreferencesViewModel
    @StateObject private var runtimePreferencesViewModel: RuntimePreferencesViewModel
    @State private var selectedSection: SettingsSection = .overview
    @State private var searchText = ""

    public init(
        viewModel: ProviderProfilesViewModel,
        lexiconViewModel: LexiconSettingsViewModel = LexiconSettingsViewModel(),
        inputModeViewModel: InputModePreferencesViewModel = InputModePreferencesViewModel(),
        runtimePreferencesViewModel: RuntimePreferencesViewModel = RuntimePreferencesViewModel()
    ) {
        self.viewModel = viewModel
        _lexiconViewModel = StateObject(wrappedValue: lexiconViewModel)
        _inputModeViewModel = StateObject(wrappedValue: inputModeViewModel)
        _runtimePreferencesViewModel = StateObject(wrappedValue: runtimePreferencesViewModel)
    }

    public var body: some View {
        NavigationSplitView {
            SettingsSidebarView(searchText: $searchText, selectedSection: $selectedSection)
        } detail: {
            settingsDetail(for: selectedSection)
        }
    }

    @ViewBuilder
    private func settingsDetail(for section: SettingsSection) -> some View {
        switch section {
        case .overview:
            SettingsOverviewView(
                viewModel: viewModel,
                lexiconViewModel: lexiconViewModel,
                runtimePreferencesViewModel: runtimePreferencesViewModel,
                selectedSection: $selectedSection
            )
        case .aiProvider:
            AIProviderSettingsView(
                viewModel: viewModel,
                runtimePreferencesViewModel: runtimePreferencesViewModel
            )
        case .input:
            InputSettingsView(
                inputModeViewModel: inputModeViewModel,
                runtimePreferencesViewModel: runtimePreferencesViewModel
            )
        case .candidates:
            CandidateSettingsView(viewModel: runtimePreferencesViewModel)
        case .lexicons:
            LexiconSettingsView(viewModel: lexiconViewModel)
        case .privacy:
            PrivacySettingsView(runtimePreferencesViewModel: runtimePreferencesViewModel)
        case .advanced:
            DiagnosticsSettingsView()
        }
    }
}

private struct SettingsSidebarView: View {
    @Binding var searchText: String
    @Binding var selectedSection: SettingsSection

    var body: some View {
        let presentation = SettingsSidebarPresentation(searchText: searchText)

        List(selection: $selectedSection) {
            ForEach(presentation.sections) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }

            if presentation.sections.isEmpty {
                Text(settingsString("settings.sidebar.noMatches"))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        .frame(minWidth: 220)
        .searchable(text: $searchText, prompt: SettingsLocalization.string("settings.search.prompt"))
    }
}

private struct SettingsOverviewView: View {
    @ObservedObject var viewModel: ProviderProfilesViewModel
    @ObservedObject var lexiconViewModel: LexiconSettingsViewModel
    @ObservedObject var runtimePreferencesViewModel: RuntimePreferencesViewModel
    @Binding var selectedSection: SettingsSection
    @State private var status = InstallationDiagnosticsStatus()

    var body: some View {
        let presentation = SettingsOverviewPresentation(
            profiles: viewModel.profiles,
            selectedProfileID: viewModel.selectedProfileID,
            runtimePreferences: runtimePreferencesViewModel.preferences,
            totalLoadedEntryCount: lexiconViewModel.totalLoadedEntryCount,
            diagnosticsStatus: status
        )

        SettingsForm(title: presentation.title, subtitle: presentation.subtitle) {
            Section(settingsString("settings.overview.section.status")) {
                ForEach(presentation.statusRows, id: \.label) { row in
                    LabeledContent(row.label, value: row.value)
                }
            }

            Section(settingsString("settings.overview.section.actions")) {
                Button {
                    status = InstallationDiagnosticsStatus()
                    selectedSection = .advanced
                } label: {
                    Label(presentation.checkInstallActionLabel, systemImage: "stethoscope")
                }
                Button {
                    selectedSection = .aiProvider
                } label: {
                    Label(presentation.configureAIActionLabel, systemImage: "sparkles")
                }
                Button {
                    selectedSection = .lexicons
                } label: {
                    Label(presentation.manageLexiconActionLabel, systemImage: "text.book.closed")
                }
                SettingsDirectoryLink(
                    title: presentation.openLogsActionLabel,
                    systemImage: "doc.text.magnifyingglass",
                    url: SettingsSupportURLs.logs
                )
            }
        }
    }
}

private struct InputSettingsView: View {
    @ObservedObject var inputModeViewModel: InputModePreferencesViewModel
    @ObservedObject var runtimePreferencesViewModel: RuntimePreferencesViewModel

    var body: some View {
        SettingsForm(title: SettingsSection.input.title) {
            Section(settingsString("settings.input.section.symbols")) {
                Picker(settingsString("settings.input.defaultPunctuation"), selection: defaultPunctuationBinding) {
                    Text(settingsString("settings.input.symbol.chinese")).tag(InputSymbolMode.chinese)
                    Text(settingsString("settings.input.symbol.english")).tag(InputSymbolMode.english)
                }
                Picker(settingsString("settings.input.defaultWidth"), selection: defaultWidthBinding) {
                    Text(settingsString("settings.input.width.half")).tag(InputSymbolWidth.halfWidth)
                    Text(settingsString("settings.input.width.full")).tag(InputSymbolWidth.fullWidth)
                }
                Picker(settingsString("settings.input.codeAppPunctuation"), selection: codeAppPunctuationBinding) {
                    Text(settingsString("settings.input.symbol.chinese")).tag(InputSymbolMode.chinese)
                    Text(settingsString("settings.input.symbol.english")).tag(InputSymbolMode.english)
                }
                Picker(settingsString("settings.input.codeAppWidth"), selection: codeAppWidthBinding) {
                    Text(settingsString("settings.input.width.half")).tag(InputSymbolWidth.halfWidth)
                    Text(settingsString("settings.input.width.full")).tag(InputSymbolWidth.fullWidth)
                }
                LabeledContent(settingsString("settings.input.punctuationShortcut"), value: "Option + .")
                LabeledContent(settingsString("settings.input.textModeShortcut"), value: "Option + /")
                Button {
                    inputModeViewModel.resetToDefaults()
                    runtimePreferencesViewModel.resetToDefaults()
                } label: {
                    Label(SettingsLocalization.string("settings.action.restoreDefaults"), systemImage: "arrow.counterclockwise")
                }
                if let message = inputModeViewModel.lastErrorMessage ?? runtimePreferencesViewModel.lastErrorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }

            Section(settingsString("settings.input.section.behavior")) {
                DisclosureGroup(settingsString("settings.input.disclosure.workflow")) {
                    LabeledContent(settingsString("settings.input.host"), value: settingsString("settings.input.host.value"))
                    LabeledContent(settingsString("settings.input.compositionMode"), value: settingsString("settings.input.compositionMode.value"))
                    LabeledContent(settingsString("settings.input.basicCommit"), value: settingsString("settings.input.basicCommit.value"))
                    LabeledContent(settingsString("settings.input.continuationCommit"), value: settingsString("settings.input.continuationCommit.value"))
                    Text(settingsString("settings.input.prefixLock.note"))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var defaultPunctuationBinding: Binding<InputSymbolMode> {
        Binding(
            get: { inputModeViewModel.preferences.defaultState.punctuationMode },
            set: { inputModeViewModel.setDefaultPunctuationMode($0) }
        )
    }

    private var defaultWidthBinding: Binding<InputSymbolWidth> {
        Binding(
            get: { inputModeViewModel.preferences.defaultState.symbolWidth },
            set: { inputModeViewModel.setDefaultSymbolWidth($0) }
        )
    }

    private var codeAppPunctuationBinding: Binding<InputSymbolMode> {
        Binding(
            get: { inputModeViewModel.preferences.codeAppState.punctuationMode },
            set: { inputModeViewModel.setCodeAppPunctuationMode($0) }
        )
    }

    private var codeAppWidthBinding: Binding<InputSymbolWidth> {
        Binding(
            get: { inputModeViewModel.preferences.codeAppState.symbolWidth },
            set: { inputModeViewModel.setCodeAppSymbolWidth($0) }
        )
    }

}

private struct CandidateSettingsView: View {
    @ObservedObject var viewModel: RuntimePreferencesViewModel

    var body: some View {
        SettingsForm(title: SettingsSection.candidates.title) {
            Section(settingsString("settings.candidates.section.display")) {
                Picker(settingsString("settings.candidates.pageSize"), selection: candidatePageSizeBinding) {
                    Text("6").tag(6)
                    Text("9").tag(9)
                }
                Picker(settingsString("settings.candidates.layout"), selection: candidateLayoutModeBinding) {
                    Text(settingsString("settings.candidates.layout.adaptive")).tag(CandidatePanelLayoutMode.adaptive)
                    Text(settingsString("settings.candidates.layout.vertical")).tag(CandidatePanelLayoutMode.verticalPreferred)
                }
                LabeledContent(settingsString("settings.candidates.adaptivePage"), value: settingsString("settings.candidates.adaptivePage.value"))
                LabeledContent(settingsString("settings.candidates.verticalPage"), value: settingsString("settings.candidates.verticalPage.value"))
                if let message = viewModel.lastErrorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }

            Section(settingsString("settings.candidates.section.behavior")) {
                DisclosureGroup(settingsString("settings.candidates.section.order")) {
                    LabeledContent(settingsString("settings.candidates.rimeCandidates"), value: settingsString("settings.candidates.rimeCandidates.value"))
                    LabeledContent(settingsString("settings.candidates.aiContinuation"), value: settingsString("settings.candidates.aiContinuation.value"))
                    LabeledContent(settingsString("settings.candidates.rawInput"), value: settingsString("settings.candidates.rawInput.value"))
                }
                DisclosureGroup(settingsString("settings.candidates.section.shortcuts")) {
                    LabeledContent("Space", value: settingsString("settings.candidates.shortcut.space.value"))
                    LabeledContent(settingsString("settings.candidates.shortcut.number.label"), value: settingsString("settings.candidates.shortcut.number.value"))
                    LabeledContent("Tab", value: settingsString("settings.candidates.shortcut.tab.value"))
                    LabeledContent("Option + 1...9", value: settingsString("settings.candidates.shortcut.optionNumber.value"))
                    LabeledContent("Option + R", value: settingsString("settings.candidates.shortcut.optionR.value"))
                }
            }
        }
    }

    private var candidatePageSizeBinding: Binding<Int> {
        Binding(
            get: { viewModel.preferences.candidatePageSize },
            set: { viewModel.setCandidatePageSize($0) }
        )
    }

    private var candidateLayoutModeBinding: Binding<CandidatePanelLayoutMode> {
        Binding(
            get: { viewModel.preferences.candidateLayoutMode },
            set: { viewModel.setCandidateLayoutMode($0) }
        )
    }
}

private struct LexiconSettingsView: View {
    @ObservedObject var viewModel: LexiconSettingsViewModel

    var body: some View {
        let presentation = LexiconSettingsPresentation(viewModel: viewModel)

        SettingsForm(title: SettingsSection.lexicons.title) {
            Section(settingsString("settings.lexicon.section.local")) {
                LabeledContent(presentation.loadedEntries.label, value: presentation.loadedEntries.value)
                if let lastRefreshDate = presentation.lastRefreshDate {
                    LabeledContent(presentation.lastRefreshLabel, value: lastRefreshDate.formatted(date: .abbreviated, time: .standard))
                }
                Button {
                    viewModel.refresh()
                } label: {
                    Label(presentation.refreshActionLabel, systemImage: "arrow.clockwise")
                }
                Button {
                    _ = viewModel.createSampleLexiconResource()
                } label: {
                    Label(presentation.createSampleActionLabel, systemImage: "doc.badge.plus")
                }
                Button {
                    Task {
                        await viewModel.installRecommendedLexiconPack()
                    }
                } label: {
                    Label(presentation.installRecommendedPackActionLabel, systemImage: "square.and.arrow.down")
                }
                .disabled(presentation.isInstallingRecommendedPack)
                if presentation.showsCreateMissingDirectoriesAction {
                    Button {
                        _ = viewModel.createMissingDirectories()
                    } label: {
                        Label(presentation.createMissingDirectoriesActionLabel, systemImage: "folder.badge.plus")
                    }
                }
                if let lastActionMessage = presentation.lastActionMessage {
                    Text(lastActionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(settingsString("settings.lexicon.section.advanced")) {
                DisclosureGroup(settingsString("settings.lexicon.disclosure.directories")) {
                    ForEach(presentation.directories) { directory in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(directory.sectionTitle)
                                .font(.headline)
                            LabeledContent(directory.status.label, value: directory.status.value)
                            LabeledContent(directory.resourceFiles.label, value: directory.resourceFiles.value)
                            LabeledContent(directory.loadedEntries.label, value: directory.loadedEntries.value)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(directory.pathLabel)
                                    .foregroundStyle(.secondary)
                                MonospacedText(directory.path)
                            }

                            ForEach(directory.installedPacks) { pack in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pack.title)
                                        .font(.headline)
                                    LabeledContent(pack.entries.label, value: pack.entries.value)
                                    LabeledContent(pack.license.label, value: pack.license.value)
                                    LabeledContent(pack.installedAt.label, value: pack.installedAt.value)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(pack.source.label)
                                            .foregroundStyle(.secondary)
                                        MonospacedText(pack.source.value)
                                    }
                                }
                                .padding(.top, 4)
                            }

                            if !directory.diagnostics.isEmpty {
                                ForEach(directory.diagnostics) { diagnostic in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(diagnostic.title)
                                            .font(.headline)
                                        Text(diagnostic.message)
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                DisclosureGroup(settingsString("settings.lexicon.section.format")) {
                    ForEach(presentation.formatRows, id: \.label) { row in
                        LabeledContent(row.label, value: row.value)
                    }
                }
            }
        }
    }
}

private struct AIProviderSettingsView: View {
    @ObservedObject var viewModel: ProviderProfilesViewModel
    @ObservedObject var runtimePreferencesViewModel: RuntimePreferencesViewModel

    var body: some View {
        let draftPresentation = ProviderProfileDraftPresentation(draft: viewModel.draft)
        let connectionPresentation = ProviderConnectionStatusPresentation(status: viewModel.connectionStatus)
        let validationPresentation = ProviderValidationPresentation(errors: viewModel.validationErrors)
        let lastErrorPresentation = ProviderLastErrorPresentation(message: viewModel.lastErrorMessage)

        SettingsForm(title: SettingsSection.aiProvider.title) {
            Section(settingsString("settings.provider.section.continuation")) {
                Toggle(settingsString("settings.provider.cloudContinuation"), isOn: cloudContinuationEnabledBinding)
                Toggle(settingsString("settings.provider.localContinuation"), isOn: localContinuationEnabledBinding)
                Picker(settingsString("settings.provider.length"), selection: continuationLengthLevelBinding) {
                    Text(settingsString("settings.provider.length.short")).tag(ContinuationLengthLevel.short)
                    Text(settingsString("settings.provider.length.medium")).tag(ContinuationLengthLevel.medium)
                    Text(settingsString("settings.provider.length.long")).tag(ContinuationLengthLevel.long)
                }
                Stepper(value: maxContinuationCandidatesBinding, in: 1...6, step: 1) {
                    Text(settingsFormat("settings.provider.maxCandidates", runtimePreferencesViewModel.preferences.maxContinuationCandidates))
                }
                if let message = runtimePreferencesViewModel.lastErrorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }

            Section(settingsString("settings.provider.section.service")) {
                if viewModel.profiles.isEmpty {
                    Text(settingsString("settings.provider.noProfiles.userFacing"))
                        .foregroundStyle(.secondary)
                } else {
                    Picker(settingsString("settings.provider.currentProfile"), selection: profileSelectionBinding) {
                        ForEach(viewModel.profiles) { profile in
                            let item = ProviderProfileListItemPresentation(profile: profile)

                            Text("\(item.title) · \(item.subtitle)")
                                .tag(Optional(item.id))
                        }
                    }
                }

                LabeledContent(settingsString("settings.provider.serviceSummary"), value: currentServiceSummary)

                Button {
                    Task {
                        await viewModel.testDraftConnection()
                    }
                } label: {
                    Label(connectionPresentation.testButtonLabel, systemImage: "network")
                }
                .disabled(viewModel.isPersistenceBlocked || connectionPresentation.isTesting)

                if connectionPresentation.showsProgress {
                    ProgressView()
                } else if let message = connectionPresentation.message {
                    connectionStatusMessage(message)
                }
            }

            Section(settingsString("settings.provider.section.advancedService")) {
                DisclosureGroup(settingsString("settings.provider.advancedServiceConfig")) {
                    Menu {
                        ForEach(ProviderKind.allCases, id: \.self) { kind in
                            Button(kind.rawValue) {
                                viewModel.createProfile(kind: kind)
                            }
                        }
                    } label: {
                        Label(settingsString("settings.provider.add"), systemImage: "plus")
                    }

                    TextField(draftPresentation.displayNameFieldLabel, text: $viewModel.draft.displayName)
                    Picker(
                        draftPresentation.kindPickerLabel,
                        selection: Binding(
                            get: { viewModel.draft.kind },
                            set: { viewModel.changeDraftKind($0) }
                        )
                    ) {
                        ForEach(ProviderKind.allCases, id: \.self) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    TextField(draftPresentation.baseURLFieldLabel, text: $viewModel.draft.baseURL)
                    TextField(draftPresentation.modelFieldLabel, text: $viewModel.draft.model)
                    Stepper(value: $viewModel.draft.timeoutSeconds, in: 1...120, step: 1) {
                        Text(draftPresentation.timeoutLabel)
                    }
                    Toggle(draftPresentation.defaultProviderLabel, isOn: $viewModel.draft.isDefault)

                    Divider()

                    Text(draftPresentation.secret.sectionTitle)
                        .font(.headline)
                    SecureField(draftPresentation.secret.apiKeyFieldPrompt, text: $viewModel.draft.apiKey)
                    if let reference = draftPresentation.secret.reference {
                        LabeledContent(reference.label, value: reference.value)
                            .font(.caption)
                    }
                    Text(draftPresentation.secret.helpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if draftPresentation.showsCustomHTTPFields {
                        Divider()
                        Text(settingsString("settings.provider.advancedCustomHTTP"))
                            .font(.headline)
                        TextEditor(text: $viewModel.draft.customBodyTemplate)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 120)
                        TextField(draftPresentation.customResponsePathLabel, text: $viewModel.draft.customResponsePath)
                    }

                    Button {
                        _ = viewModel.saveDraft()
                    } label: {
                        Label(SettingsLocalization.string("settings.action.save"), systemImage: "square.and.arrow.down")
                    }
                    .disabled(viewModel.isPersistenceBlocked)
                    .keyboardShortcut("s", modifiers: [.command])
                }
            }

            if validationPresentation.isVisible {
                Section(validationPresentation.title) {
                    ForEach(validationPresentation.messages, id: \.self) { error in
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }

            if let lastErrorMessage = lastErrorPresentation.message {
                Section(lastErrorPresentation.title) {
                    Text(lastErrorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var currentServiceSummary: String {
        if let selectedProfileID = viewModel.selectedProfileID,
           let profile = viewModel.profiles.first(where: { $0.id == selectedProfileID }) {
            return serviceSummary(for: profile)
        }
        if let profile = viewModel.profiles.first(where: \.isDefault) ?? viewModel.profiles.first {
            return serviceSummary(for: profile)
        }
        return settingsString("settings.provider.serviceSummary.empty")
    }

    private func serviceSummary(for profile: ProviderProfile) -> String {
        let model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            return profile.displayName
        }
        return "\(profile.displayName) · \(model)"
    }

    private var profileSelectionBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedProfileID },
            set: { id in
                if let id {
                    viewModel.selectProfile(id: id)
                }
            }
        )
    }

    private var cloudContinuationEnabledBinding: Binding<Bool> {
        Binding(
            get: { runtimePreferencesViewModel.preferences.cloudContinuationEnabled },
            set: { runtimePreferencesViewModel.setCloudContinuationEnabled($0) }
        )
    }

    private var localContinuationEnabledBinding: Binding<Bool> {
        Binding(
            get: { runtimePreferencesViewModel.preferences.localContinuationEnabledWhenNoProvider },
            set: { runtimePreferencesViewModel.setLocalContinuationEnabledWhenNoProvider($0) }
        )
    }

    private var continuationLengthLevelBinding: Binding<ContinuationLengthLevel> {
        Binding(
            get: { runtimePreferencesViewModel.preferences.continuationLengthLevel },
            set: { runtimePreferencesViewModel.setContinuationLengthLevel($0) }
        )
    }

    private var maxContinuationCandidatesBinding: Binding<Int> {
        Binding(
            get: { runtimePreferencesViewModel.preferences.maxContinuationCandidates },
            set: { runtimePreferencesViewModel.setMaxContinuationCandidates($0) }
        )
    }

    @ViewBuilder
    private func connectionStatusMessage(_ message: ProviderStatusMessagePresentation) -> some View {
        switch message.tone {
        case .secondary:
            Text(message.text)
                .foregroundStyle(.secondary)
        case .error:
            Text(message.text)
                .foregroundStyle(.red)
        }
    }
}

private struct PrivacySettingsView: View {
    @ObservedObject var runtimePreferencesViewModel: RuntimePreferencesViewModel

    var body: some View {
        SettingsForm(title: SettingsSection.privacy.title) {
            Section(settingsString("settings.privacy.section.cloud")) {
                LabeledContent(
                    settingsString("settings.privacy.providerCalls"),
                    value: runtimePreferencesViewModel.preferences.cloudContinuationEnabled
                        ? settingsString("settings.privacy.providerCalls.enabled")
                        : settingsString("settings.privacy.providerCalls.disabled")
                )
                LabeledContent(
                    settingsString("settings.privacy.localFallback"),
                    value: runtimePreferencesViewModel.preferences.localContinuationEnabledWhenNoProvider
                        ? settingsString("settings.privacy.localFallback.enabled")
                        : settingsString("settings.privacy.localFallback.disabled")
                )
            }

            Section(settingsString("settings.privacy.section.level0")) {
                LabeledContent(settingsString("settings.privacy.urlEmail"), value: settingsString("settings.privacy.localOnly"))
                LabeledContent(settingsString("settings.privacy.pathCommand"), value: settingsString("settings.privacy.localOnly"))
                LabeledContent(settingsString("settings.privacy.codeInput"), value: settingsString("settings.privacy.localOnly"))
                LabeledContent("Terminal, iTerm, Xcode", value: settingsString("settings.privacy.localOnly"))
            }

            Section(settingsString("settings.privacy.section.technicalTokens")) {
                Text(settingsString("settings.privacy.technicalTokens.note"))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DiagnosticsSettingsView: View {
    @State private var status = InstallationDiagnosticsStatus()

    var body: some View {
        SettingsForm(title: SettingsSection.advanced.title, subtitle: settingsString("settings.advanced.subtitle")) {
            Section(settingsString("settings.advanced.section.shortcuts")) {
                SettingsDirectoryLink(
                    title: settingsString("settings.advanced.openLogs"),
                    systemImage: "doc.text.magnifyingglass",
                    url: SettingsSupportURLs.logs
                )
                SettingsDirectoryLink(
                    title: settingsString("settings.advanced.openSupportFolder"),
                    systemImage: "folder",
                    url: SettingsSupportURLs.support
                )
                SettingsDirectoryLink(
                    title: settingsString("settings.advanced.openRimeUserFolder"),
                    systemImage: "keyboard",
                    url: SettingsSupportURLs.rimeUser
                )
            }

            Section(settingsString("settings.diagnostics.section.install")) {
                ForEach(status.installRows, id: \.label) { row in
                    LabeledContent(row.label, value: row.value)
                }
                Button {
                    status = InstallationDiagnosticsStatus()
                } label: {
                    Label(settingsString("settings.diagnostics.refresh"), systemImage: "arrow.clockwise")
                }
            }

            Section(settingsString("settings.diagnostics.section.runtime")) {
                ForEach(status.runtimeRows, id: \.label) { row in
                    LabeledContent(row.label, value: row.value)
                }
            }

            Section(settingsString("settings.diagnostics.section.ai")) {
                ForEach(status.aiRows, id: \.label) { row in
                    LabeledContent(row.label, value: row.value)
                }
            }

            Section(settingsString("settings.diagnostics.section.userData")) {
                ForEach(status.userDataRows, id: \.label) { row in
                    LabeledContent(row.label, value: row.value)
                }
            }

            Section(settingsString("settings.diagnostics.section.acceptedLearning")) {
                ForEach(status.acceptedLearningRows, id: \.label) { row in
                    LabeledContent(row.label, value: row.value)
                }
                DisclosureGroup(settingsString("settings.diagnostics.acceptedLearning.commands")) {
                    ForEach(status.acceptedLearningCommands, id: \.self) { command in
                        MonospacedText(command)
                    }
                }
            }

            Section(settingsString("settings.diagnostics.section.acceptedFeedback")) {
                ForEach(status.acceptedFeedbackRows, id: \.label) { row in
                    LabeledContent(row.label, value: row.value)
                }
            }

            Section(settingsString("settings.diagnostics.section.backup")) {
                ForEach(status.backupRows, id: \.label) { row in
                    LabeledContent(row.label, value: row.value)
                }
                if let rollbackCommand = status.rollbackCommand {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(settingsString("settings.diagnostics.backup.rollbackCommand"))
                            .foregroundStyle(.secondary)
                        MonospacedText(rollbackCommand)
                    }
                }
            }

            Section(settingsString("settings.diagnostics.section.local")) {
                ForEach(DebugInstallGuidance.steps) { step in
                    InstallStepView(title: step.title, detail: step.detail)
                }
            }

            Section {
                DisclosureGroup(settingsString("settings.diagnostics.commands")) {
                    ForEach(DebugInstallGuidance.commands, id: \.self) { command in
                        MonospacedText(command)
                    }
                }
            }
        }
    }
}

private enum SettingsSupportURLs {
    static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/KnowType", isDirectory: true)
    }

    static var logs: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/KnowType", isDirectory: true)
    }

    static var rimeUser: URL {
        support.appendingPathComponent("Rime", isDirectory: true)
    }
}

private struct SettingsDirectoryLink: View {
    let title: String
    let systemImage: String
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(url)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct SettingsForm<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                if let subtitle {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Form {
                content
            }
            .formStyle(.grouped)
        }
        .padding(.bottom, 12)
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct InstallStepView: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct MonospacedText: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
    }
}
