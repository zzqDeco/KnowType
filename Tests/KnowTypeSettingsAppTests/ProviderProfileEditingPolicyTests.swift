import Foundation
import XCTest
@testable import KnowTypeProviders
@testable import KnowTypeSettingsUI

final class ProviderProfileEditingPolicyTests: XCTestCase {
    func testValidationRejectsInvalidDraftFields() {
        var draft = ProviderProfileDraft(profile: ProviderProfileTemplates.defaultProfile(kind: .anthropicMessages))
        draft.displayName = " "
        draft.baseURL = "not a url"
        draft.model = " "
        draft.timeoutSeconds = 0

        let errors = ProviderProfileEditingPolicy.validate(draft)

        XCTAssertTrue(errors.contains("显示名称不能为空。"))
        XCTAssertTrue(errors.contains("Base URL 必须是有效的 HTTP 或 HTTPS URL，且不能包含用户名、密码或 fragment。"))
        XCTAssertTrue(errors.contains("模型不能为空。"))
        XCTAssertTrue(errors.contains("超时时间必须大于 0。"))
    }

    func testValidationRejectsCustomHTTPMissingTemplateAndResponsePath() {
        var draft = ProviderProfileDraft(profile: ProviderProfileTemplates.defaultProfile(kind: .customHTTP))
        draft.customBodyTemplate = " "
        draft.customResponsePath = ""

        let errors = ProviderProfileEditingPolicy.validate(draft)

        XCTAssertTrue(errors.contains("Custom HTTP 请求体模板不能为空。"))
        XCTAssertTrue(errors.contains("Custom HTTP 响应路径不能为空。"))
    }

    func testValidationRejectsRemoteOpenAIPlaceholderModel() {
        var draft = ProviderProfileDraft(profile: ProviderProfileTemplates.defaultProfile(kind: .openAIResponses))
        draft.baseURL = "https://api.openai.com"
        draft.model = "<model>"

        let errors = ProviderProfileEditingPolicy.validate(draft)

        XCTAssertTrue(errors.contains("模型不能为空。"))
    }

    func testMakeSavePlanCreatesDefaultProfileAndScopedSetMutation() throws {
        var draft = ProviderProfileDraft(profile: ProviderProfileTemplates.defaultProfile(kind: .openAIResponses))
        draft.id = "work"
        draft.displayName = "Work OpenAI"
        draft.apiKey = " \n sk-work \t "
        draft.isDefault = true

        let plan = try ProviderProfileEditingPolicy.makeSavePlan(
            draft: draft,
            profiles: [],
            file: ProviderProfilesFile(),
            secretResolver: { _ in nil },
            credentialReferenceGenerator: { _ in
                "knowtype.provider.work.credential.00000000-0000-0000-0000-000000000001"
            }
        )

        XCTAssertEqual(plan.profile.id, "work")
        XCTAssertEqual(
            plan.profile.secretName,
            "knowtype.provider.work.credential.00000000-0000-0000-0000-000000000001"
        )
        XCTAssertEqual(plan.selectedProfileID, "work")
        XCTAssertEqual(plan.postSaveDraft.id, "work")
        XCTAssertEqual(plan.postSaveDraft.apiKey, "")
        XCTAssertEqual(plan.updatedProfiles.map(\.id), ["work"])
        XCTAssertEqual(plan.updatedFile.profiles.map(\.id), ["work"])
        XCTAssertEqual(
            plan.secretMutation,
            .set(
                value: "sk-work",
                secretName: "knowtype.provider.work.credential.00000000-0000-0000-0000-000000000001",
                oldSecretName: nil
            )
        )
    }

    func testMakeSavePlanKeepsSingleDefaultWhenUpdatingProfile() throws {
        let first = ProviderProfile(
            id: "first",
            displayName: "Local",
            kind: .openAIChat,
            baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
            model: "",
            isDefault: true
        )
        let second = ProviderProfile(
            id: "second",
            displayName: "Ollama",
            kind: .ollamaNative,
            baseURL: URL(string: "http://localhost:11434")!,
            model: "llama3.2"
        )
        var draft = ProviderProfileDraft(profile: second)
        draft.isDefault = true

        let plan = try ProviderProfileEditingPolicy.makeSavePlan(
            draft: draft,
            profiles: [first, second],
            file: ProviderProfilesFile(profiles: [first, second]),
            secretResolver: { _ in nil }
        )

        XCTAssertEqual(plan.updatedProfiles.filter(\.isDefault).map(\.id), ["second"])
        XCTAssertEqual(plan.secretMutation, .none)
    }

