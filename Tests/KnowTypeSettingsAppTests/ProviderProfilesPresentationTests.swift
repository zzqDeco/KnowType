import Foundation
import XCTest
@testable import KnowTypeProviders
@testable import KnowTypeSettingsUI

final class ProviderProfilesPresentationTests: XCTestCase {
    func testSettingsSidebarUsesChineseNativeSectionsAndSearch() {
        let allSections = SettingsSidebarPresentation(searchText: "", preferredLanguages: ["zh-Hans-CN"])

        XCTAssertEqual(
            allSections.sections.map { $0.title(preferredLanguages: ["zh-Hans-CN"]) },
            ["输入", "候选窗", "Rime 与用户数据", "AI 续写", "隐私", "诊断"]
        )
        XCTAssertEqual(SettingsSection.input.systemImage, "keyboard")
        XCTAssertEqual(SettingsSection.aiProvider.systemImage, "sparkles")

        let aiSearch = SettingsSidebarPresentation(searchText: "模型", preferredLanguages: ["zh-Hans-CN"])
        XCTAssertEqual(aiSearch.sections, [.aiProvider])

        let lexiconSearch = SettingsSidebarPresentation(searchText: "Rime", preferredLanguages: ["zh-Hans-CN"])
        XCTAssertEqual(lexiconSearch.sections, [.lexicons])

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
            "AI Continuation"
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
            "Test Connection"
        )
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

        let englishPresentation = ProviderProfileDraftPresentation(draft: customDraft, preferredLanguages: ["en-US"])
        XCTAssertEqual(englishPresentation.displayNameFieldLabel, "Display Name")
        XCTAssertEqual(englishPresentation.kindPickerLabel, "Provider Type")
        XCTAssertEqual(englishPresentation.modelFieldLabel, "Model")
        XCTAssertEqual(englishPresentation.timeoutLabel, "Timeout: 37 seconds")
        XCTAssertEqual(englishPresentation.defaultProviderLabel, "Default provider")
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

        let englishPresentation = ProviderProfileDraftPresentation(draft: draft, preferredLanguages: ["en-US"])
        XCTAssertEqual(englishPresentation.secret.apiKeyFieldPrompt, "Leave blank to keep the existing key")
        XCTAssertEqual(englishPresentation.secret.reference?.label, "Secret Reference")
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

        let english = ProviderConnectionStatusPresentation(status: .idle, preferredLanguages: ["en-US"])
        XCTAssertEqual(english.sectionTitle, "Connection")
        XCTAssertEqual(english.testButtonLabel, "Test Connection")

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

        let validation = ProviderValidationPresentation(errors: ["Model is required."], preferredLanguages: ["zh-Hans-CN"])
        XCTAssertTrue(validation.isVisible)
        XCTAssertEqual(validation.messages, ["Model is required."])

        let emptyError = ProviderLastErrorPresentation(message: nil, preferredLanguages: ["zh-Hans-CN"])
        XCTAssertFalse(emptyError.isVisible)
        XCTAssertNil(emptyError.message)

        let error = ProviderLastErrorPresentation(message: "save failed", preferredLanguages: ["zh-Hans-CN"])
        XCTAssertTrue(error.isVisible)
        XCTAssertEqual(error.title, "最近错误")
        XCTAssertEqual(error.message, "save failed")

        XCTAssertEqual(
            ProviderValidationPresentation(errors: [], preferredLanguages: ["en-US"]).title,
            "Validation"
        )
        XCTAssertEqual(
            ProviderLastErrorPresentation(message: nil, preferredLanguages: ["en-US"]).title,
            "Last Error"
        )
    }
}
