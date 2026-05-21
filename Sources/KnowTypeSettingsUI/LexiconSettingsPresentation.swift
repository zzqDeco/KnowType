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
        isInstallingRecommendedPack: Bool = false
    ) {
        self.loadedEntries = SettingsKeyValuePresentation(label: "已载入词条", value: "\(totalLoadedEntryCount)")
        self.lastRefreshLabel = "上次刷新"
        self.lastRefreshDate = lastRefreshDate
        self.refreshActionLabel = "刷新"
        self.createSampleActionLabel = "创建示例 TSV"
        self.installRecommendedPackActionLabel = isInstallingRecommendedPack
            ? "正在安装推荐词库..."
            : "安装推荐词库"
        self.isInstallingRecommendedPack = isInstallingRecommendedPack
        self.createMissingDirectoriesActionLabel = "创建缺失目录"
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
    var installedPacks: [InstalledLexiconPackPresentation]
    var diagnostics: [LexiconDiagnosticPresentation]

    init(status: LexiconDirectoryStatus) {
        self.id = status.id
        self.sectionTitle = "目录"
        self.status = SettingsKeyValuePresentation(
            label: "状态",
            value: status.exists ? "可用" : "缺失"
        )
        self.resourceFiles = SettingsKeyValuePresentation(
            label: "资源文件",
            value: "\(status.resourceFileCount)"
        )
        self.loadedEntries = SettingsKeyValuePresentation(
            label: "已载入词条",
            value: "\(status.loadedEntryCount)"
        )
        self.pathLabel = "路径"
        self.path = status.directory.path
        self.installedPacks = status.installedPacks.map(InstalledLexiconPackPresentation.init(status:))
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

    init(status: InstalledLexiconPackStatus) {
        self.id = status.id
        self.title = status.displayName
        self.entries = SettingsKeyValuePresentation(label: "词条", value: "\(status.entryCount)")
        self.license = SettingsKeyValuePresentation(label: "许可证", value: status.licenseName)
        self.source = SettingsKeyValuePresentation(label: "来源", value: status.sourceURL.absoluteString)
        self.installedAt = SettingsKeyValuePresentation(
            label: "安装时间",
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
