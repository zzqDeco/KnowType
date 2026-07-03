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
        XCTAssertTrue(errors.contains("Base URL 必须是 HTTP 或 HTTPS URL。"))
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
            secretResolver: { _ in nil }
        )

        XCTAssertEqual(plan.profile.id, "work")
        XCTAssertEqual(plan.profile.secretName, "knowtype.provider.work.apiKey")
        XCTAssertEqual(plan.selectedProfileID, "work")
        XCTAssertEqual(plan.postSaveDraft.id, "work")
        XCTAssertEqual(plan.postSaveDraft.apiKey, "")
        XCTAssertEqual(plan.updatedProfiles.map(\.id), ["work"])
        XCTAssertEqual(plan.updatedFile.profiles.map(\.id), ["work"])
        XCTAssertEqual(
            plan.secretMutation,
            .set(value: "sk-work", secretName: "knowtype.provider.work.apiKey", oldSecretName: nil)
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

    func testApplySecretMutationDoesNotDeleteSharedOldSecret() throws {
        let store = RecordingPolicySecretStore()
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

        try ProviderProfileEditingPolicy.applySecretMutation(
            .set(value: "sk-new", secretName: "knowtype.provider.work.apiKey", oldSecretName: "legacy.shared"),
            updatedProfiles: updatedProfiles,
            secretStore: store
        )

        XCTAssertEqual(store.setSecretCalls.map(\.name), ["knowtype.provider.work.apiKey"])
        XCTAssertTrue(store.deleteSecretCalls.isEmpty)
    }

    func testApplySecretMutationCleansNewSecretWhenOldDeleteFails() {
        let store = RecordingPolicySecretStore(deleteErrors: ["legacy.old": TestPolicyError(message: "delete failed")])
        let updatedProfiles = [
            ProviderProfile(
                id: "work",
                displayName: "Work",
                kind: .openAIResponses,
                baseURL: URL(string: "https://api.openai.com")!,
                model: "gpt-4.1-mini",
                secretName: "knowtype.provider.work.apiKey"
            )
        ]

        XCTAssertThrowsError(
            try ProviderProfileEditingPolicy.applySecretMutation(
                .set(value: "sk-new", secretName: "knowtype.provider.work.apiKey", oldSecretName: "legacy.old"),
                updatedProfiles: updatedProfiles,
                secretStore: store
            )
        )

        XCTAssertEqual(store.setSecretCalls.map(\.name), ["knowtype.provider.work.apiKey"])
        XCTAssertEqual(store.deleteSecretCalls, ["legacy.old", "knowtype.provider.work.apiKey"])
    }
}

private final class RecordingPolicySecretStore: SecretStore, @unchecked Sendable {
    private var values: [String: String]
    private let deleteErrors: [String: Error]
    private(set) var setSecretCalls: [(value: String, name: String)] = []
    private(set) var deleteSecretCalls: [String] = []

    init(values: [String: String] = [:], deleteErrors: [String: Error] = [:]) {
        self.values = values
        self.deleteErrors = deleteErrors
    }

    func secret(named name: String) throws -> String? {
        values[name]
    }

    func setSecret(_ value: String, named name: String) throws {
        setSecretCalls.append((value: value, name: name))
        values[name] = value
    }

    func deleteSecret(named name: String) throws {
        deleteSecretCalls.append(name)
        if let error = deleteErrors[name] {
            throw error
        }
        values.removeValue(forKey: name)
    }
}

private struct TestPolicyError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
