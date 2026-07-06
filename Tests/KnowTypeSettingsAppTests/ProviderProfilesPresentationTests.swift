import Foundation
import XCTest
@testable import KnowTypeCore
@testable import KnowTypeProviders
@testable import KnowTypeSettingsUI

final class ProviderProfilesPresentationTests: XCTestCase {
    func testSettingsSidebarUsesChineseNativeSectionsAndSearch() {
        let allSections = SettingsSidebarPresentation(searchText: "", preferredLanguages: ["zh-Hans-CN"])

        XCTAssertEqual(
            allSections.sections.map { $0.title(preferredLanguages: ["zh-Hans-CN"]) },
            ["概览", "AI 续写", "输入体验", "候选窗", "词库", "隐私", "高级"]
        )
        XCTAssertEqual(SettingsSection.overview.systemImage, "checkmark.seal")
        XCTAssertEqual(SettingsSection.aiProvider.systemImage, "sparkles")
        XCTAssertEqual(SettingsSection.advanced.systemImage, "wrench.and.screwdriver")

        let aiSearch = SettingsSidebarPresentation(searchText: "模型", preferredLanguages: ["zh-Hans-CN"])
        XCTAssertEqual(aiSearch.sections, [.aiProvider])

        let lexiconSearch = SettingsSidebarPresentation(searchText: "Rime", preferredLanguages: ["zh-Hans-CN"])
        XCTAssertEqual(lexiconSearch.sections, [.lexicons])

        let advancedSearch = SettingsSidebarPresentation(searchText: "Base URL", preferredLanguages: ["zh-Hans-CN"])
        XCTAssertEqual(advancedSearch.sections, [.advanced])

        let emptySearch = SettingsSidebarPresentation(searchText: "不存在", preferredLanguages: ["zh-Hans-CN"])
        XCTAssertTrue(emptySearch.sections.isEmpty)
    }

    func testSettingsLocalizationRespectsPreferredLanguagesAndFallbacks() {
        XCTAssertEqual(
            SettingsLocalization.string("settings.window.title", preferredLanguages: ["zh-Hans-CN"]),
            "KnowType 设置"
        )
        XCTAssertEqual(
            SettingsLocalization.string("settings.section.ai", preferredLanguages: ["zh-Hant-TW"]),
            "AI 续写"
        )
        XCTAssertEqual(
            SettingsLocalization.string("settings.section.ai", preferredLanguages: ["en-US"]),
            "AI 续写"
        )
        XCTAssertEqual(
            SettingsLocalization.string("settings.section.ai", localeIdentifier: "en"),
            "AI Continuation"
        )
        XCTAssertEqual(
            SettingsLocalization.string("settings.action.testConnection", localeIdentifier: "en-US"),
            "Test Connection"
        )
        XCTAssertEqual(
            SettingsLocalization.string("settings.action.testConnection", localeIdentifier: "fr-FR"),
            "测试连接"
        )
    }

    func testSettingsLocalizationFallsBackWhenPreferredBundleLacksKey() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-settings-localization-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let zhBundle = try makeLocalizationBundle(
            rootURL: temporaryDirectory,
            language: "zh-Hans",
            strings: #""settings.window.title" = "KnowType 设置";"#
        )
        let englishBundle = try makeLocalizationBundle(
            rootURL: temporaryDirectory,
            language: "en",
            strings: #""settings.test.englishOnly" = "English fallback";"#
        )

        let value = SettingsLocalization.string(
            "settings.test.englishOnly",
            preferredLanguages: ["zh-Hans-CN"],
            bundleResolver: { identifier in
                identifier.hasPrefix("zh") ? zhBundle : englishBundle
            }
        )

