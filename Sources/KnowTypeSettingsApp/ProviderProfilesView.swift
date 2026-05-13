import KnowTypeProviders
import SwiftUI

public struct ProviderProfilesView: View {
    @ObservedObject private var viewModel: ProviderProfilesViewModel

    public init(viewModel: ProviderProfilesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
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
                        Text(secretName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.draft.kind == .customHTTP {
                    Section("Custom HTTP") {
                        TextEditor(text: $viewModel.draft.customBodyTemplate)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 120)
                        TextField("Response Path", text: $viewModel.draft.customResponsePath)
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
