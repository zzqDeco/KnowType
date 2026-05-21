import Foundation

struct LexiconSettingsPresentation: Equatable, Sendable {
    var loadedEntries: SettingsKeyValuePresentation
    var lastRefreshLabel: String
    var lastRefreshDate: Date?
    var refreshActionLabel: String
    var createSampleActionLabel: String
    var installRecommendedPackActionLabel: String
    var isInstallingRecommendedPack: Bool
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
            lastActionMessage: viewModel.lastActionMessage,
            isInstallingRecommendedPack: viewModel.isInstallingRecommendedPack
        )
    }

    init(
        totalLoadedEntryCount: Int,
        lastRefreshDate: Date?,
        directories: [LexiconDirectoryStatus],
        lastActionMessage: String?,
        isInstallingRecommendedPack: Bool = false,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.loadedEntries = SettingsKeyValuePresentation(
            label: SettingsLocalization.string("settings.lexicon.loadedEntries", preferredLanguages: preferredLanguages),
            value: "\(totalLoadedEntryCount)"
        )
        self.lastRefreshLabel = SettingsLocalization.string(
            "settings.lexicon.lastRefresh",
            preferredLanguages: preferredLanguages
        )
        self.lastRefreshDate = lastRefreshDate
        self.refreshActionLabel = SettingsLocalization.string(
            "settings.lexicon.refresh",
            preferredLanguages: preferredLanguages
        )
        self.createSampleActionLabel = SettingsLocalization.string(
            "settings.lexicon.createSample",
            preferredLanguages: preferredLanguages
        )
        self.installRecommendedPackActionLabel = isInstallingRecommendedPack
            ? SettingsLocalization.string("settings.lexicon.installingRecommended", preferredLanguages: preferredLanguages)
            : SettingsLocalization.string("settings.lexicon.installRecommended", preferredLanguages: preferredLanguages)
        self.isInstallingRecommendedPack = isInstallingRecommendedPack
        self.createMissingDirectoriesActionLabel = SettingsLocalization.string(
            "settings.lexicon.createMissingDirectories",
            preferredLanguages: preferredLanguages
        )
        self.showsCreateMissingDirectoriesAction = directories.contains { !$0.exists }
        self.lastActionMessage = lastActionMessage
        self.directories = directories.map {
            LexiconDirectoryPresentation(status: $0, preferredLanguages: preferredLanguages)
        }
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
    var installedPacks: [InstalledLexiconPackPresentation]
    var diagnostics: [LexiconDiagnosticPresentation]

    init(status: LexiconDirectoryStatus, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.id = status.id
        self.sectionTitle = SettingsLocalization.string(
            "settings.lexicon.directory",
            preferredLanguages: preferredLanguages
        )
        self.status = SettingsKeyValuePresentation(
            label: SettingsLocalization.string("settings.lexicon.status", preferredLanguages: preferredLanguages),
            value: status.exists
                ? SettingsLocalization.string("settings.lexicon.status.available", preferredLanguages: preferredLanguages)
                : SettingsLocalization.string("settings.lexicon.status.missing", preferredLanguages: preferredLanguages)
        )
        self.resourceFiles = SettingsKeyValuePresentation(
            label: SettingsLocalization.string("settings.lexicon.resourceFiles", preferredLanguages: preferredLanguages),
            value: "\(status.resourceFileCount)"
        )
        self.loadedEntries = SettingsKeyValuePresentation(
            label: SettingsLocalization.string("settings.lexicon.loadedEntries", preferredLanguages: preferredLanguages),
            value: "\(status.loadedEntryCount)"
        )
        self.pathLabel = SettingsLocalization.string("settings.lexicon.path", preferredLanguages: preferredLanguages)
        self.path = status.directory.path
        self.installedPacks = status.installedPacks.map {
            InstalledLexiconPackPresentation(status: $0, preferredLanguages: preferredLanguages)
        }
        self.diagnostics = status.diagnostics.map(LexiconDiagnosticPresentation.init(diagnostic:))
    }
}

struct InstalledLexiconPackPresentation: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var entries: SettingsKeyValuePresentation
    var license: SettingsKeyValuePresentation
    var source: SettingsKeyValuePresentation
    var installedAt: SettingsKeyValuePresentation

    init(status: InstalledLexiconPackStatus, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.id = status.id
        self.title = status.displayName
        self.entries = SettingsKeyValuePresentation(
            label: SettingsLocalization.string("settings.lexicon.entries", preferredLanguages: preferredLanguages),
            value: "\(status.entryCount)"
        )
        self.license = SettingsKeyValuePresentation(
            label: SettingsLocalization.string("settings.lexicon.license", preferredLanguages: preferredLanguages),
            value: status.licenseName
        )
        self.source = SettingsKeyValuePresentation(
            label: SettingsLocalization.string("settings.lexicon.source", preferredLanguages: preferredLanguages),
            value: status.sourceURL.absoluteString
        )
        self.installedAt = SettingsKeyValuePresentation(
            label: SettingsLocalization.string("settings.lexicon.installedAt", preferredLanguages: preferredLanguages),
            value: status.installedAt.formatted(date: .abbreviated, time: .shortened)
        )
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
