import Foundation
import KnowTypeCore
import KnowTypeProviders

enum SettingsSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case overview
    case aiProvider
    case input
    case candidates
    case lexicons
    case privacy
    case advanced

    var id: String { rawValue }

    var title: String {
        title(preferredLanguages: Locale.preferredLanguages)
    }

    func title(preferredLanguages: [String]) -> String {
        switch self {
        case .overview:
            SettingsLocalization.string("settings.section.overview", preferredLanguages: preferredLanguages)
        case .aiProvider:
            SettingsLocalization.string("settings.section.ai", preferredLanguages: preferredLanguages)
        case .input:
            SettingsLocalization.string("settings.section.input", preferredLanguages: preferredLanguages)
        case .candidates:
            SettingsLocalization.string("settings.section.candidates", preferredLanguages: preferredLanguages)
        case .lexicons:
            SettingsLocalization.string("settings.section.lexicons", preferredLanguages: preferredLanguages)
        case .privacy:
            SettingsLocalization.string("settings.section.privacy", preferredLanguages: preferredLanguages)
        case .advanced:
            SettingsLocalization.string("settings.section.advanced", preferredLanguages: preferredLanguages)
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "checkmark.seal"
        case .aiProvider:
            "sparkles"
        case .input:
            "keyboard"
        case .candidates:
            "list.bullet.rectangle"
        case .lexicons:
            "folder"
        case .privacy:
            "lock.shield"
        case .advanced:
            "wrench.and.screwdriver"
        }
    }

    var keywords: [String] {
        switch self {
        case .overview:
            ["概览", "首页", "状态", "安装", "可用", "Overview", "status"]
        case .aiProvider:
            ["AI", "续写", "服务", "Provider", "API Key", "模型", "连接"]
        case .input:
            ["输入", "输入体验", "标点", "符号", "前缀", "Input", "punctuation"]
        case .candidates:
            ["候选", "候选窗", "翻页", "快捷键", "Candidates", "panel"]
        case .lexicons:
            ["Rime", "用户数据", "词库", "目录", "lexicon", "data"]
        case .privacy:
            ["隐私", "云端", "本地", "保护", "Privacy"]
        case .advanced:
            ["高级", "诊断", "安装", "日志", "命令", "Custom HTTP", "Base URL", "Diagnostics", "logs"]
        }
    }
}

struct SettingsSidebarPresentation: Equatable, Sendable {
    var sections: [SettingsSection]

    init(searchText: String, preferredLanguages: [String] = Locale.preferredLanguages) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            self.sections = SettingsSection.allCases
            return
        }

        self.sections = SettingsSection.allCases.filter { section in
            ([section.title(preferredLanguages: preferredLanguages)] + section.keywords).contains { candidate in
                candidate.localizedCaseInsensitiveContains(query)
            }
        }
    }
}

struct SettingsOverviewPresentation: Equatable, Sendable {
    var title: String
    var subtitle: String
    var statusRows: [SettingsKeyValuePresentation]
    var checkInstallActionLabel: String
    var configureAIActionLabel: String
    var manageLexiconActionLabel: String
    var openLogsActionLabel: String