        XCTAssertEqual(value, "English fallback")
    }

    func testSettingsDetailDoesNotReplaceWindowTitleWithSectionTitle() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeSettingsUI/ProviderProfilesView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains(".navigationTitle(selectedSection.title)"))
        XCTAssertTrue(source.contains("SettingsForm(title: SettingsSection.input.title)"))
        XCTAssertTrue(source.contains("@State private var selectedSection: SettingsSection = .overview"))
    }

    func testSettingsViewKeepsTechnicalDetailsBehindAdvancedDisclosures() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeSettingsUI/ProviderProfilesView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("SettingsOverviewView("))
        XCTAssertTrue(source.contains("DisclosureGroup(settingsString(\"settings.provider.advancedServiceConfig\"))"))
        XCTAssertTrue(source.contains("DisclosureGroup(settingsString(\"settings.lexicon.disclosure.directories\"))"))
        XCTAssertTrue(source.contains("SettingsForm(title: SettingsSection.advanced.title"))
        XCTAssertFalse(source.contains("SettingsForm(title: SettingsSection.diagnostics.title"))
    }

    func testOverviewPresentationShowsUserFacingStatusWithoutProviderInternals() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-settings-overview-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let diagnostics = InstallationDiagnosticsStatus(
            applicationSupportURL: temporaryDirectory.appendingPathComponent("Application Support/KnowType", isDirectory: true),
            homeDirectoryURL: temporaryDirectory,
            inputMethodBundleURL: temporaryDirectory.appendingPathComponent("Input Methods/KnowType.app", isDirectory: true),
            preferencePaneURL: temporaryDirectory.appendingPathComponent("PreferencePanes/KnowType.prefPane", isDirectory: true),
            runtimePreferences: .standard,
            preferredLanguages: ["zh-Hans-CN"]
        )
        let profile = ProviderProfile(
            id: "local",
            displayName: "本地代理",
            kind: .openAIChat,
            baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
            model: "gpt-5.3-codex-spark",
            isDefault: true
        )
        let presentation = SettingsOverviewPresentation(
            profiles: [profile],
            selectedProfileID: profile.id,
            runtimePreferences: .standard,
            totalLoadedEntryCount: 123,
            diagnosticsStatus: diagnostics,
            preferredLanguages: ["zh-Hans-CN"]
        )

        XCTAssertEqual(presentation.title, "概览")
        XCTAssertEqual(presentation.checkInstallActionLabel, "检查输入法状态")
        XCTAssertEqual(presentation.configureAIActionLabel, "配置 AI 续写")
        XCTAssertEqual(presentation.manageLexiconActionLabel, "管理词库")
        XCTAssertEqual(presentation.openLogsActionLabel, "打开日志")
        XCTAssertEqual(
            presentation.statusRows,
            [
                SettingsKeyValuePresentation(label: "输入法", value: "需要检查安装状态"),
                SettingsKeyValuePresentation(label: "AI 续写", value: "已启用：本地代理"),
                SettingsKeyValuePresentation(label: "词库", value: "已载入 123 条词条"),
                SettingsKeyValuePresentation(label: "隐私", value: "云端续写开启，受保护输入仍只走本地")
            ]
        )
        let reflected = String(reflecting: presentation)
        XCTAssertFalse(reflected.contains("Base URL"))
        XCTAssertFalse(reflected.contains("Custom HTTP"))
        XCTAssertFalse(reflected.contains("API Key"))
    }

    func testOverviewPresentationUsesDefaultProfileForActiveAIStatus() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-settings-overview-default-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let diagnostics = InstallationDiagnosticsStatus(
            applicationSupportURL: temporaryDirectory.appendingPathComponent("Application Support/KnowType", isDirectory: true),
            homeDirectoryURL: temporaryDirectory,
            inputMethodBundleURL: temporaryDirectory.appendingPathComponent("Input Methods/KnowType.app", isDirectory: true),
            preferencePaneURL: temporaryDirectory.appendingPathComponent("PreferencePanes/KnowType.prefPane", isDirectory: true),
            runtimePreferences: .standard,
            preferredLanguages: ["zh-Hans-CN"]
        )
        let defaultProfile = ProviderProfile(
            id: "runtime-default",
            displayName: "当前运行服务",
            kind: .openAIChat,
            baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
            model: "spark",
            isDefault: true
        )
        let editingProfile = ProviderProfile(
            id: "editing-only",
            displayName: "正在编辑的服务",
            kind: .customHTTP,
            baseURL: URL(string: "http://127.0.0.1:8318/complete")!,
            model: ""
        )

        let presentation = SettingsOverviewPresentation(
            profiles: [defaultProfile, editingProfile],
            selectedProfileID: editingProfile.id,
            runtimePreferences: .standard,
            totalLoadedEntryCount: 0,
            diagnosticsStatus: diagnostics,
            preferredLanguages: ["zh-Hans-CN"]
        )

        XCTAssertEqual(
            presentation.statusRows.first { $0.label == "AI 续写" }?.value,
            "已启用：当前运行服务"
        )
    }

    func testOverviewPresentationRequiresExplicitDefaultProfileForActiveAIStatus() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-settings-overview-no-default-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let diagnostics = InstallationDiagnosticsStatus(
            applicationSupportURL: temporaryDirectory.appendingPathComponent("Application Support/KnowType", isDirectory: true),
            homeDirectoryURL: temporaryDirectory,
            inputMethodBundleURL: temporaryDirectory.appendingPathComponent("Input Methods/KnowType.app", isDirectory: true),
            preferencePaneURL: temporaryDirectory.appendingPathComponent("PreferencePanes/KnowType.prefPane", isDirectory: true),
            runtimePreferences: .standard,
            preferredLanguages: ["zh-Hans-CN"]
        )
        let profile = ProviderProfile(
            id: "configured-but-not-default",
            displayName: "未设默认",
            kind: .openAIChat,
            baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
            model: "spark"
        )

        let presentation = SettingsOverviewPresentation(
            profiles: [profile],
            selectedProfileID: profile.id,
            runtimePreferences: .standard,
            totalLoadedEntryCount: 0,
            diagnosticsStatus: diagnostics,
            preferredLanguages: ["zh-Hans-CN"]
        )

        XCTAssertEqual(
            presentation.statusRows.first { $0.label == "AI 续写" }?.value,
            "已启用，尚未配置服务"
        )
    }

    func testSettingsDirectoryOpenerCreatesMissingDirectoriesBeforeOpening() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-settings-open-directory-\(UUID().uuidString)", isDirectory: true)
        let target = temporaryDirectory
            .appendingPathComponent("Library/Logs/KnowType", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        let prepared = try SettingsDirectoryOpener.prepareDirectoryForOpening(target)

        XCTAssertEqual(prepared, target)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testSettingsViewSeparatesSavedServiceAndDraftConnectionTests() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeSettingsUI/ProviderProfilesView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("await viewModel.testSavedProfileConnection()"))
        XCTAssertTrue(source.contains("await viewModel.testDraftConnection()"))
        XCTAssertTrue(source.contains("get: { activeProfileID }"))
        XCTAssertTrue(source.contains("editProfileSelectionBinding"))
        XCTAssertTrue(source.contains("settings.provider.editProfile"))
        XCTAssertFalse(source.contains("try viewModel.setDefaultProfile(id: id)\n                        viewModel.selectProfile(id: id)"))
    }

    func testListItemUsesSavedDisplayNameAndProviderKind() {
        let profile = ProviderProfile(
            id: "work",
            displayName: "Work OpenAI",
            kind: .openAIResponses,
            baseURL: URL(string: "https://api.openai.com")!,
            model: "gpt-4.1-mini"
        )

        let item = ProviderProfileListItemPresentation(profile: profile)

        XCTAssertEqual(item.id, "work")
        XCTAssertEqual(item.title, "Work OpenAI")
        XCTAssertEqual(item.subtitle, "openai_responses")
    }

    func testDraftPresentationShowsCustomHTTPFieldsOnlyForCustomProfiles() {
        let customProfile = ProviderProfile(
            id: "proxy",
            displayName: "Proxy",
            kind: .customHTTP,
            baseURL: URL(string: "https://proxy.example.com/complete")!,
            model: "",
            customBodyTemplate: #"{"request":{{request_json}}}"#,
            customResponsePath: "candidates"
        )
        var customDraft = ProviderProfileDraft(profile: customProfile)
        customDraft.timeoutSeconds = 37

        let customPresentation = ProviderProfileDraftPresentation(draft: customDraft, preferredLanguages: ["zh-Hans-CN"])

        XCTAssertEqual(customPresentation.displayNameFieldLabel, "显示名称")
        XCTAssertEqual(customPresentation.kindPickerLabel, "Provider 类型")
        XCTAssertEqual(customPresentation.baseURLFieldLabel, "Base URL")
        XCTAssertEqual(customPresentation.modelFieldLabel, "模型")
        XCTAssertEqual(customPresentation.timeoutLabel, "超时：37 秒")
        XCTAssertEqual(customPresentation.defaultProviderLabel, "设为默认 provider")
        XCTAssertTrue(customPresentation.showsCustomHTTPFields)
        XCTAssertEqual(customPresentation.customBodyTemplateLabel, "Custom HTTP")
        XCTAssertEqual(customPresentation.customResponsePathLabel, "Response Path")

        let chatDraft = ProviderProfileDraft(
            profile: ProviderProfile(
                displayName: "Chat",
                kind: .openAIChat,
                baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
                model: ""
            )
        )

        XCTAssertFalse(
            ProviderProfileDraftPresentation(
                draft: chatDraft,
                preferredLanguages: ["zh-Hans-CN"]
            ).showsCustomHTTPFields
        )

        let englishPreferredPresentation = ProviderProfileDraftPresentation(draft: customDraft, preferredLanguages: ["en-US"])
        XCTAssertEqual(englishPreferredPresentation.displayNameFieldLabel, "显示名称")
        XCTAssertEqual(englishPreferredPresentation.kindPickerLabel, "Provider 类型")
        XCTAssertEqual(englishPreferredPresentation.modelFieldLabel, "模型")
        XCTAssertEqual(englishPreferredPresentation.timeoutLabel, "超时：37 秒")
        XCTAssertEqual(englishPreferredPresentation.defaultProviderLabel, "设为默认 provider")
    }

    func testSecretPresentationLabelsSecretReferenceWithoutExposingTypedAPIKey() {
        var draft = ProviderProfileDraft(
            profile: ProviderProfile(
                id: "work",
                displayName: "Work",
                kind: .openAIChat,
                baseURL: URL(string: "https://api.openai.com")!,
                model: "gpt-4.1-mini",
                secretName: "knowtype.provider.work.apiKey"
            )
        )
        draft.apiKey = "sk-typed-secret"

        let presentation = ProviderProfileDraftPresentation(draft: draft, preferredLanguages: ["zh-Hans-CN"])

        XCTAssertEqual(presentation.secret.sectionTitle, "API Key")
        XCTAssertEqual(presentation.secret.apiKeyFieldPrompt, "留空则保留现有 key")
        XCTAssertEqual(
            presentation.secret.reference,
            SettingsKeyValuePresentation(
                label: "Secret 引用",
                value: "knowtype.provider.work.apiKey"
            )
        )
        XCTAssertTrue(presentation.secret.helpText.contains("Keychain"))
        XCTAssertFalse(String(reflecting: presentation).contains("sk-typed-secret"))

        let englishPreferredPresentation = ProviderProfileDraftPresentation(draft: draft, preferredLanguages: ["en-US"])
        XCTAssertEqual(englishPreferredPresentation.secret.apiKeyFieldPrompt, "留空则保留现有 key")
        XCTAssertEqual(englishPreferredPresentation.secret.reference?.label, "Secret 引用")
    }

    func testConnectionStatusPresentationMapsProgressSuccessAndFailure() {
        let idle = ProviderConnectionStatusPresentation(status: .idle, preferredLanguages: ["zh-Hans-CN"])
        XCTAssertEqual(idle.sectionTitle, "连接")
        XCTAssertEqual(idle.testButtonLabel, "测试连接")
        XCTAssertFalse(idle.showsProgress)
        XCTAssertFalse(idle.isTesting)
        XCTAssertNil(idle.message)

        let testing = ProviderConnectionStatusPresentation(status: .testing)
        XCTAssertTrue(testing.showsProgress)
        XCTAssertTrue(testing.isTesting)
        XCTAssertNil(testing.message)

        let englishPreferred = ProviderConnectionStatusPresentation(status: .idle, preferredLanguages: ["en-US"])
        XCTAssertEqual(englishPreferred.sectionTitle, "连接")
        XCTAssertEqual(englishPreferred.testButtonLabel, "测试连接")

        let success = ProviderConnectionStatusPresentation(status: .success("Connected to openai_chat."))
        XCTAssertFalse(success.showsProgress)
        XCTAssertEqual(
            success.message,
            ProviderStatusMessagePresentation(text: "Connected to openai_chat.", tone: .secondary)
        )

        let failure = ProviderConnectionStatusPresentation(status: .failure("Timed out."))
        XCTAssertFalse(failure.showsProgress)
        XCTAssertEqual(
            failure.message,
            ProviderStatusMessagePresentation(text: "Timed out.", tone: .error)
        )
    }

    func testValidationAndLastErrorPresentationsControlSectionVisibility() {
        let emptyValidation = ProviderValidationPresentation(errors: [], preferredLanguages: ["zh-Hans-CN"])
        XCTAssertFalse(emptyValidation.isVisible)
        XCTAssertEqual(emptyValidation.title, "校验")

        let validation = ProviderValidationPresentation(errors: ["模型不能为空。"], preferredLanguages: ["zh-Hans-CN"])
        XCTAssertTrue(validation.isVisible)
        XCTAssertEqual(validation.messages, ["模型不能为空。"])

        let emptyError = ProviderLastErrorPresentation(message: nil, preferredLanguages: ["zh-Hans-CN"])
        XCTAssertFalse(emptyError.isVisible)
        XCTAssertNil(emptyError.message)

        let error = ProviderLastErrorPresentation(message: "save failed", preferredLanguages: ["zh-Hans-CN"])
        XCTAssertTrue(error.isVisible)
        XCTAssertEqual(error.title, "最近错误")
        XCTAssertEqual(error.message, "save failed")

        XCTAssertEqual(
            ProviderValidationPresentation(errors: [], preferredLanguages: ["en-US"]).title,
            "校验"
        )
        XCTAssertEqual(
            ProviderLastErrorPresentation(message: nil, preferredLanguages: ["en-US"]).title,
            "最近错误"
        )
    }
}

private func makeLocalizationBundle(
    rootURL: URL,
    language: String,
    strings: String
) throws -> Bundle {
    let bundleURL = rootURL.appendingPathComponent("\(language).lproj", isDirectory: true)
    try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
    try strings.write(
        to: bundleURL.appendingPathComponent("Localizable.strings"),
        atomically: true,
        encoding: .utf8
    )
    return try XCTUnwrap(Bundle(url: bundleURL))
}
