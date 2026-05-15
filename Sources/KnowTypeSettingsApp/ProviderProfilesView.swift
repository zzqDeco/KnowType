import KnowTypeCore
import KnowTypeProviders
import SwiftUI

public struct ProviderProfilesView: View {
    @ObservedObject private var viewModel: ProviderProfilesViewModel
    @StateObject private var lexiconViewModel: LexiconSettingsViewModel
    @StateObject private var inputModeViewModel: InputModePreferencesViewModel
    @State private var selectedSection: SettingsSection = .input

    public init(
        viewModel: ProviderProfilesViewModel,
        lexiconViewModel: LexiconSettingsViewModel = LexiconSettingsViewModel(),
        inputModeViewModel: InputModePreferencesViewModel = InputModePreferencesViewModel()
    ) {
        self.viewModel = viewModel
        _lexiconViewModel = StateObject(wrappedValue: lexiconViewModel)
        _inputModeViewModel = StateObject(wrappedValue: inputModeViewModel)
    }

    public var body: some View {
        TabView(selection: $selectedSection) {
            InputSettingsView(viewModel: inputModeViewModel)
                .tabItem {
                    Label("Input", systemImage: "keyboard")
                }
                .tag(SettingsSection.input)

            CandidateSettingsView()
                .tabItem {
                    Label("Candidates", systemImage: "list.bullet.rectangle")
                }
                .tag(SettingsSection.candidates)

            LexiconSettingsView(viewModel: lexiconViewModel)
                .tabItem {
                    Label("Lexicons", systemImage: "books.vertical")
                }
                .tag(SettingsSection.lexicons)

            AIProviderSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("AI Provider", systemImage: "network")
                }
                .tag(SettingsSection.aiProvider)

            PrivacySettingsView()
                .tabItem {
                    Label("Privacy", systemImage: "lock.shield")
                }
                .tag(SettingsSection.privacy)

            DebugInstallSettingsView()
                .tabItem {
                    Label("Debug Install", systemImage: "hammer")
                }
                .tag(SettingsSection.debugInstall)
        }
    }
}

private enum SettingsSection: Hashable {
    case input
    case candidates
    case lexicons
    case aiProvider
    case privacy
    case debugInstall
}

private struct InputSettingsView: View {
    @ObservedObject var viewModel: InputModePreferencesViewModel

