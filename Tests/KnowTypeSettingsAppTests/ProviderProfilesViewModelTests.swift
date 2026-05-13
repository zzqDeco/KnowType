import Foundation
import XCTest
@testable import KnowTypeProviders
@testable import KnowTypeSettingsApp

@MainActor
final class ProviderProfilesViewModelTests: XCTestCase {
    func testLoadsProviderDefaultsWhenStoreIsEmpty() throws {
        let store = CapturingProfileStore(file: ProviderProfilesFile())
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: InMemorySecretStore()
        )

        XCTAssertEqual(viewModel.profiles.map(\.kind), ProviderKind.allCases)
        XCTAssertEqual(viewModel.profiles.filter(\.isDefault).map(\.kind), [.openAIChat])
        XCTAssertEqual(viewModel.profiles.first(where: { $0.kind == .ollamaNative })?.baseURL.absoluteString, "http://localhost:11434")
        XCTAssertEqual(viewModel.profiles.first(where: { $0.kind == .customHTTP })?.customResponsePath, "candidates")
    }

    func testSeededProviderDefaultsUseProfileScopedSecretNames() {
        let viewModel = ProviderProfilesViewModel(
            profileStore: CapturingProfileStore(file: ProviderProfilesFile()),
            secretStore: InMemorySecretStore()
        )

        for profile in viewModel.profiles where profile.secretName != nil {
            XCTAssertEqual(profile.secretName, "knowtype.provider.\(profile.id).apiKey")
        }
        XCTAssertFalse(viewModel.profiles.contains { $0.secretName == "knowtype.openai_chat.apiKey" })
        XCTAssertFalse(viewModel.profiles.contains { $0.secretName == "knowtype.custom_http.apiKey" })
    }

    func testValidationRejectsMissingRequiredFields() {
        let viewModel = ProviderProfilesViewModel(
            profileStore: CapturingProfileStore(file: ProviderProfilesFile()),
            secretStore: InMemorySecretStore()
        )

        viewModel.draft.displayName = " "
        viewModel.draft.baseURL = "not a url"
        viewModel.draft.model = " "
        viewModel.draft.timeoutSeconds = 0

        let errors = viewModel.validate(viewModel.draft)

        XCTAssertTrue(errors.contains("Display name is required."))
        XCTAssertTrue(errors.contains("Base URL must be an HTTP or HTTPS URL."))
        XCTAssertTrue(errors.contains("Model is required."))
        XCTAssertTrue(errors.contains("Timeout must be greater than zero."))
    }

    func testValidationRejectsBaseURLWithoutHost() {
        let viewModel = ProviderProfilesViewModel(
            profileStore: CapturingProfileStore(file: ProviderProfilesFile()),
            secretStore: InMemorySecretStore()
        )

        viewModel.draft.baseURL = "https:"

        let errors = viewModel.validate(viewModel.draft)

        XCTAssertTrue(errors.contains("Base URL must be an HTTP or HTTPS URL."))
    }

    func testSaveCreatesProfileAndWritesAPIKeyToSecretStoreOnly() throws {
        let store = CapturingProfileStore(file: ProviderProfilesFile())
        let secrets = InMemorySecretStore()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false
        )

        viewModel.createProfile(kind: .openAIResponses)
        viewModel.draft.displayName = "Work OpenAI"
        viewModel.draft.baseURL = "https://api.openai.com"
        viewModel.draft.model = "gpt-4.1"
        viewModel.draft.apiKey = "sk-secret"
        viewModel.draft.isDefault = true

        XCTAssertTrue(viewModel.saveDraft())

        let savedProfile = try XCTUnwrap(store.savedFiles.last?.profiles.first)
        XCTAssertEqual(savedProfile.displayName, "Work OpenAI")
        XCTAssertEqual(savedProfile.kind, .openAIResponses)
        XCTAssertEqual(savedProfile.secretName, "knowtype.provider.\(savedProfile.id).apiKey")
        XCTAssertEqual(try secrets.secret(named: savedProfile.secretName ?? ""), "sk-secret")

        let savedJSON = String(data: try JSONEncoder().encode(store.savedFiles.last), encoding: .utf8)
        XCTAssertFalse(savedJSON?.contains("sk-secret") ?? true)
    }

    func testNewProfilesUseProfileScopedSecretNames() throws {
        let store = CapturingProfileStore(file: ProviderProfilesFile())
        let secrets = InMemorySecretStore()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false
        )

        viewModel.createProfile(kind: .openAIChat)
        let firstID = viewModel.draft.id
        viewModel.draft.displayName = "Work OpenAI"
        viewModel.draft.apiKey = "sk-work"
        viewModel.draft.isDefault = true
        XCTAssertTrue(viewModel.saveDraft())

        viewModel.createProfile(kind: .openAIChat)
        let secondID = viewModel.draft.id
        viewModel.draft.displayName = "Personal OpenAI"
        viewModel.draft.apiKey = "sk-personal"
        viewModel.draft.isDefault = true
        XCTAssertTrue(viewModel.saveDraft())

        let saved = try XCTUnwrap(store.savedFiles.last?.profiles)
        let first = try XCTUnwrap(saved.first(where: { $0.id == firstID }))
        let second = try XCTUnwrap(saved.first(where: { $0.id == secondID }))

        XCTAssertNotEqual(first.secretName, second.secretName)
        XCTAssertEqual(first.secretName, "knowtype.provider.\(firstID).apiKey")
        XCTAssertEqual(second.secretName, "knowtype.provider.\(secondID).apiKey")
        XCTAssertEqual(try secrets.secret(named: first.secretName ?? ""), "sk-work")
        XCTAssertEqual(try secrets.secret(named: second.secretName ?? ""), "sk-personal")
    }

    func testSaveUpdatesExistingProfileAndKeepsSingleDefault() throws {
        let existing = [
            ProviderProfileTemplates.defaultProfile(kind: .openAIChat, isDefault: true),
            ProviderProfileTemplates.defaultProfile(kind: .anthropicMessages)
        ]
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: existing))
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: InMemorySecretStore()
        )

        let anthropicID = try XCTUnwrap(existing.first(where: { $0.kind == .anthropicMessages })?.id)
        viewModel.selectProfile(id: anthropicID)
        viewModel.draft.displayName = "Claude Fast"
        viewModel.draft.isDefault = true

        XCTAssertTrue(viewModel.saveDraft())

        let saved = try XCTUnwrap(store.savedFiles.last?.profiles)
        XCTAssertEqual(saved.first(where: { $0.id == anthropicID })?.displayName, "Claude Fast")
        XCTAssertEqual(saved.filter(\.isDefault).map(\.id), [anthropicID])
    }

    func testChangingKindAppliesProviderTemplateDefaults() throws {
        let existing = [
            ProviderProfile(
                id: "work",
                displayName: "Work",
                kind: .openAIChat,
                baseURL: URL(string: "https://openrouter.ai/api/v1")!,
                model: "openai/custom",
                headers: ["anthropic-version": "stale"],
                secretName: "knowtype.openai_chat.apiKey",
                customBodyTemplate: #"{"stale":true}"#,
                customResponsePath: "stale",
                isDefault: true
            )
        ]
        let viewModel = ProviderProfilesViewModel(
            profileStore: CapturingProfileStore(file: ProviderProfilesFile(profiles: existing)),
            secretStore: InMemorySecretStore()
        )

        viewModel.changeDraftKind(.geminiNative)

        XCTAssertEqual(viewModel.draft.kind, .geminiNative)
        XCTAssertEqual(viewModel.draft.baseURL, "https://generativelanguage.googleapis.com")
        XCTAssertEqual(viewModel.draft.model, "gemini-1.5-flash")
        XCTAssertTrue(viewModel.draft.headers.isEmpty)
        XCTAssertEqual(viewModel.draft.secretName, "knowtype.provider.work.apiKey")
        XCTAssertEqual(viewModel.draft.customBodyTemplate, "")
        XCTAssertEqual(viewModel.draft.customResponsePath, "")
    }

    func testChangingKindToProviderWithoutSecretClearsAPIKey() throws {
        let existing = [
            ProviderProfile(
                id: "work",
                displayName: "Work",
                kind: .openAIChat,
                baseURL: URL(string: "https://api.openai.com")!,
                model: "gpt-4.1-mini",
                secretName: "knowtype.provider.work.apiKey",
                isDefault: true
            )
        ]
        let viewModel = ProviderProfilesViewModel(
            profileStore: CapturingProfileStore(file: ProviderProfilesFile(profiles: existing)),
            secretStore: InMemorySecretStore()
        )
        viewModel.draft.apiKey = "sk-typed"

        viewModel.changeDraftKind(.ollamaNative)

        XCTAssertEqual(viewModel.draft.kind, .ollamaNative)
        XCTAssertNil(viewModel.draft.secretName)
        XCTAssertEqual(viewModel.draft.apiKey, "")
    }

    func testSavingProviderWithoutSecretDoesNotWriteStaleSecret() throws {
        let existing = [
            ProviderProfile(
                id: "work",
                displayName: "Work",
                kind: .openAIChat,
                baseURL: URL(string: "https://api.openai.com")!,
                model: "gpt-4.1-mini",
                secretName: "knowtype.provider.work.apiKey",
                isDefault: true
            )
        ]
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: existing))
        let secrets = RecordingSecretStore()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets
        )

        viewModel.changeDraftKind(.ollamaNative)
        viewModel.draft.apiKey = "sk-stale"

        XCTAssertTrue(viewModel.saveDraft())

        let saved = try XCTUnwrap(store.savedFiles.last?.profiles.first)
        XCTAssertEqual(saved.kind, .ollamaNative)
        XCTAssertNil(saved.secretName)
        XCTAssertTrue(secrets.setSecretCalls.isEmpty)
    }

    func testLoadFailureBlocksPersistenceUntilProfilesLoadSuccessfully() throws {
        let store = ThrowingProfileStore(error: TestProfileStoreError(message: "malformed profiles"))
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: InMemorySecretStore(),
            loadDefaultsWhenEmpty: false
        )

        XCTAssertTrue(viewModel.isPersistenceBlocked)
        XCTAssertEqual(viewModel.lastErrorMessage, "malformed profiles")

        viewModel.createProfile(kind: .openAIChat)
        viewModel.draft.displayName = "Work OpenAI"
        viewModel.draft.apiKey = "sk-secret"
        viewModel.draft.isDefault = true

        XCTAssertFalse(viewModel.saveDraft())
        XCTAssertTrue(store.savedFiles.isEmpty)
        XCTAssertThrowsError(try viewModel.setDefaultProfile(id: viewModel.draft.id))
        XCTAssertTrue(store.savedFiles.isEmpty)
        XCTAssertEqual(viewModel.lastErrorMessage, "malformed profiles")
    }

    func testSaveRejectsRemovingOnlyDefaultProfile() throws {
        let existing = [
            ProviderProfileTemplates.defaultProfile(kind: .openAIChat, isDefault: true),
            ProviderProfileTemplates.defaultProfile(kind: .anthropicMessages)
        ]
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: existing))
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: InMemorySecretStore()
        )

        viewModel.draft.isDefault = false

        XCTAssertFalse(viewModel.saveDraft())
        XCTAssertTrue(viewModel.validationErrors.contains("At least one default provider is required."))
        XCTAssertTrue(store.savedFiles.isEmpty)
    }

    func testCustomHTTPRequiresTemplateAndResponsePath() {
        let viewModel = ProviderProfilesViewModel(
            profileStore: CapturingProfileStore(file: ProviderProfilesFile()),
            secretStore: InMemorySecretStore()
        )

        viewModel.createProfile(kind: .customHTTP)
        viewModel.draft.customBodyTemplate = ""
        viewModel.draft.customResponsePath = " "

        let errors = viewModel.validate(viewModel.draft)

        XCTAssertTrue(errors.contains("Custom HTTP body template is required."))
        XCTAssertTrue(errors.contains("Custom HTTP response path is required."))
    }

    func testSetDefaultPersistsDefaultProviderChoice() throws {
        let profiles = ProviderProfileTemplates.defaultProfiles()
        let targetID = try XCTUnwrap(profiles.first(where: { $0.kind == .ollamaNative })?.id)
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: profiles))
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: InMemorySecretStore()
        )

        try viewModel.setDefaultProfile(id: targetID)

        let saved = try XCTUnwrap(store.savedFiles.last?.profiles)
        XCTAssertEqual(saved.filter(\.isDefault).map(\.id), [targetID])
    }
}

