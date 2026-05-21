import KnowTypeCore
import KnowTypeProviders
import SwiftUI

public struct ProviderProfilesView: View {
    @ObservedObject private var viewModel: ProviderProfilesViewModel
    @StateObject private var lexiconViewModel: LexiconSettingsViewModel
    @StateObject private var inputModeViewModel: InputModePreferencesViewModel
    @StateObject private var runtimePreferencesViewModel: RuntimePreferencesViewModel
    @State private var selectedSection: SettingsSection = .input
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
                .navigationTitle(selectedSection.title)
        }
    }

    @ViewBuilder
    private func settingsDetail(for section: SettingsSection) -> some View {
        switch section {
        case .input:
            InputSettingsView(
                inputModeViewModel: inputModeViewModel,
                runtimePreferencesViewModel: runtimePreferencesViewModel
            )
        case .candidates:
            CandidateSettingsView(viewModel: runtimePreferencesViewModel)
        case .lexicons:
            LexiconSettingsView(viewModel: lexiconViewModel)
        case .aiProvider:
            AIProviderSettingsView(
                viewModel: viewModel,
                runtimePreferencesViewModel: runtimePreferencesViewModel
            )
        case .privacy:
            PrivacySettingsView(runtimePreferencesViewModel: runtimePreferencesViewModel)
        case .diagnostics:
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
                Text("没有匹配的设置")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        .frame(minWidth: 220)
        .searchable(text: $searchText, prompt: SettingsLocalization.string("settings.search.prompt"))
    }
}

private struct InputSettingsView: View {
    @ObservedObject var inputModeViewModel: InputModePreferencesViewModel
    @ObservedObject var runtimePreferencesViewModel: RuntimePreferencesViewModel

