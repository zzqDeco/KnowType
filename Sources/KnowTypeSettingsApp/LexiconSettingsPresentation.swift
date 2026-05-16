import Foundation

struct LexiconSettingsPresentation: Equatable, Sendable {
    var loadedEntries: SettingsKeyValuePresentation
    var lastRefreshLabel: String
    var lastRefreshDate: Date?
    var refreshActionLabel: String
    var createSampleActionLabel: String
    var createMissingDirectoriesActionLabel: String
    var showsCreateMissingDirectoriesAction: Bool
    var lastActionMessage: String?
    var directories: [LexiconDirectoryPresentation]
    var formatRows: [SettingsKeyValuePresentation]

    @MainActor
    init(viewModel: LexiconSettingsViewModel) {
        self.init(
            totalLoadedEntryCount: viewModel.totalLoadedEntryCount,
            lastRefreshDate: viewModel.lastRefreshDate,
            directories: viewModel.directories,
            lastActionMessage: viewModel.lastActionMessage
        )
    }

    init(
        totalLoadedEntryCount: Int,
        lastRefreshDate: Date?,
        directories: [LexiconDirectoryStatus],
        lastActionMessage: String?
    ) {
        self.loadedEntries = SettingsKeyValuePresentation(label: "Loaded entries", value: "\(totalLoadedEntryCount)")
        self.lastRefreshLabel = "Last refresh"
        self.lastRefreshDate = lastRefreshDate
        self.refreshActionLabel = "Refresh"
        self.createSampleActionLabel = "Create Sample TSV"
        self.createMissingDirectoriesActionLabel = "Create Missing Directories"
        self.showsCreateMissingDirectoriesAction = directories.contains { !$0.exists }
        self.lastActionMessage = lastActionMessage
        self.directories = directories.map(LexiconDirectoryPresentation.init(status:))
        self.formatRows = [
            SettingsKeyValuePresentation(label: "TSV", value: "pinyin<TAB>text<TAB>confidence"),
            SettingsKeyValuePresentation(label: "JSON", value: "TraditionalInputLexiconEntry array")
        ]
    }
}

struct LexiconDirectoryPresentation: Equatable, Identifiable, Sendable {
    var id: String
    var sectionTitle: String
    var status: SettingsKeyValuePresentation
    var resourceFiles: SettingsKeyValuePresentation
    var loadedEntries: SettingsKeyValuePresentation
    var pathLabel: String
    var path: String
    var diagnostics: [LexiconDiagnosticPresentation]

    init(status: LexiconDirectoryStatus) {
        self.id = status.id
        self.sectionTitle = "Directory"
        self.status = SettingsKeyValuePresentation(
            label: "Status",
            value: status.exists ? "Available" : "Missing"
        )
        self.resourceFiles = SettingsKeyValuePresentation(
            label: "Resource files",
            value: "\(status.resourceFileCount)"
        )
        self.loadedEntries = SettingsKeyValuePresentation(
            label: "Loaded entries",
            value: "\(status.loadedEntryCount)"
        )
        self.pathLabel = "Path"
        self.path = status.directory.path
        self.diagnostics = status.diagnostics.map(LexiconDiagnosticPresentation.init(diagnostic:))
    }
}

struct LexiconDiagnosticPresentation: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var message: String

    init(diagnostic: LexiconDiagnosticStatus) {
        self.id = diagnostic.id
        self.title = diagnostic.resourceID
        self.message = diagnostic.message
    }
}