private final class CapturingProfileStore: ProviderProfileStore, @unchecked Sendable {
    private let file: ProviderProfilesFile
    private(set) var savedFiles: [ProviderProfilesFile] = []

    init(file: ProviderProfilesFile) {
        self.file = file
    }

    func loadProfiles() throws -> ProviderProfilesFile {
        file
    }

    func saveProfiles(_ profiles: ProviderProfilesFile) throws {
        savedFiles.append(profiles)
    }
}

private final class ThrowingProfileStore: ProviderProfileStore, @unchecked Sendable {
    private let error: Error
    private(set) var savedFiles: [ProviderProfilesFile] = []

    init(error: Error) {
        self.error = error
    }

    func loadProfiles() throws -> ProviderProfilesFile {
        throw error
    }

    func saveProfiles(_ profiles: ProviderProfilesFile) throws {
        savedFiles.append(profiles)
    }
}

private final class RecordingSecretStore: SecretStore, @unchecked Sendable {
    private(set) var setSecretCalls: [(value: String, name: String)] = []

    func secret(named name: String) throws -> String? {
        nil
    }

    func setSecret(_ value: String, named name: String) throws {
        setSecretCalls.append((value: value, name: name))
    }

    func deleteSecret(named name: String) throws {}
}

private struct TestProfileStoreError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