    var body: some View {
        SettingsForm {
            Section("Composition") {
                LabeledContent("Input host", value: "InputMethodKit")
                LabeledContent("Composition mode", value: "Marked text before commit")
                LabeledContent("Primary commit", value: "Space commits the corrected prefix")
                LabeledContent("Continuation commit", value: "Tab commits prefix plus continuation")
            }

            Section("Punctuation") {
                Picker("Default punctuation", selection: defaultPunctuationBinding) {
                    Text("Chinese").tag(InputSymbolMode.chinese)
                    Text("English").tag(InputSymbolMode.english)
                }
                Picker("Default width", selection: defaultWidthBinding) {
                    Text("Half width").tag(InputSymbolWidth.halfWidth)
                    Text("Full width").tag(InputSymbolWidth.fullWidth)
                }
                Picker("Code app punctuation", selection: codeAppPunctuationBinding) {
                    Text("Chinese").tag(InputSymbolMode.chinese)
                    Text("English").tag(InputSymbolMode.english)
                }
                Picker("Code app width", selection: codeAppWidthBinding) {
                    Text("Half width").tag(InputSymbolWidth.halfWidth)
                    Text("Full width").tag(InputSymbolWidth.fullWidth)
                }
                LabeledContent("Toggle", value: "Option + .")
                Button {
                    viewModel.resetToDefaults()
                } label: {
                    Label("Restore Defaults", systemImage: "arrow.counterclockwise")
                }
                if let message = viewModel.lastErrorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }

            Section("Prefix Lock") {
                Text("Continuation candidates append after the locked prefix. Prefix rewrites are reserved for explicit polish actions.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var defaultPunctuationBinding: Binding<InputSymbolMode> {
        Binding(
            get: { viewModel.preferences.defaultState.punctuationMode },
            set: { viewModel.setDefaultPunctuationMode($0) }
        )
    }

    private var defaultWidthBinding: Binding<InputSymbolWidth> {
        Binding(
            get: { viewModel.preferences.defaultState.symbolWidth },
            set: { viewModel.setDefaultSymbolWidth($0) }
        )
    }

    private var codeAppPunctuationBinding: Binding<InputSymbolMode> {
        Binding(
            get: { viewModel.preferences.codeAppState.punctuationMode },
            set: { viewModel.setCodeAppPunctuationMode($0) }
        )
    }

    private var codeAppWidthBinding: Binding<InputSymbolWidth> {
        Binding(
            get: { viewModel.preferences.codeAppState.symbolWidth },
            set: { viewModel.setCodeAppSymbolWidth($0) }
        )
    }
}

private struct CandidateSettingsView: View {
    var body: some View {
        SettingsForm {
            Section("Candidate Order") {
                LabeledContent("Prefix candidates", value: "Shown first")
                LabeledContent("Continuation candidates", value: "Shown after prefix candidates")
                LabeledContent("Raw input", value: "Shown only before suggestions are available")
            }

            Section("Shortcuts") {
                LabeledContent("Tab", value: "First continuation")
                LabeledContent("Option + number", value: "Matching continuation row")
                LabeledContent("Option + R", value: "Explicit polish")
            }
        }
    }
}

private struct LexiconSettingsView: View {
    @ObservedObject var viewModel: LexiconSettingsViewModel

    var body: some View {
        SettingsForm {
            Section("Local Lexicons") {
                LabeledContent("Loaded entries", value: "\(viewModel.totalLoadedEntryCount)")
                if let lastRefreshDate = viewModel.lastRefreshDate {
                    LabeledContent("Last refresh", value: lastRefreshDate.formatted(date: .abbreviated, time: .standard))
                }
                Button {
                    viewModel.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button {
                    _ = viewModel.createSampleLexiconResource()
                } label: {
                    Label("Create Sample TSV", systemImage: "doc.badge.plus")
                }
                if viewModel.directories.contains(where: { !$0.exists }) {
                    Button {
                        _ = viewModel.createMissingDirectories()
                    } label: {
                        Label("Create Missing Directories", systemImage: "folder.badge.plus")
                    }
                }
                if let lastActionMessage = viewModel.lastActionMessage {
                    Text(lastActionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(viewModel.directories) { directory in
                Section("Directory") {
                    LabeledContent("Status", value: directory.exists ? "Available" : "Missing")
                    LabeledContent("Resource files", value: "\(directory.resourceFileCount)")
                    LabeledContent("Loaded entries", value: "\(directory.loadedEntryCount)")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Path")
                            .foregroundStyle(.secondary)
                        MonospacedText(directory.directory.path)
                    }

                    if !directory.diagnostics.isEmpty {
                        ForEach(directory.diagnostics) { diagnostic in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(diagnostic.resourceID)
                                    .font(.headline)
                                Text(diagnostic.message)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }

            Section("Format") {
                LabeledContent("TSV", value: "pinyin<TAB>text<TAB>confidence")
                LabeledContent("JSON", value: "TraditionalInputLexiconEntry array")
            }
        }
    }
}

private struct AIProviderSettingsView: View {
    @ObservedObject var viewModel: ProviderProfilesViewModel

    var body: some View {
        NavigationSplitView {
            List(selection: $viewModel.selectedProfileID) {
                ForEach(viewModel.profiles) { profile in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.displayName)
                            .font(.headline)
                        Text(profile.kind.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(profile.id)
                }
            }
            .onChange(of: viewModel.selectedProfileID) { id in
                if let id {
                    viewModel.selectProfile(id: id)
                }
            }
            .toolbar {
                Menu {
                    ForEach(ProviderKind.allCases, id: \.self) { kind in
                        Button(kind.rawValue) {
                            viewModel.createProfile(kind: kind)
                        }
                    }
                } label: {
                    Label("Add Profile", systemImage: "plus")
                }
            }
        } detail: {
            Form {
                Section("Provider") {
                    TextField("Display Name", text: $viewModel.draft.displayName)
                    Picker(
                        "Kind",
                        selection: Binding(
                            get: { viewModel.draft.kind },
                            set: { viewModel.changeDraftKind($0) }
                        )
                    ) {
                        ForEach(ProviderKind.allCases, id: \.self) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    TextField("Base URL", text: $viewModel.draft.baseURL)
                    TextField("Model", text: $viewModel.draft.model)
                    Stepper(value: $viewModel.draft.timeoutSeconds, in: 1...120, step: 1) {
                        Text("Timeout: \(Int(viewModel.draft.timeoutSeconds)) seconds")
                    }
                    Toggle("Default provider", isOn: $viewModel.draft.isDefault)
                }

                Section("API Key") {
                    SecureField("Leave blank to keep existing key", text: $viewModel.draft.apiKey)
                    if let secretName = viewModel.draft.secretName {
                        LabeledContent("Secret reference", value: secretName)
                            .font(.caption)
                    }
                    Text("API keys are written through the secret store. On macOS this uses Keychain; provider JSON stores secret references only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.draft.kind == .customHTTP {
                    Section("Custom HTTP") {
                        TextEditor(text: $viewModel.draft.customBodyTemplate)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 120)
                        TextField("Response Path", text: $viewModel.draft.customResponsePath)
                    }
                }

                Section("Connection") {
                    Button {
                        Task {
                            await viewModel.testDraftConnection()
                        }
                    } label: {
                        Label("Test Connection", systemImage: "network")
                    }
                    .disabled(viewModel.isPersistenceBlocked || viewModel.connectionStatus.isTesting)

                    switch viewModel.connectionStatus {
                    case .idle:
                        EmptyView()
                    case .testing:
                        ProgressView()
                    case .success(let message):
                        Text(message)
                            .foregroundStyle(.secondary)
                    case .failure(let message):
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }

                if !viewModel.validationErrors.isEmpty {
                    Section("Validation") {
                        ForEach(viewModel.validationErrors, id: \.self) { error in
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }
                }

                if let lastErrorMessage = viewModel.lastErrorMessage {
                    Section("Last Error") {
                        Text(lastErrorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .toolbar {
                Button {
                    _ = viewModel.saveDraft()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(viewModel.isPersistenceBlocked)
                .keyboardShortcut("s", modifiers: [.command])
            }
            .padding()
        }
    }
}

private struct PrivacySettingsView: View {
    var body: some View {
        SettingsForm {
            Section("Level 0 Local Path") {
                LabeledContent("URLs and emails", value: "No provider call")
                LabeledContent("Paths and commands", value: "No provider call")
                LabeledContent("Code-like input", value: "No provider call")
                LabeledContent("Terminal, iTerm, Xcode", value: "No provider call")
            }

            Section("Technical Tokens") {
                Text("API, JSON, macOS, InputMethodKit, snake_case, and camelCase are preserved by local protection rules.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DebugInstallSettingsView: View {
    var body: some View {
        SettingsForm {
            Section("Local Development Flow") {
                ForEach(DebugInstallGuidance.steps) { step in
                    InstallStepView(title: step.title, detail: step.detail)
                }
            }

            Section("Commands") {
                ForEach(DebugInstallGuidance.commands, id: \.self) { command in
                    MonospacedText(command)
                }
            }
        }
    }
}

private struct SettingsForm<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .padding()
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