    func testSaveValidationRejectsRemovingOnlyDefault() {
        let profile = ProviderProfile(
            id: "only",
            displayName: "Only",
            kind: .ollamaNative,
            baseURL: URL(string: "http://localhost:11434")!,
            model: "llama3.2",
            isDefault: true
        )
        var draft = ProviderProfileDraft(profile: profile)
        draft.isDefault = false

        let errors = ProviderProfileEditingPolicy.saveValidationErrors(draft: draft, profiles: [profile])

        XCTAssertTrue(errors.contains(ProviderProfileEditingPolicy.defaultProviderValidationError))
    }

    func testBlankLocalOpenAIKeepsReusableExistingLocalSecret() throws {
        let existing = ProviderProfile(
            id: "local-openai",
            displayName: "Local",
            kind: .openAIChat,
            baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
            model: "",
            secretName: "knowtype.provider.local-openai.apiKey",
            isDefault: true
        )
        var draft = ProviderProfileDraft(profile: existing)
        draft.apiKey = " "

        let plan = try ProviderProfileEditingPolicy.makeSavePlan(
            draft: draft,
            profiles: [existing],
            file: ProviderProfilesFile(profiles: [existing]),
            secretResolver: { name in
                name == "knowtype.provider.local-openai.apiKey" ? "sk-local" : nil
            }
        )

        XCTAssertEqual(plan.profile.secretName, "knowtype.provider.local-openai.apiKey")
        XCTAssertEqual(plan.secretMutation, .none)
    }

    func testBlankRemoteToLocalOpenAIClearsRemoteSecret() throws {
        let existing = ProviderProfile(
            id: "work",
            displayName: "Remote",
            kind: .openAIChat,
            baseURL: URL(string: "https://api.openai.com")!,
            model: "gpt-4.1-mini",
            secretName: "knowtype.provider.work.apiKey",
            isDefault: true
        )
        var draft = ProviderProfileDraft(profile: existing)
        draft.baseURL = "http://127.0.0.1:8317/v1"
        draft.model = ""
        draft.apiKey = ""

        let plan = try ProviderProfileEditingPolicy.makeSavePlan(
            draft: draft,
            profiles: [existing],
            file: ProviderProfilesFile(profiles: [existing]),
            secretResolver: { _ in "sk-remote" }
        )

        XCTAssertNil(plan.profile.secretName)
        XCTAssertEqual(plan.secretMutation, .delete(secretName: "knowtype.provider.work.apiKey"))
    }

    func testKindOrEndpointChangeDoesNotReuseRequiredSecret() {
        let existing = ProviderProfile(
            id: "work",
            displayName: "Work",
            kind: .openAIResponses,
            baseURL: URL(string: "https://api.openai.com")!,
            model: "gpt-4.1-mini",
            secretName: "knowtype.provider.work.apiKey",
            isDefault: true
        )
        var draft = ProviderProfileDraft(profile: existing)
        draft.baseURL = "https://openrouter.ai/api/v1"
        draft.apiKey = ""

        XCTAssertThrowsError(
            try ProviderProfileEditingPolicy.makeSavePlan(
                draft: draft,
                profiles: [existing],
                file: ProviderProfilesFile(profiles: [existing]),
                secretResolver: { _ in "sk-existing" }
            )
        ) { error in
            XCTAssertEqual(error as? ProviderProfilesViewModelError, .missingAPIKey)
        }
    }