    init(
        profiles: [ProviderProfile],
        selectedProfileID: String?,
        runtimePreferences: InputMethodRuntimePreferences,
        totalLoadedEntryCount: Int,
        diagnosticsStatus: InstallationDiagnosticsStatus,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.title = SettingsLocalization.string("settings.overview.title", preferredLanguages: preferredLanguages)
        self.subtitle = SettingsLocalization.string("settings.overview.subtitle", preferredLanguages: preferredLanguages)
        self.checkInstallActionLabel = SettingsLocalization.string(
            "settings.overview.action.checkInstall",
            preferredLanguages: preferredLanguages
        )
        self.configureAIActionLabel = SettingsLocalization.string(
            "settings.overview.action.configureAI",
            preferredLanguages: preferredLanguages
        )
        self.manageLexiconActionLabel = SettingsLocalization.string(
            "settings.overview.action.manageLexicon",
            preferredLanguages: preferredLanguages
        )
        self.openLogsActionLabel = SettingsLocalization.string(
            "settings.overview.action.openLogs",
            preferredLanguages: preferredLanguages
        )

        let missing = SettingsLocalization.string(
            "settings.diagnostics.status.missing",
            preferredLanguages: preferredLanguages
        )
        let version = diagnosticsStatus.installRows.first?.value
        let inputStatus: String
        if let version, version != missing {
            inputStatus = String(
                format: SettingsLocalization.string("settings.overview.input.installed", preferredLanguages: preferredLanguages),
                version
            )
        } else {
            inputStatus = SettingsLocalization.string("settings.overview.input.needsCheck", preferredLanguages: preferredLanguages)
        }

        let activeProfile = profiles.first(where: \.isDefault) ?? profiles.first
        let aiStatus: String
        if runtimePreferences.cloudContinuationEnabled {
            if let activeProfile {
                aiStatus = String(
                    format: SettingsLocalization.string("settings.overview.ai.enabled", preferredLanguages: preferredLanguages),
                    activeProfile.displayName
                )
            } else {
                aiStatus = SettingsLocalization.string("settings.overview.ai.needsService", preferredLanguages: preferredLanguages)
            }
        } else {
            aiStatus = SettingsLocalization.string("settings.overview.ai.disabled", preferredLanguages: preferredLanguages)
        }

        let lexiconStatus = String(
            format: SettingsLocalization.string("settings.overview.lexicon.loaded", preferredLanguages: preferredLanguages),
            totalLoadedEntryCount
        )
        let privacyStatus = runtimePreferences.cloudContinuationEnabled
            ? SettingsLocalization.string("settings.overview.privacy.cloudEnabled", preferredLanguages: preferredLanguages)
            : SettingsLocalization.string("settings.overview.privacy.localOnly", preferredLanguages: preferredLanguages)

        self.statusRows = [
            SettingsKeyValuePresentation(
                label: SettingsLocalization.string("settings.overview.input", preferredLanguages: preferredLanguages),
                value: inputStatus
            ),
            SettingsKeyValuePresentation(
                label: SettingsLocalization.string("settings.overview.ai", preferredLanguages: preferredLanguages),
                value: aiStatus
            ),
            SettingsKeyValuePresentation(
                label: SettingsLocalization.string("settings.overview.lexicon", preferredLanguages: preferredLanguages),
                value: lexiconStatus
            ),
            SettingsKeyValuePresentation(
                label: SettingsLocalization.string("settings.overview.privacy", preferredLanguages: preferredLanguages),
                value: privacyStatus
            )
        ]
    }
}

struct SettingsKeyValuePresentation: Equatable, Sendable {
    var label: String
    var value: String
}

enum SettingsDirectoryOpener {
    static func prepareDirectoryForOpening(_ url: URL, fileManager: FileManager = .default) throws -> URL {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

struct ProviderProfileListItemPresentation: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var subtitle: String

    init(profile: ProviderProfile) {
        self.id = profile.id
        self.title = profile.displayName
        self.subtitle = profile.kind.rawValue
    }
}

struct ProviderProfileDraftPresentation: Equatable, Sendable {
    var displayNameFieldLabel: String
    var kindPickerLabel: String
    var baseURLFieldLabel: String
    var modelFieldLabel: String
    var timeoutLabel: String
    var defaultProviderLabel: String
    var showsCustomHTTPFields: Bool
    var customBodyTemplateLabel: String
    var customResponsePathLabel: String
    var secret: ProviderSecretPresentation

