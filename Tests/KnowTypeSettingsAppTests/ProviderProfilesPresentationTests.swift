import Foundation
import XCTest
@testable import KnowTypeProviders
@testable import KnowTypeSettingsUI

final class ProviderProfilesPresentationTests: XCTestCase {
    func testSettingsSidebarUsesChineseNativeSectionsAndSearch() {
        let allSections = SettingsSidebarPresentation(searchText: "")

        XCTAssertEqual(
            allSections.sections.map(\.title),
            ["输入", "候选窗", "Rime 与用户数据", "AI 续写", "隐私", "诊断"]
        )
        XCTAssertEqual(SettingsSection.input.systemImage, "keyboard")
        XCTAssertEqual(SettingsSection.aiProvider.systemImage, "sparkles")

        let aiSearch = SettingsSidebarPresentation(searchText: "模型")
        XCTAssertEqual(aiSearch.sections, [.aiProvider])

        let lexiconSearch = SettingsSidebarPresentation(searchText: "Rime")
        XCTAssertEqual(lexiconSearch.sections, [.lexicons])

        let emptySearch = SettingsSidebarPresentation(searchText: "不存在")
        XCTAssertTrue(emptySearch.sections.isEmpty)
    }

    func testSettingsLocalizationLoadsChineseStringsAndEnglishFallback() {
        XCTAssertEqual(SettingsLocalization.string("settings.window.title"), "KnowType 设置")
        XCTAssertEqual(SettingsLocalization.string("settings.section.ai"), "AI 续写")
        XCTAssertEqual(
            SettingsLocalization.string("settings.section.ai", localeIdentifier: "en"),
            "AI Continuation"
        )
        XCTAssertEqual(SettingsLocalization.string("settings.action.testConnection"), "测试连接")
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

        let customPresentation = ProviderProfileDraftPresentation(draft: customDraft)

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

        XCTAssertFalse(ProviderProfileDraftPresentation(draft: chatDraft).showsCustomHTTPFields)
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

        let presentation = ProviderProfileDraftPresentation(draft: draft)

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
    }

    func testConnectionStatusPresentationMapsProgressSuccessAndFailure() {
        let idle = ProviderConnectionStatusPresentation(status: .idle)
        XCTAssertEqual(idle.sectionTitle, "连接")
        XCTAssertEqual(idle.testButtonLabel, "测试连接")
        XCTAssertFalse(idle.showsProgress)
        XCTAssertFalse(idle.isTesting)
        XCTAssertNil(idle.message)

        let testing = ProviderConnectionStatusPresentation(status: .testing)
        XCTAssertTrue(testing.showsProgress)
        XCTAssertTrue(testing.isTesting)
        XCTAssertNil(testing.message)

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
        let emptyValidation = ProviderValidationPresentation(errors: [])
        XCTAssertFalse(emptyValidation.isVisible)
        XCTAssertEqual(emptyValidation.title, "校验")

        let validation = ProviderValidationPresentation(errors: ["Model is required."])
        XCTAssertTrue(validation.isVisible)
        XCTAssertEqual(validation.messages, ["Model is required."])

        let emptyError = ProviderLastErrorPresentation(message: nil)
        XCTAssertFalse(emptyError.isVisible)
        XCTAssertNil(emptyError.message)

        let error = ProviderLastErrorPresentation(message: "save failed")
        XCTAssertTrue(error.isVisible)
        XCTAssertEqual(error.title, "最近错误")
        XCTAssertEqual(error.message, "save failed")
    }
}