    func testSavePlanRejectsReusedCredentialReference() {
        let reference = "knowtype.provider.work.credential.00000000-0000-0000-0000-000000000001"
        let existing = ProviderProfile(
            id: "work",
            displayName: "Work",
            kind: .openAIResponses,
            baseURL: URL(string: "https://api.openai.com")!,
            model: "gpt-test",
            secretName: reference,
            isDefault: true
        )
        var draft = ProviderProfileDraft(profile: existing)
        draft.apiKey = "K2"

        XCTAssertThrowsError(
            try ProviderProfileEditingPolicy.makeSavePlan(
                draft: draft,
                profiles: [existing],
                file: ProviderProfilesFile(profiles: [existing]),
                secretResolver: { _ in "K1" },
                credentialReferenceGenerator: { _ in reference }
            )
        ) { error in
            XCTAssertEqual(error as? ProviderProfilesViewModelError, .invalidCredentialReference)
        }
    }

    func testConnectionConfigurationUsesTransientDraftAPIKey() throws {
        var draft = ProviderProfileDraft(profile: ProviderProfileTemplates.defaultProfile(kind: .openAIResponses))
        draft.apiKey = " \n sk-transient \t "

        let configuration = try ProviderProfileEditingPolicy.makeConnectionConfiguration(
            draft: draft,
            profiles: [],
            secretResolver: { _ in nil }
        )

        XCTAssertEqual(configuration.apiKey, "sk-transient")
        XCTAssertEqual(configuration.kind, .openAIResponses)
        XCTAssertEqual(configuration.baseURL.absoluteString, "https://api.openai.com")
    }

    func testConnectionConfigurationReusesExistingSecretOnlyForSameScope() throws {
        let existing = ProviderProfile(
            id: "work",
            displayName: "Work",
            kind: .openAIResponses,
            baseURL: URL(string: "https://api.openai.com")!,
            model: "gpt-4.1-mini",
            secretName: "knowtype.provider.work.apiKey",
            isDefault: true
        )
        var draft = ProviderProfileDraft(profile: existing)
        draft.apiKey = ""

        let configuration = try ProviderProfileEditingPolicy.makeConnectionConfiguration(
            draft: draft,
            profiles: [existing],
            secretResolver: { name in
                name == "knowtype.provider.work.apiKey" ? "sk-existing" : nil
            }
        )

        XCTAssertEqual(configuration.apiKey, "sk-existing")

        draft.baseURL = "https://openrouter.ai/api/v1"
        XCTAssertThrowsError(
            try ProviderProfileEditingPolicy.makeConnectionConfiguration(
                draft: draft,
                profiles: [existing],
                secretResolver: { _ in "sk-existing" }
            )
        ) { error in
            XCTAssertEqual(error as? ProviderProfilesViewModelError, .missingAPIKey)
        }
    }

    func testSharedOldSecretRemainsReferencedByAnotherProfile() {
        let updatedProfiles = [
            ProviderProfile(
                id: "work",
                displayName: "Work",
                kind: .openAIResponses,
                baseURL: URL(string: "https://api.openai.com")!,
                model: "gpt-4.1-mini",
                secretName: "knowtype.provider.work.apiKey"
            ),
            ProviderProfile(
                id: "shared",
                displayName: "Shared",
                kind: .anthropicMessages,
                baseURL: URL(string: "https://api.anthropic.com")!,
                model: "claude-3-5-haiku-latest",
                secretName: "legacy.shared"
            )
        ]

        XCTAssertTrue(ProviderProfileEditingPolicy.isSecretReferenced("legacy.shared", in: updatedProfiles))
    }

    func testValidationRejectsUserInfoAndFragmentButAllowsQuery() {
        var draft = ProviderProfileDraft(profile: ProviderProfileTemplates.defaultProfile(kind: .openAIResponses))
        draft.model = "gpt-test"

        draft.baseURL = "https://user:pass@example.com/v1"
        XCTAssertFalse(ProviderProfileEditingPolicy.validate(draft).isEmpty)

        draft.baseURL = "https://example.com/v1#debug"
        XCTAssertFalse(ProviderProfileEditingPolicy.validate(draft).isEmpty)

        draft.baseURL = "https://example.com/v1?runtime=compatible"
        XCTAssertTrue(ProviderProfileEditingPolicy.validate(draft).isEmpty)
    }
}