    init(draft: ProviderProfileDraft, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.displayNameFieldLabel = SettingsLocalization.string(
            "settings.provider.displayName",
            preferredLanguages: preferredLanguages
        )
        self.kindPickerLabel = SettingsLocalization.string(
            "settings.provider.kind",
            preferredLanguages: preferredLanguages
        )
        self.baseURLFieldLabel = SettingsLocalization.string(
            "settings.provider.baseURL",
            preferredLanguages: preferredLanguages
        )
        self.modelFieldLabel = SettingsLocalization.string(
            "settings.provider.model",
            preferredLanguages: preferredLanguages
        )
        self.timeoutLabel = String(
            format: SettingsLocalization.string("settings.provider.timeout", preferredLanguages: preferredLanguages),
            Int(draft.timeoutSeconds)
        )
        self.defaultProviderLabel = SettingsLocalization.string(
            "settings.provider.default",
            preferredLanguages: preferredLanguages
        )
        self.showsCustomHTTPFields = draft.kind == .customHTTP
        self.customBodyTemplateLabel = SettingsLocalization.string(
            "settings.provider.customHTTP",
            preferredLanguages: preferredLanguages
        )
        self.customResponsePathLabel = SettingsLocalization.string(
            "settings.provider.responsePath",
            preferredLanguages: preferredLanguages
        )
        self.secret = ProviderSecretPresentation(secretName: draft.secretName, preferredLanguages: preferredLanguages)
    }
}

struct ProviderSecretPresentation: Equatable, Sendable {
    var sectionTitle: String
    var apiKeyFieldPrompt: String
    var reference: SettingsKeyValuePresentation?
    var helpText: String

    init(secretName: String?, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.sectionTitle = SettingsLocalization.string(
            "settings.provider.apiKey",
            preferredLanguages: preferredLanguages
        )
        self.apiKeyFieldPrompt = SettingsLocalization.string(
            "settings.provider.secretPrompt",
            preferredLanguages: preferredLanguages
        )
        self.reference = secretName.map {
            SettingsKeyValuePresentation(
                label: SettingsLocalization.string(
                    "settings.provider.secretReference",
                    preferredLanguages: preferredLanguages
                ),
                value: $0
            )
        }
        self.helpText = SettingsLocalization.string(
            "settings.provider.secretHelp",
            preferredLanguages: preferredLanguages
        )
    }
}

struct ProviderConnectionStatusPresentation: Equatable, Sendable {
    var sectionTitle: String
    var testButtonLabel: String
    var showsProgress: Bool
    var message: ProviderStatusMessagePresentation?

    var isTesting: Bool {
        showsProgress
    }

    init(status: ProviderConnectionStatus, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.sectionTitle = SettingsLocalization.string(
            "settings.provider.connection",
            preferredLanguages: preferredLanguages
        )
        self.testButtonLabel = SettingsLocalization.string(
            "settings.action.testConnection",
            preferredLanguages: preferredLanguages
        )
        switch status {
        case .idle:
            self.showsProgress = false
            self.message = nil
        case .testing:
            self.showsProgress = true
            self.message = nil
        case .success(let message):
            self.showsProgress = false
            self.message = ProviderStatusMessagePresentation(text: message, tone: .secondary)
        case .failure(let message):
            self.showsProgress = false
            self.message = ProviderStatusMessagePresentation(text: message, tone: .error)
        }
    }
}

struct ProviderStatusMessagePresentation: Equatable, Sendable {
    enum Tone: Equatable, Sendable {
        case secondary
        case error
    }

    var text: String
    var tone: Tone
}

struct ProviderValidationPresentation: Equatable, Sendable {
    var title: String
    var messages: [String]

    var isVisible: Bool {
        !messages.isEmpty
    }

    init(errors: [String], preferredLanguages: [String] = Locale.preferredLanguages) {
        self.title = SettingsLocalization.string(
            "settings.provider.validation",
            preferredLanguages: preferredLanguages
        )
        self.messages = errors
    }
}

struct ProviderLastErrorPresentation: Equatable, Sendable {
    var title: String
    var message: String?

    var isVisible: Bool {
        message != nil
    }

    init(message: String?, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.title = SettingsLocalization.string(
            "settings.provider.lastError",
            preferredLanguages: preferredLanguages
        )
        self.message = message
    }
}