    var body: some View {
        SettingsForm(title: SettingsSection.input.title) {
            Section("组合输入") {
                LabeledContent("输入宿主", value: "InputMethodKit")
                LabeledContent("组合模式", value: "提交前使用 marked text")
                LabeledContent("基础提交", value: "Space 提交 Rime 候选")
                LabeledContent("续写提交", value: "Tab 提交前缀与续写")
            }

            Section("标点与宽度") {
                Picker("默认标点", selection: defaultPunctuationBinding) {
                    Text("中文").tag(InputSymbolMode.chinese)
                    Text("英文").tag(InputSymbolMode.english)
                }
                Picker("默认宽度", selection: defaultWidthBinding) {
                    Text("半角").tag(InputSymbolWidth.halfWidth)
                    Text("全角").tag(InputSymbolWidth.fullWidth)
                }
                Picker("代码 app 标点", selection: codeAppPunctuationBinding) {
                    Text("中文").tag(InputSymbolMode.chinese)
                    Text("英文").tag(InputSymbolMode.english)
                }
                Picker("代码 app 宽度", selection: codeAppWidthBinding) {
                    Text("半角").tag(InputSymbolWidth.halfWidth)
                    Text("全角").tag(InputSymbolWidth.fullWidth)
                }
                LabeledContent("切换快捷键", value: "Option + .")
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

            Section("前缀锁定") {
                Text("续写候选只会追加在已锁定前缀之后。改写前缀只允许通过显式润色操作触发。")
                    .foregroundStyle(.secondary)
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
            Section("显示") {
                Picker("每页候选数", selection: candidatePageSizeBinding) {
                    Text("6").tag(6)
                    Text("9").tag(9)
                }
                Picker("候选窗布局", selection: candidateLayoutModeBinding) {
                    Text("自适应横排").tag(CandidatePanelLayoutMode.adaptive)
                    Text("竖排列表").tag(CandidatePanelLayoutMode.verticalPreferred)
                }
                LabeledContent("自适应页", value: "最多 6 个候选")
                LabeledContent("竖排页", value: "使用上方每页候选数")
                if let message = viewModel.lastErrorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }

            Section("候选顺序") {
                LabeledContent("Rime 候选", value: "优先显示")
                LabeledContent("AI 续写", value: "只在显式快捷键或点击时提交")
                LabeledContent("原始输入", value: "仅在没有中文候选时保留")
            }

            Section("快捷键") {
                LabeledContent("Space", value: "提交当前 Rime 候选")
                LabeledContent("数字键", value: "选择当前页 Rime 候选")
                LabeledContent("Tab", value: "提交第一条 AI 续写")
                LabeledContent("Option + 数字", value: "提交对应 AI 续写")
                LabeledContent("Option + R", value: "显式润色")
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
            Section("本地词库") {
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

            ForEach(presentation.directories) { directory in
                Section(directory.sectionTitle) {
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
            }

            Section("格式") {
                ForEach(presentation.formatRows, id: \.label) { row in
                    LabeledContent(row.label, value: row.value)
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
            Section("续写") {
                Toggle("启用云端续写", isOn: cloudContinuationEnabledBinding)
                Toggle("没有 provider 时显示本地续写", isOn: localContinuationEnabledBinding)
                Picker("长度", selection: continuationLengthLevelBinding) {
                    Text("短").tag(ContinuationLengthLevel.short)
                    Text("中").tag(ContinuationLengthLevel.medium)
                    Text("长").tag(ContinuationLengthLevel.long)
                }
                Stepper(value: maxContinuationCandidatesBinding, in: 1...6, step: 1) {
                    Text("最多续写候选：\(runtimePreferencesViewModel.preferences.maxContinuationCandidates)")
                }
                if let message = runtimePreferencesViewModel.lastErrorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }

            Section("Provider") {
                if viewModel.profiles.isEmpty {
                    Text("尚未配置 provider。")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("当前配置", selection: profileSelectionBinding) {
                        ForEach(viewModel.profiles) { profile in
                            let item = ProviderProfileListItemPresentation(profile: profile)

                            Text("\(item.title) · \(item.subtitle)")
                                .tag(Optional(item.id))
                        }
                    }
                }

                Menu {
                    ForEach(ProviderKind.allCases, id: \.self) { kind in
                        Button(kind.rawValue) {
                            viewModel.createProfile(kind: kind)
                        }
                    }
                } label: {
                    Label("添加 Provider", systemImage: "plus")
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
            }

            Section(draftPresentation.secret.sectionTitle) {
                SecureField(draftPresentation.secret.apiKeyFieldPrompt, text: $viewModel.draft.apiKey)
                if let reference = draftPresentation.secret.reference {
                    LabeledContent(reference.label, value: reference.value)
                        .font(.caption)
                }
                Text(draftPresentation.secret.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if draftPresentation.showsCustomHTTPFields {
                Section {
                    DisclosureGroup("高级 Custom HTTP") {
                        TextEditor(text: $viewModel.draft.customBodyTemplate)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 120)
                        TextField(draftPresentation.customResponsePathLabel, text: $viewModel.draft.customResponsePath)
                    }
                }
            }

            Section(connectionPresentation.sectionTitle) {
                Button {
                    Task {
                        await viewModel.testDraftConnection()
                    }
                } label: {
                    Label(connectionPresentation.testButtonLabel, systemImage: "network")
                }
                .disabled(viewModel.isPersistenceBlocked || connectionPresentation.isTesting)

                Button {
                    _ = viewModel.saveDraft()
                } label: {
                    Label(SettingsLocalization.string("settings.action.save"), systemImage: "square.and.arrow.down")
                }
                .disabled(viewModel.isPersistenceBlocked)
                .keyboardShortcut("s", modifiers: [.command])

                if connectionPresentation.showsProgress {
                    ProgressView()
                } else if let message = connectionPresentation.message {
                    connectionStatusMessage(message)
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
            Section("云端续写") {
                LabeledContent(
                    "Provider 调用",
                    value: runtimePreferencesViewModel.preferences.cloudContinuationEnabled ? "续写时启用" : "已关闭"
                )
                LabeledContent(
                    "本地 fallback",
                    value: runtimePreferencesViewModel.preferences.localContinuationEnabledWhenNoProvider ? "没有 provider 时启用" : "已关闭"
                )
            }

            Section("Level 0 本地路径") {
                LabeledContent("URL 与邮箱", value: "不调用 provider")
                LabeledContent("路径与命令", value: "不调用 provider")
                LabeledContent("代码形态输入", value: "不调用 provider")
                LabeledContent("Terminal、iTerm、Xcode", value: "不调用 provider")
            }

            Section("技术 token") {
                Text("API、JSON、macOS、InputMethodKit、snake_case 和 camelCase 会通过本地保护规则保留。")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DiagnosticsSettingsView: View {
    var body: some View {
        SettingsForm(title: SettingsSection.diagnostics.title) {
            Section("本地诊断") {
                ForEach(DebugInstallGuidance.steps) { step in
                    InstallStepView(title: step.title, detail: step.detail)
                }
            }

            Section {
                DisclosureGroup("命令") {
                    ForEach(DebugInstallGuidance.commands, id: \.self) { command in
                        MonospacedText(command)
                    }
                }
            }
        }
    }
}

private struct SettingsForm<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
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
