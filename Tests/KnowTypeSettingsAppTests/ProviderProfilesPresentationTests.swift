import Foundation
import XCTest
@testable import KnowTypeProviders
@testable import KnowTypeSettingsApp

final class ProviderProfilesPresentationTests: XCTestCase {
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

        XCTAssertEqual(customPresentation.displayNameFieldLabel, "Display Name")
        XCTAssertEqual(customPresentation.kindPickerLabel, "Kind")
        XCTAssertEqual(customPresentation.baseURLFieldLabel, "Base URL")
        XCTAssertEqual(customPresentation.modelFieldLabel, "Model")
        XCTAssertEqual(customPresentation.timeoutLabel, "Timeout: 37 seconds")
        XCTAssertEqual(customPresentation.defaultProviderLabel, "Default provider")
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
        XCTAssertEqual(presentation.secret.apiKeyFieldPrompt, "Leave blank to keep existing key")
        XCTAssertEqual(
            presentation.secret.reference,
            SettingsKeyValuePresentation(
                label: "Secret reference",
                value: "knowtype.provider.work.apiKey"
            )
        )
        XCTAssertTrue(presentation.secret.helpText.contains("Keychain"))
        XCTAssertFalse(String(reflecting: presentation).contains("sk-typed-secret"))
    }

    func testConnectionStatusPresentationMapsProgressSuccessAndFailure() {
        let idle = ProviderConnectionStatusPresentation(status: .idle)
        XCTAssertEqual(idle.sectionTitle, "Connection")
        XCTAssertEqual(idle.testButtonLabel, "Test Connection")
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
        XCTAssertEqual(emptyValidation.title, "Validation")

        let validation = ProviderValidationPresentation(errors: ["Model is required."])
        XCTAssertTrue(validation.isVisible)
        XCTAssertEqual(validation.messages, ["Model is required."])

        let emptyError = ProviderLastErrorPresentation(message: nil)
        XCTAssertFalse(emptyError.isVisible)
        XCTAssertNil(emptyError.message)

        let error = ProviderLastErrorPresentation(message: "save failed")
        XCTAssertTrue(error.isVisible)
        XCTAssertEqual(error.title, "Last Error")
        XCTAssertEqual(error.message, "save failed")
    }
}
