import Foundation
import XCTest
@testable import KnowTypeProviders
@testable import KnowTypeSettingsUI

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
        XCTAssertEqual(viewModel.profiles.first(where: { $0.kind == .openAIChat })?.displayName, "Local OpenAI Compatible")
        XCTAssertEqual(viewModel.profiles.first(where: { $0.kind == .openAIChat })?.baseURL.absoluteString, "http://127.0.0.1:8317/v1")
        XCTAssertEqual(viewModel.profiles.first(where: { $0.kind == .openAIChat })?.model, "")
        XCTAssertNil(viewModel.profiles.first(where: { $0.kind == .openAIChat })?.secretName)
        XCTAssertEqual(viewModel.profiles.first(where: { $0.kind == .ollamaNative })?.baseURL.absoluteString, "http://localhost:11434")
        XCTAssertEqual(viewModel.profiles.first(where: { $0.kind == .customHTTP })?.customResponsePath, "candidates")
    }

    func testLoadMigratesRetiredOfficialModelAtCurrentRevision() throws {
        let store = CapturingProfileStore(file: ProviderProfilesFile(
            revision: 5,
            profiles: [
                ProviderProfile(
                    displayName: "Gemini",
                    kind: .geminiNative,
                    baseURL: URL(string: "https://generativelanguage.googleapis.com")!,
                    model: "gemini-1.5-flash",
                    isDefault: true
                )
            ]
        ))

        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: InMemorySecretStore(),
            loadDefaultsWhenEmpty: false
        )

        XCTAssertEqual(viewModel.profiles.first?.model, "gemini-3.5-flash")
        XCTAssertEqual(store.savedFiles.last?.revision, 6)
        XCTAssertEqual(store.savedFiles.count, 1)
    }

    func testSeededProviderDefaultsUseProfileScopedSecretNames() {
        let viewModel = ProviderProfilesViewModel(
            profileStore: CapturingProfileStore(file: ProviderProfilesFile()),
            secretStore: InMemorySecretStore()
        )

        for profile in viewModel.profiles where profile.secretName != nil {
            XCTAssertEqual(profile.secretName, "knowtype.provider.\(profile.id).apiKey")
        }
        XCTAssertNil(viewModel.profiles.first(where: { $0.kind == .customHTTP })?.secretName)
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
        viewModel.draft.kind = .anthropicMessages
        viewModel.draft.model = " "
        viewModel.draft.timeoutSeconds = 0

        let errors = viewModel.validate(viewModel.draft)

        XCTAssertTrue(errors.contains("显示名称不能为空。"))
        XCTAssertTrue(errors.contains("Base URL 必须是有效的 HTTP 或 HTTPS URL，且不能包含用户名、密码或 fragment。"))
        XCTAssertTrue(errors.contains("模型不能为空。"))
        XCTAssertTrue(errors.contains("超时时间必须大于 0。"))
    }

    func testValidationRejectsBaseURLWithoutHost() {
        let viewModel = ProviderProfilesViewModel(
            profileStore: CapturingProfileStore(file: ProviderProfilesFile()),
            secretStore: InMemorySecretStore()
        )

        viewModel.draft.baseURL = "https:"

        let errors = viewModel.validate(viewModel.draft)

        XCTAssertTrue(errors.contains("Base URL 必须是有效的 HTTP 或 HTTPS URL，且不能包含用户名、密码或 fragment。"))
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
        XCTAssertTrue(
            savedProfile.secretName?.hasPrefix("knowtype.provider.\(savedProfile.id).credential.") == true
        )
        XCTAssertEqual(try secrets.secret(named: savedProfile.secretName ?? ""), "sk-secret")

        let savedJSON = String(data: try JSONEncoder().encode(store.savedFiles.last), encoding: .utf8)
        XCTAssertFalse(savedJSON?.contains("sk-secret") ?? true)
    }

    func testSaveStoresTrimmedAPIKey() throws {
        let store = CapturingProfileStore(file: ProviderProfilesFile())
        let secrets = RecordingSecretStore()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false
        )

        viewModel.createProfile(kind: .openAIResponses)
        viewModel.draft.displayName = "Work OpenAI"
        viewModel.draft.baseURL = "https://api.openai.com"
        viewModel.draft.model = "gpt-4.1"
        viewModel.draft.apiKey = " \n sk-trimmed \t "
        viewModel.draft.isDefault = true

        XCTAssertTrue(viewModel.saveDraft())

        XCTAssertEqual(secrets.setSecretCalls.count, 1)
        XCTAssertEqual(secrets.setSecretCalls.first?.value, "sk-trimmed")
        XCTAssertEqual(try secrets.secret(named: secrets.setSecretCalls.first?.name ?? ""), "sk-trimmed")
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
        XCTAssertTrue(first.secretName?.hasPrefix("knowtype.provider.\(firstID).credential.") == true)
        XCTAssertTrue(second.secretName?.hasPrefix("knowtype.provider.\(secondID).credential.") == true)
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
            secretStore: InMemorySecretStore(values: ["knowtype.anthropic_messages.apiKey": "sk-existing"])
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
        XCTAssertEqual(viewModel.draft.model, "gemini-3.5-flash")
        XCTAssertTrue(viewModel.draft.headers.isEmpty)
        XCTAssertEqual(viewModel.draft.secretName, "knowtype.openai_chat.apiKey")
        XCTAssertEqual(viewModel.draft.customBodyTemplate, "")
        XCTAssertEqual(viewModel.draft.customResponsePath, "")
    }

    func testChangingCloudKindWithBlankAPIKeyRequiresNewSecret() throws {
        let existing = [
            ProviderProfile(
                id: "work",
                displayName: "Work",
                kind: .openAIChat,
                baseURL: URL(string: "https://api.openai.com")!,
                model: "gpt-4.1-mini",
                secretName: "knowtype.openai_chat.apiKey",
                isDefault: true
            )
        ]
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: existing))
        let secrets = RecordingSecretStore(values: ["knowtype.openai_chat.apiKey": "sk-existing"])
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets
        )

        viewModel.changeDraftKind(.anthropicMessages)

        XCTAssertFalse(viewModel.saveDraft())
        XCTAssertEqual(viewModel.lastErrorMessage, "此 provider 需要 API Key。")
        XCTAssertTrue(store.savedFiles.isEmpty)
        XCTAssertTrue(secrets.setSecretCalls.isEmpty)
        XCTAssertTrue(secrets.deleteSecretCalls.isEmpty)
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

    func testSavingProviderWithoutSecretDeletesPreviousSecret() throws {
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

        XCTAssertTrue(viewModel.saveDraft())

        XCTAssertEqual(secrets.deleteSecretCalls, ["knowtype.provider.work.apiKey"])
        XCTAssertNil(store.savedFiles.last?.profiles.first?.secretName)
    }

    func testSavingProviderWithoutSecretDoesNotDeleteSharedLegacySecret() throws {
        let existing = [
            ProviderProfile(
                id: "work",
                displayName: "Work",
                kind: .openAIChat,
                baseURL: URL(string: "https://api.openai.com")!,
                model: "gpt-4.1-mini",
                secretName: "knowtype.openai_chat.apiKey",
                isDefault: true
            ),
            ProviderProfile(
                id: "personal",
                displayName: "Personal",
                kind: .openAIChat,
                baseURL: URL(string: "https://api.openai.com")!,
                model: "gpt-4.1-mini",
                secretName: "knowtype.openai_chat.apiKey",
                isDefault: false
            )
        ]
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: existing))
        let secrets = RecordingSecretStore(values: ["knowtype.openai_chat.apiKey": "sk-shared"])
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets
        )

        viewModel.changeDraftKind(.ollamaNative)

        XCTAssertTrue(viewModel.saveDraft())

        XCTAssertTrue(secrets.deleteSecretCalls.isEmpty)
        let saved = try XCTUnwrap(store.savedFiles.last?.profiles)
        XCTAssertNil(saved.first(where: { $0.id == "work" })?.secretName)
        XCTAssertEqual(saved.first(where: { $0.id == "personal" })?.secretName, "knowtype.openai_chat.apiKey")
    }

    func testDeleteSecretFailureAfterProviderWithoutSecretSaveKeepsCommittedMetadata() throws {
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
        let secrets = RecordingSecretStore(deleteError: TestProfileStoreError(message: "delete failed"))
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets
        )

        viewModel.changeDraftKind(.ollamaNative)

        XCTAssertTrue(viewModel.saveDraft())
        XCTAssertEqual(
            viewModel.lastErrorMessage,
            "Provider 配置已保存，但无法清理旧的未引用凭据：delete failed。"
        )
        XCTAssertEqual(store.savedFiles.count, 1)
        XCTAssertNil(store.savedFiles.last?.profiles.first?.secretName)
        XCTAssertEqual(secrets.deleteSecretCalls, ["knowtype.provider.work.apiKey"])
        XCTAssertEqual(viewModel.profiles, store.savedFiles.last?.profiles)
    }

    func testSetSecretFailureDoesNotWriteProfileFile() throws {
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
        let secrets = RecordingSecretStore(setError: TestProfileStoreError(message: "set failed"))
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets
        )

        viewModel.draft.displayName = "Updated Work"
        viewModel.draft.apiKey = "sk-new"

        XCTAssertFalse(viewModel.saveDraft())
        XCTAssertEqual(viewModel.lastErrorMessage, "set failed")
        XCTAssertTrue(store.savedFiles.isEmpty)
        XCTAssertEqual(viewModel.profiles, existing)
    }

    func testSetSecretFailureFromSeededDefaultsDoesNotWriteProfileFile() throws {
        let loaded = ProviderProfilesFile()
        let store = CapturingProfileStore(file: loaded)
        let secrets = RecordingSecretStore(setError: TestProfileStoreError(message: "set failed"))
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets
        )

        viewModel.draft.apiKey = "sk-new"

        XCTAssertFalse(viewModel.saveDraft())
        XCTAssertEqual(viewModel.lastErrorMessage, "set failed")
        XCTAssertTrue(store.savedFiles.isEmpty)
        XCTAssertEqual(viewModel.profiles.map(\.kind), ProviderKind.allCases)
    }

    func testFailedLegacySecretDeleteKeepsCommittedImmutableCredential() throws {
        let oldSecretName = "knowtype.openai_chat.apiKey"
        let newSecretName = "knowtype.provider.work.credential.00000000-0000-0000-0000-000000000001"
        let existing = [
            ProviderProfile(
                id: "work",
                displayName: "Work",
                kind: .openAIChat,
                baseURL: URL(string: "https://api.openai.com")!,
                model: "gpt-4.1-mini",
                secretName: oldSecretName,
                isDefault: true
            )
        ]
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: existing))
        let secrets = RecordingSecretStore(
            values: [oldSecretName: "sk-old"],
            deleteErrors: [oldSecretName: TestProfileStoreError(message: "delete failed")]
        )
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets,
            credentialReferenceGenerator: { _ in newSecretName }
        )

        viewModel.draft.apiKey = "sk-new"

        XCTAssertTrue(viewModel.saveDraft())
        XCTAssertEqual(
            viewModel.lastErrorMessage,
            "Provider 配置已保存，但无法清理旧的未引用凭据：delete failed。"
        )
        XCTAssertEqual(store.savedFiles.count, 1)
        XCTAssertEqual(store.savedFiles.last?.profiles.first?.secretName, newSecretName)
        XCTAssertEqual(secrets.setSecretCalls.map(\.name), [newSecretName])
        XCTAssertEqual(secrets.deleteSecretCalls, [oldSecretName])
        XCTAssertEqual(try secrets.secret(named: newSecretName), "sk-new")
        XCTAssertEqual(viewModel.profiles, store.savedFiles.last?.profiles)
    }

    func testMetadataFailureCompensatesNewCredentialWithoutChangingExistingMetadata() throws {
        let oldSecretName = "knowtype.provider.work.apiKey"
        let newSecretName = "knowtype.provider.work.credential.00000000-0000-0000-0000-000000000001"
        let existing = [
            ProviderProfile(
                id: "work",
                displayName: "Work",
                kind: .openAIChat,
                baseURL: URL(string: "https://api.openai.com")!,
                model: "gpt-4.1-mini",
                secretName: oldSecretName,
                isDefault: true
            )
        ]
        let store = SavingThrowingProfileStore(
            file: ProviderProfilesFile(profiles: existing),
            error: TestProfileStoreError(message: "save failed")
        )
        let secrets = RecordingSecretStore(values: [oldSecretName: "sk-old"])
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets,
            credentialReferenceGenerator: { _ in newSecretName }
        )

        viewModel.draft.displayName = "Updated Work"
        viewModel.draft.apiKey = "sk-new"

        XCTAssertFalse(viewModel.saveDraft())
        XCTAssertEqual(viewModel.lastErrorMessage, "save failed")
        XCTAssertEqual(store.saveAttempts.count, 1)
        XCTAssertEqual(store.saveAttempts.first?.profiles.first?.displayName, "Updated Work")
        XCTAssertEqual(store.saveAttempts.first?.profiles.first?.secretName, newSecretName)
        XCTAssertEqual(secrets.setSecretCalls.map(\.name), [newSecretName])
        XCTAssertEqual(secrets.deleteSecretCalls, [newSecretName])
        XCTAssertNil(try secrets.secret(named: newSecretName))
        XCTAssertEqual(try secrets.secret(named: oldSecretName), "sk-old")
        XCTAssertEqual(viewModel.profiles, existing)
    }

    func testBlankAPIKeyIsRejectedWhenNoExistingSecretIsAvailable() throws {
        let existing = [
            ProviderProfile(
                id: "local",
                displayName: "Local",
                kind: .ollamaNative,
                baseURL: URL(string: "http://localhost:11434")!,
                model: "llama3.2",
                isDefault: true
            )
        ]
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: existing))
        let secrets = RecordingSecretStore()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets
        )

        viewModel.changeDraftKind(.openAIResponses)

        XCTAssertFalse(viewModel.saveDraft())
        XCTAssertEqual(viewModel.lastErrorMessage, "此 provider 需要 API Key。")
        XCTAssertTrue(store.savedFiles.isEmpty)
        XCTAssertTrue(secrets.setSecretCalls.isEmpty)
        XCTAssertTrue(secrets.deleteSecretCalls.isEmpty)
        XCTAssertEqual(viewModel.profiles, existing)
    }

    func testBlankExistingSecretIsRejectedForCloudProvider() throws {
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
        let secrets = RecordingSecretStore(values: ["knowtype.provider.work.apiKey": " \n\t "])
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets
        )

        viewModel.draft.displayName = "Updated Work"

        XCTAssertFalse(viewModel.saveDraft())
        XCTAssertEqual(viewModel.lastErrorMessage, "此 provider 需要 API Key。")
        XCTAssertTrue(store.savedFiles.isEmpty)
        XCTAssertTrue(secrets.setSecretCalls.isEmpty)
        XCTAssertTrue(secrets.deleteSecretCalls.isEmpty)
        XCTAssertEqual(viewModel.profiles, existing)
    }

    func testLocalOpenAICompatibleProfileCanSaveWithoutAPIKeyAndModel() throws {
        let store = CapturingProfileStore(file: ProviderProfilesFile())
        let secrets = RecordingSecretStore()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false
        )

        viewModel.createProfile(kind: .openAIChat)
        viewModel.draft.displayName = "Local OpenAI Compatible"
        viewModel.draft.baseURL = "http://127.0.0.1:8317/v1"
        viewModel.draft.model = " \n "
        viewModel.draft.apiKey = " "
        viewModel.draft.isDefault = true

        XCTAssertTrue(viewModel.saveDraft())

        let saved = try XCTUnwrap(store.savedFiles.last?.profiles.first)
        XCTAssertEqual(saved.kind, .openAIChat)
        XCTAssertEqual(saved.baseURL.absoluteString, "http://127.0.0.1:8317/v1")
        XCTAssertEqual(saved.model, "")
        XCTAssertNil(saved.secretName)
        XCTAssertTrue(secrets.setSecretCalls.isEmpty)
        XCTAssertTrue(secrets.deleteSecretCalls.isEmpty)
    }

    func testLocalOpenAICompatibleBlankAPIKeyClearsExistingSecret() throws {
        let secretName = "knowtype.provider.work.apiKey"
        let existing = [
            ProviderProfile(
                id: "work",
                displayName: "Work",
                kind: .openAIChat,
                baseURL: URL(string: "https://api.openai.com")!,
                model: "gpt-4.1-mini",
                secretName: secretName,
                isDefault: true
            )
        ]
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: existing))
        let secrets = RecordingSecretStore(values: [secretName: "sk-existing"])
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets
        )

        viewModel.draft.baseURL = "http://localhost:8317/v1"
        viewModel.draft.model = " \n "
        viewModel.draft.apiKey = " \n "

        XCTAssertTrue(viewModel.saveDraft())

        let saved = try XCTUnwrap(store.savedFiles.last?.profiles.first)
        XCTAssertEqual(saved.baseURL.absoluteString, "http://localhost:8317/v1")
        XCTAssertEqual(saved.model, "")
        XCTAssertNil(saved.secretName)
        XCTAssertTrue(secrets.setSecretCalls.isEmpty)
        XCTAssertEqual(secrets.deleteSecretCalls, [secretName])
        XCTAssertNil(try secrets.secret(named: secretName))
    }

    func testLocalOpenAICompatibleBlankAPIKeyKeepsExistingLocalSecret() throws {
        let secretName = "knowtype.provider.local.apiKey"
        let existing = [
            ProviderProfile(
                id: "local",
                displayName: "Local",
                kind: .openAIChat,
                baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
                model: "gpt-5.2",
                secretName: secretName,
                isDefault: true
            )
        ]
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: existing))
        let secrets = RecordingSecretStore(values: [secretName: "local-key"])
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets
        )

        viewModel.draft.apiKey = " \n "

        XCTAssertTrue(viewModel.saveDraft())

        let saved = try XCTUnwrap(store.savedFiles.last?.profiles.first)
        XCTAssertEqual(saved.secretName, secretName)
        XCTAssertTrue(secrets.setSecretCalls.isEmpty)
        XCTAssertTrue(secrets.deleteSecretCalls.isEmpty)
        XCTAssertEqual(try secrets.secret(named: secretName), "local-key")
    }

    func testLocalOpenAICompatibleBlankAPIKeyClearsMissingLocalSecretReference() throws {
        let secretName = "knowtype.provider.local.apiKey"
        let existing = [
            ProviderProfile(
                id: "local",
                displayName: "Local",
                kind: .openAIChat,
                baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
                model: "gpt-5.2",
                secretName: secretName,
                isDefault: true
            )
        ]
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: existing))
        let secrets = RecordingSecretStore(values: [:])
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets
        )

        viewModel.draft.apiKey = " \n "

        XCTAssertTrue(viewModel.saveDraft())

        let saved = try XCTUnwrap(store.savedFiles.last?.profiles.first)
        XCTAssertNil(saved.secretName)
        XCTAssertTrue(secrets.setSecretCalls.isEmpty)
        XCTAssertTrue(secrets.deleteSecretCalls.isEmpty)
    }

    func testRemoteOpenAICompatibleProfileStillRequiresAPIKey() throws {
        let store = CapturingProfileStore(file: ProviderProfilesFile())
        let secrets = RecordingSecretStore()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false
        )

        viewModel.createProfile(kind: .openAIResponses)
        viewModel.draft.displayName = "Remote Responses"
        viewModel.draft.baseURL = "https://api.openai.com"
        viewModel.draft.model = "gpt-4.1-mini"
        viewModel.draft.apiKey = ""
        viewModel.draft.isDefault = true

        XCTAssertFalse(viewModel.saveDraft())
        XCTAssertEqual(viewModel.lastErrorMessage, "此 provider 需要 API Key。")
        XCTAssertTrue(viewModel.validationErrors.isEmpty)
        XCTAssertTrue(store.savedFiles.isEmpty)
        XCTAssertTrue(secrets.setSecretCalls.isEmpty)
    }

    func testRemoteOpenAICompatibleProfileRequiresModelEvenWithAPIKey() throws {
        let store = CapturingProfileStore(file: ProviderProfilesFile())
        let secrets = RecordingSecretStore()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false
        )

        viewModel.createProfile(kind: .openAIResponses)
        viewModel.draft.displayName = "Remote Responses"
        viewModel.draft.baseURL = "https://api.openai.com"
        viewModel.draft.model = " \n "
        viewModel.draft.apiKey = "sk-remote"
        viewModel.draft.isDefault = true

        XCTAssertFalse(viewModel.saveDraft())
        XCTAssertTrue(viewModel.validationErrors.contains("模型不能为空。"))
        XCTAssertTrue(store.savedFiles.isEmpty)
        XCTAssertTrue(secrets.setSecretCalls.isEmpty)
        XCTAssertTrue(secrets.deleteSecretCalls.isEmpty)
    }

    func testRemoteOpenAICompatibleProfileRejectsPlaceholderModel() throws {
        let store = CapturingProfileStore(file: ProviderProfilesFile())
        let secrets = RecordingSecretStore()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false
        )

        viewModel.createProfile(kind: .openAIChat)
        viewModel.draft.displayName = "Remote Chat"
        viewModel.draft.baseURL = "https://api.openai.com"
        viewModel.draft.model = "<model-id>"
        viewModel.draft.apiKey = "sk-remote"
        viewModel.draft.isDefault = true

        XCTAssertFalse(viewModel.saveDraft())
        XCTAssertTrue(viewModel.validationErrors.contains("模型不能为空。"))
        XCTAssertTrue(store.savedFiles.isEmpty)
        XCTAssertTrue(secrets.setSecretCalls.isEmpty)
        XCTAssertTrue(secrets.deleteSecretCalls.isEmpty)
    }

    func testLocalOpenAICompatibleProfileAllowsPlaceholderModelForDiscovery() throws {
        let store = CapturingProfileStore(file: ProviderProfilesFile())
        let secrets = RecordingSecretStore()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false
        )

        viewModel.createProfile(kind: .openAIChat)
        viewModel.draft.displayName = "Local Chat"
        viewModel.draft.baseURL = "http://127.0.0.1:8317/v1"
        viewModel.draft.model = "<model-id>"
        viewModel.draft.apiKey = ""
        viewModel.draft.isDefault = true

        XCTAssertTrue(viewModel.saveDraft())
        let saved = try XCTUnwrap(store.savedFiles.last?.profiles.first)
        XCTAssertEqual(saved.model, "<model-id>")
        XCTAssertNil(saved.secretName)
        XCTAssertTrue(secrets.setSecretCalls.isEmpty)
    }

    func testSaveFailureDoesNotDeleteExistingSecretForNoSecretProvider() throws {
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
        let store = SavingThrowingProfileStore(
            file: ProviderProfilesFile(profiles: existing),
            error: TestProfileStoreError(message: "save failed")
        )
        let secrets = RecordingSecretStore()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets
        )

        viewModel.changeDraftKind(.ollamaNative)

        XCTAssertFalse(viewModel.saveDraft())
        XCTAssertEqual(viewModel.lastErrorMessage, "save failed")
        XCTAssertTrue(secrets.deleteSecretCalls.isEmpty)
        XCTAssertTrue(secrets.setSecretCalls.isEmpty)
        XCTAssertEqual(viewModel.profiles, existing)
        XCTAssertNil(store.saveAttempts.last?.profiles.first?.secretName)
    }

    func testSaveFailureDoesNotOverwriteExistingSecretForReplacementAPIKey() throws {
        let newSecretName = "knowtype.provider.work.credential.00000000-0000-0000-0000-000000000001"
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
        let store = SavingThrowingProfileStore(
            file: ProviderProfilesFile(profiles: existing),
            error: TestProfileStoreError(message: "save failed")
        )
        let secrets = RecordingSecretStore()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets,
            credentialReferenceGenerator: { _ in newSecretName }
        )

        viewModel.draft.apiKey = "sk-replacement"

        XCTAssertFalse(viewModel.saveDraft())
        XCTAssertEqual(viewModel.lastErrorMessage, "save failed")
        XCTAssertEqual(secrets.setSecretCalls.map(\.name), [newSecretName])
        XCTAssertEqual(secrets.deleteSecretCalls, [newSecretName])
        XCTAssertEqual(viewModel.profiles, existing)
        XCTAssertEqual(store.saveAttempts.last?.profiles.first?.secretName, newSecretName)
    }

    func testSaveDraftDoesNotPublishProfilesWhenStoreSaveFails() throws {
        let existing = [
            ProviderProfile(
                id: "work",
                displayName: "Work",
                kind: .openAIChat,
                baseURL: URL(string: "https://api.openai.com")!,
                model: "gpt-4.1-mini",
                secretName: "knowtype.provider.work.apiKey",
                isDefault: true
            ),
            ProviderProfile(
                id: "local",
                displayName: "Local",
                kind: .ollamaNative,
                baseURL: URL(string: "http://localhost:11434")!,
                model: "llama3.2",
                isDefault: false
            )
        ]
        let store = SavingThrowingProfileStore(
            file: ProviderProfilesFile(profiles: existing),
            error: TestProfileStoreError(message: "save failed")
        )
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: InMemorySecretStore(values: ["knowtype.provider.work.apiKey": "sk-existing"])
        )

        viewModel.draft.displayName = "Unsaved Work"

        XCTAssertFalse(viewModel.saveDraft())
        XCTAssertEqual(viewModel.lastErrorMessage, "save failed")
        XCTAssertEqual(viewModel.profiles, existing)
        XCTAssertEqual(viewModel.draft.displayName, "Unsaved Work")
        XCTAssertEqual(store.saveAttempts.last?.profiles.first?.displayName, "Unsaved Work")
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
        XCTAssertTrue(viewModel.validationErrors.contains("至少需要保留一个默认 provider。"))
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

        XCTAssertTrue(errors.contains("Custom HTTP 请求体模板不能为空。"))
        XCTAssertTrue(errors.contains("Custom HTTP 响应路径不能为空。"))
    }

    func testCustomHTTPSavesWithoutAPIKey() throws {
        let store = CapturingProfileStore(file: ProviderProfilesFile())
        let secrets = RecordingSecretStore()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false
        )

        viewModel.createProfile(kind: .customHTTP)
        viewModel.draft.displayName = "Local Proxy"
        viewModel.draft.baseURL = "http://localhost:8787/complete"
        viewModel.draft.apiKey = " \n "
        viewModel.draft.isDefault = true

        XCTAssertTrue(viewModel.saveDraft())

        let saved = try XCTUnwrap(store.savedFiles.last?.profiles.first)
        XCTAssertEqual(saved.kind, .customHTTP)
        XCTAssertNil(saved.secretName)
        XCTAssertTrue(secrets.setSecretCalls.isEmpty)
        XCTAssertTrue(secrets.deleteSecretCalls.isEmpty)
    }

    func testCustomHTTPSavesOptionalAPIKey() throws {
        let store = CapturingProfileStore(file: ProviderProfilesFile())
        let secrets = RecordingSecretStore()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false
        )

        viewModel.createProfile(kind: .customHTTP)
        viewModel.draft.displayName = "Authenticated Proxy"
        viewModel.draft.baseURL = "https://proxy.example.com/complete"
        viewModel.draft.apiKey = " proxy-secret\n"
        viewModel.draft.isDefault = true

        XCTAssertTrue(viewModel.saveDraft())

        let saved = try XCTUnwrap(store.savedFiles.last?.profiles.first)
        XCTAssertTrue(saved.secretName?.hasPrefix("knowtype.provider.\(saved.id).credential.") == true)
        XCTAssertEqual(secrets.setSecretCalls.count, 1)
        XCTAssertEqual(secrets.setSecretCalls.first?.value, "proxy-secret")
        XCTAssertEqual(secrets.setSecretCalls.first?.name, saved.secretName)
    }

    func testCustomHTTPBlankAPIKeyKeepsExistingSecret() throws {
        let secretName = "knowtype.provider.proxy.apiKey"
        let existing = [
            ProviderProfile(
                id: "proxy",
                displayName: "Proxy",
                kind: .customHTTP,
                baseURL: URL(string: "https://proxy.example.com/complete")!,
                model: "",
                secretName: secretName,
                customBodyTemplate: #"{"request":{{request_json}}}"#,
                customResponsePath: "candidates",
                isDefault: true
            )
        ]
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: existing))
        let secrets = RecordingSecretStore(values: [secretName: "proxy-secret"])
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets
        )

        viewModel.draft.displayName = "Updated Proxy"
        viewModel.draft.apiKey = " \n "

        XCTAssertTrue(viewModel.saveDraft())
        let saved = try XCTUnwrap(store.savedFiles.last?.profiles.first)
        XCTAssertEqual(saved.displayName, "Updated Proxy")
        XCTAssertEqual(saved.secretName, secretName)
        XCTAssertTrue(secrets.setSecretCalls.isEmpty)
        XCTAssertTrue(secrets.deleteSecretCalls.isEmpty)
        XCTAssertEqual(try secrets.secret(named: secretName), "proxy-secret")
    }

    func testSetDefaultPersistsDefaultProviderChoice() throws {
        let profiles = ProviderProfileTemplates.defaultProfiles()
        let originalDraftID = try XCTUnwrap(profiles.first(where: \.isDefault)?.id)
        let targetID = try XCTUnwrap(profiles.first(where: { $0.kind == .ollamaNative })?.id)
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: profiles))
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: InMemorySecretStore()
        )

        try viewModel.setDefaultProfile(id: targetID)

        let saved = try XCTUnwrap(store.savedFiles.last?.profiles)
        XCTAssertEqual(saved.filter(\.isDefault).map(\.id), [targetID])
        XCTAssertEqual(viewModel.selectedProfileID, originalDraftID)
        XCTAssertEqual(viewModel.draft.id, originalDraftID)
        XCTAssertFalse(viewModel.draft.isDefault)
    }

    func testSetDefaultPreservesDraftEditsForSelectedProfile() throws {
        let profiles = ProviderProfileTemplates.defaultProfiles()
        let targetID = try XCTUnwrap(profiles.first(where: { $0.kind == .ollamaNative })?.id)
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: profiles))
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: InMemorySecretStore()
        )
        viewModel.selectProfile(id: targetID)
        viewModel.draft.displayName = "Unsaved Ollama Name"

        try viewModel.setDefaultProfile(id: targetID)

        XCTAssertEqual(viewModel.selectedProfileID, targetID)
        XCTAssertEqual(viewModel.draft.id, targetID)
        XCTAssertEqual(viewModel.draft.displayName, "Unsaved Ollama Name")
        XCTAssertTrue(viewModel.draft.isDefault)
    }

    func testSetDefaultRejectsRemoteServiceWithoutRequiredSecret() throws {
        let profiles = ProviderProfileEditingPolicy.profileScopedSecrets(ProviderProfileTemplates.defaultProfiles())
        let originalDefaultIDs = profiles.filter(\.isDefault).map(\.id)
        let targetID = try XCTUnwrap(profiles.first(where: { $0.kind == .openAIResponses })?.id)
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: profiles))
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: InMemorySecretStore()
        )

        XCTAssertThrowsError(try viewModel.setDefaultProfile(id: targetID)) { error in
            XCTAssertEqual(error as? ProviderProfilesViewModelError, .missingAPIKey)
        }
        XCTAssertEqual(viewModel.profiles.filter(\.isDefault).map(\.id), originalDefaultIDs)
        XCTAssertTrue(store.savedFiles.isEmpty)
        XCTAssertEqual(viewModel.savedConnectionStatus, .failure("此 provider 需要 API Key。"))
    }

    func testSetDefaultRejectsPlaceholderCustomHTTPTemplate() throws {
        let profiles = ProviderProfileEditingPolicy.profileScopedSecrets(ProviderProfileTemplates.defaultProfiles())
        let originalDefaultIDs = profiles.filter(\.isDefault).map(\.id)
        let targetID = try XCTUnwrap(profiles.first(where: { $0.kind == .customHTTP })?.id)
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: profiles))
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: InMemorySecretStore()
        )
        let message = SettingsLocalization.string("settings.provider.validation.customHTTPPlaceholder")

        XCTAssertThrowsError(try viewModel.setDefaultProfile(id: targetID)) { error in
            XCTAssertEqual(error as? ProviderProfilesViewModelError, .validationFailed(message))
        }
        XCTAssertEqual(viewModel.profiles.filter(\.isDefault).map(\.id), originalDefaultIDs)
        XCTAssertTrue(store.savedFiles.isEmpty)
        XCTAssertEqual(viewModel.savedConnectionStatus, .failure(message))
    }

    func testSetDefaultClearsMissingOptionalSecretBeforeSavingCurrentService() throws {
        let current = ProviderProfile(
            id: "current",
            displayName: "Current Local Ollama",
            kind: .ollamaNative,
            baseURL: URL(string: "http://localhost:11434")!,
            model: "llama3.2",
            isDefault: true
        )
        let target = ProviderProfile(
            id: "local-proxy",
            displayName: "Local Proxy",
            kind: .openAIChat,
            baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
            model: "",
            secretName: "knowtype.provider.local-proxy.apiKey"
        )
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: [current, target]))
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: InMemorySecretStore()
        )

        try viewModel.setDefaultProfile(id: target.id)

        let savedProfiles = try XCTUnwrap(store.savedFiles.last?.profiles)
        let savedTarget = try XCTUnwrap(savedProfiles.first(where: { $0.id == target.id }))
        XCTAssertTrue(savedTarget.isDefault)
        XCTAssertNil(savedTarget.secretName)
        XCTAssertEqual(savedProfiles.filter(\.isDefault).map(\.id), [target.id])
        XCTAssertNil(viewModel.profiles.first(where: { $0.id == target.id })?.secretName)
    }

    func testSetDefaultDoesNotPublishProfilesWhenStoreSaveFails() throws {
        let profiles = ProviderProfileTemplates.defaultProfiles()
        let originalDefaultIDs = profiles.filter(\.isDefault).map(\.id)
        let targetID = try XCTUnwrap(profiles.first(where: { $0.kind == .ollamaNative })?.id)
        let store = SavingThrowingProfileStore(
            file: ProviderProfilesFile(profiles: profiles),
            error: TestProfileStoreError(message: "save failed")
        )
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: InMemorySecretStore()
        )

        XCTAssertThrowsError(try viewModel.setDefaultProfile(id: targetID)) { error in
            XCTAssertEqual(error.localizedDescription, "save failed")
        }
        XCTAssertEqual(viewModel.profiles.filter(\.isDefault).map(\.id), originalDefaultIDs)
        XCTAssertEqual(store.saveAttempts.last?.profiles.filter(\.isDefault).map(\.id), [targetID])
    }

    func testFallbackProfileStoreErrorUsesOriginalLocalizedDescription() {
        let error = FailingProviderProfileStoreError(description: "setup failed")

        XCTAssertEqual(error.localizedDescription, "setup failed")
    }

    func testConnectionTestUsesSeededLocalDefaultWithoutSavingProfile() async throws {
        let store = CapturingProfileStore(file: ProviderProfilesFile())
        let capture = ConfigurationRecorder()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: RecordingSecretStore(),
            connectionTester: { configuration in
                await capture.append(configuration)
                return ProviderConnectionDiagnosticResult(providerName: "openai_chat", candidateCount: 1)
            }
        )

        let didConnect = await viewModel.testDraftConnection()
        XCTAssertTrue(didConnect)

        let configurations = await capture.configurations
        XCTAssertEqual(configurations, [
            ProviderConfiguration(
                kind: .openAIChat,
                baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
                model: ""
            )
        ])
        XCTAssertEqual(viewModel.connectionStatus, .success("已连接 openai_chat，收到 1 条候选。"))
        XCTAssertTrue(store.savedFiles.isEmpty)
    }

    func testSavedProfileConnectionUsesDefaultProfileInsteadOfUnsavedDraft() async throws {
        let defaultProfile = ProviderProfile(
            id: "default",
            displayName: "Default",
            kind: .openAIChat,
            baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
            model: "spark",
            isDefault: true
        )
        let editingProfile = ProviderProfile(
            id: "editing",
            displayName: "Editing",
            kind: .openAIChat,
            baseURL: URL(string: "http://127.0.0.1:9999/v1")!,
            model: "draft"
        )
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: [defaultProfile, editingProfile]))
        let capture = ConfigurationRecorder()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: RecordingSecretStore(),
            connectionTester: { configuration in
                await capture.append(configuration)
                return ProviderConnectionDiagnosticResult(providerName: "openai_chat", candidateCount: 1)
            }
        )
        viewModel.selectProfile(id: editingProfile.id)
        viewModel.draft.baseURL = "http://127.0.0.1:7777/v1"
        viewModel.draft.model = "unsaved-draft"

        let didConnect = await viewModel.testSavedProfileConnection()

        XCTAssertTrue(didConnect)
        let configurations = await capture.configurations
        XCTAssertEqual(configurations, [
            ProviderConfiguration(
                kind: .openAIChat,
                baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
                model: "spark"
            )
        ])
        XCTAssertTrue(store.savedFiles.isEmpty)
        XCTAssertEqual(viewModel.savedConnectionStatus, .success("已连接 openai_chat，收到 1 条候选。"))
        XCTAssertEqual(viewModel.draftConnectionStatus, .idle)
    }

    func testSavedProfileConnectionRequiresExplicitDefaultProfile() async throws {
        let profile = ProviderProfile(
            id: "not-default",
            displayName: "Not Default",
            kind: .openAIChat,
            baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
            model: "spark"
        )
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: [profile]))
        let capture = ConfigurationRecorder()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: RecordingSecretStore(),
            connectionTester: { configuration in
                await capture.append(configuration)
                return ProviderConnectionDiagnosticResult(providerName: "openai_chat", candidateCount: 1)
            }
        )

        let didConnect = await viewModel.testSavedProfileConnection()

        XCTAssertFalse(didConnect)
        let configurations = await capture.configurations
        XCTAssertEqual(configurations, [])
        XCTAssertEqual(viewModel.savedConnectionStatus, .failure("未配置服务"))
        XCTAssertEqual(viewModel.draftConnectionStatus, .idle)
    }

    func testSavedProfileConnectionRejectsPlaceholderCustomHTTPDefault() async throws {
        let profile = ProviderProfileTemplates.defaultProfile(kind: .customHTTP, isDefault: true)
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: [profile]))
        let capture = ConfigurationRecorder()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: RecordingSecretStore(),
            connectionTester: { configuration in
                await capture.append(configuration)
                return ProviderConnectionDiagnosticResult(providerName: "custom_http", candidateCount: 1)
            }
        )
        let message = SettingsLocalization.string("settings.provider.validation.customHTTPPlaceholder")

        let didConnect = await viewModel.testSavedProfileConnection()

        XCTAssertFalse(didConnect)
        let configurations = await capture.configurations
        XCTAssertEqual(configurations, [])
        XCTAssertTrue(store.savedFiles.isEmpty)
        XCTAssertEqual(viewModel.savedConnectionStatus, .failure(message))
    }

    func testSavedProfileConnectionClearsMissingOptionalSecretBeforeTesting() async throws {
        let profile = ProviderProfile(
            id: "local-proxy",
            displayName: "Local Proxy",
            kind: .openAIChat,
            baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
            model: "",
            secretName: "knowtype.provider.local-proxy.apiKey",
            isDefault: true
        )
        let store = CapturingProfileStore(file: ProviderProfilesFile(profiles: [profile]))
        let capture = ConfigurationRecorder()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: RecordingSecretStore(),
            connectionTester: { configuration in
                await capture.append(configuration)
                return ProviderConnectionDiagnosticResult(providerName: "openai_chat", candidateCount: 1)
            }
        )

        let didConnect = await viewModel.testSavedProfileConnection()

        XCTAssertTrue(didConnect)
        let configurations = await capture.configurations
        XCTAssertEqual(configurations, [
            ProviderConfiguration(
                kind: .openAIChat,
                baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
                model: ""
            )
        ])
        let savedProfile = try XCTUnwrap(store.savedFiles.last?.profiles.first)
        XCTAssertNil(savedProfile.secretName)
        XCTAssertNil(viewModel.profiles.first?.secretName)
        XCTAssertEqual(viewModel.savedConnectionStatus, .success("已连接 openai_chat，收到 1 条候选。"))
    }

    func testDraftConnectionStatusDoesNotReplaceSavedServiceStatus() async throws {
        let defaultProfile = ProviderProfile(
            id: "default",
            displayName: "Default",
            kind: .openAIChat,
            baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
            model: "spark",
            isDefault: true
        )
        let editingProfile = ProviderProfile(
            id: "editing",
            displayName: "Editing",
            kind: .openAIChat,
            baseURL: URL(string: "http://127.0.0.1:9999/v1")!,
            model: "draft"
        )
        let viewModel = ProviderProfilesViewModel(
            profileStore: CapturingProfileStore(file: ProviderProfilesFile(profiles: [defaultProfile, editingProfile])),
            secretStore: RecordingSecretStore(),
            connectionTester: { _ in
                ProviderConnectionDiagnosticResult(providerName: "openai_chat", candidateCount: 1)
            }
        )

        let savedDidConnect = await viewModel.testSavedProfileConnection()
        XCTAssertTrue(savedDidConnect)
        XCTAssertEqual(viewModel.savedConnectionStatus, .success("已连接 openai_chat，收到 1 条候选。"))

        viewModel.selectProfile(id: editingProfile.id)
        viewModel.draft.baseURL = "not a url"
        let draftDidConnect = await viewModel.testDraftConnection()
        XCTAssertFalse(draftDidConnect)

        XCTAssertEqual(viewModel.savedConnectionStatus, .success("已连接 openai_chat，收到 1 条候选。"))
        XCTAssertEqual(viewModel.draftConnectionStatus, .failure("请先修复校验错误再测试连接。"))
    }

    func testConnectionTestUsesTransientDraftAPIKeyWithoutPersistingIt() async throws {
        let store = CapturingProfileStore(file: ProviderProfilesFile())
        let secrets = RecordingSecretStore()
        let capture = ConfigurationRecorder()
        let viewModel = ProviderProfilesViewModel(
            profileStore: store,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false,
            connectionTester: { configuration in
                await capture.append(configuration)
                return ProviderConnectionDiagnosticResult(providerName: "openai_responses", candidateCount: 2)
            }
        )

        viewModel.createProfile(kind: .openAIResponses)
        viewModel.draft.displayName = "Remote Responses"
        viewModel.draft.baseURL = "https://api.openai.com"
        viewModel.draft.model = "gpt-4.1-mini"
        viewModel.draft.apiKey = " sk-test\n"
        viewModel.draft.isDefault = true

        let didConnect = await viewModel.testDraftConnection()
        XCTAssertTrue(didConnect)

        let configurations = await capture.configurations
        XCTAssertEqual(configurations.first?.apiKey, "sk-test")
        XCTAssertEqual(configurations.first?.kind, .openAIResponses)
        XCTAssertEqual(viewModel.connectionStatus, .success("已连接 openai_responses，收到 2 条候选。"))
        XCTAssertTrue(store.savedFiles.isEmpty)
        XCTAssertTrue(secrets.setSecretCalls.isEmpty)
    }

    func testConnectionTestUsesExistingSavedSecretWhenDraftAPIKeyIsBlank() async throws {
        let existing = [
            ProviderProfile(
                id: "remote",
                displayName: "Remote",
                kind: .openAIResponses,
                baseURL: URL(string: "https://api.openai.com")!,
                model: "gpt-4.1-mini",
                secretName: "knowtype.provider.remote.apiKey",
                isDefault: true
            )
        ]
        let capture = ConfigurationRecorder()
        let viewModel = ProviderProfilesViewModel(
            profileStore: CapturingProfileStore(file: ProviderProfilesFile(profiles: existing)),
            secretStore: RecordingSecretStore(values: ["knowtype.provider.remote.apiKey": "sk-existing"]),
            connectionTester: { configuration in
                await capture.append(configuration)
                return ProviderConnectionDiagnosticResult(providerName: "openai_responses", candidateCount: 1)
            }
        )

        let didConnect = await viewModel.testDraftConnection()
        XCTAssertTrue(didConnect)

        let configurations = await capture.configurations
        XCTAssertEqual(configurations.first?.apiKey, "sk-existing")
    }

    func testConnectionTestDoesNotReuseRemoteSecretWhenDraftSwitchesToLocalEndpoint() async throws {
        let existing = [
            ProviderProfile(
                id: "remote",
                displayName: "Remote",
                kind: .openAIChat,
                baseURL: URL(string: "https://api.openai.com")!,
                model: "gpt-4.1-mini",
                secretName: "knowtype.provider.remote.apiKey",
                isDefault: true
            )
        ]
        let capture = ConfigurationRecorder()
        let viewModel = ProviderProfilesViewModel(
            profileStore: CapturingProfileStore(file: ProviderProfilesFile(profiles: existing)),
            secretStore: RecordingSecretStore(values: ["knowtype.provider.remote.apiKey": "sk-remote"]),
            connectionTester: { configuration in
                await capture.append(configuration)
                return ProviderConnectionDiagnosticResult(providerName: "openai_chat", candidateCount: 1)
            }
        )
        viewModel.draft.baseURL = "http://127.0.0.1:8317/v1"
        viewModel.draft.model = ""
        viewModel.draft.apiKey = ""

        let didConnect = await viewModel.testDraftConnection()

        XCTAssertTrue(didConnect)
        let configurations = await capture.configurations
        XCTAssertNil(configurations.first?.apiKey)
    }

    func testConnectionTestDoesNotReuseSecretWhenDraftProviderKindChanges() async throws {
        let existing = [
            ProviderProfile(
                id: "remote",
                displayName: "Remote",
                kind: .openAIChat,
                baseURL: URL(string: "https://api.openai.com")!,
                model: "gpt-4.1-mini",
                secretName: "knowtype.provider.remote.apiKey",
                isDefault: true
            )
        ]
        let capture = ConfigurationRecorder()
        let viewModel = ProviderProfilesViewModel(
            profileStore: CapturingProfileStore(file: ProviderProfilesFile(profiles: existing)),
            secretStore: RecordingSecretStore(values: ["knowtype.provider.remote.apiKey": "sk-openai"]),
            connectionTester: { configuration in
                await capture.append(configuration)
                return ProviderConnectionDiagnosticResult(providerName: "anthropic_messages", candidateCount: 1)
            }
        )
        viewModel.changeDraftKind(.anthropicMessages)
        viewModel.draft.apiKey = ""

        let didConnect = await viewModel.testDraftConnection()

        XCTAssertFalse(didConnect)
        XCTAssertEqual(viewModel.connectionStatus, .failure("此 provider 需要 API Key。"))
        let configurations = await capture.configurations
        XCTAssertTrue(configurations.isEmpty)
    }

    func testConnectionTestReportsMissingRequiredAPIKey() async throws {
        let viewModel = ProviderProfilesViewModel(
            profileStore: CapturingProfileStore(file: ProviderProfilesFile()),
            secretStore: RecordingSecretStore(),
            loadDefaultsWhenEmpty: false,
            connectionTester: { _ in
                XCTFail("Connection tester should not run without a required API key")
                return ProviderConnectionDiagnosticResult(providerName: "unused", candidateCount: 1)
            }
        )

        viewModel.createProfile(kind: .openAIResponses)
        viewModel.draft.displayName = "Remote Responses"
        viewModel.draft.baseURL = "https://api.openai.com"
        viewModel.draft.model = "gpt-4.1-mini"
        viewModel.draft.apiKey = ""
        viewModel.draft.isDefault = true

        let didConnect = await viewModel.testDraftConnection()
        XCTAssertFalse(didConnect)
        XCTAssertEqual(viewModel.connectionStatus, .failure("此 provider 需要 API Key。"))
        XCTAssertNil(viewModel.lastErrorMessage)
    }

    func testConnectionTestSurfacesCurrentValidationErrorsBeforeReturning() async throws {
        let viewModel = ProviderProfilesViewModel(
            profileStore: CapturingProfileStore(file: ProviderProfilesFile()),
            secretStore: RecordingSecretStore(),
            connectionTester: { _ in
                XCTFail("Connection tester should not run for invalid draft")
                return ProviderConnectionDiagnosticResult(providerName: "unused", candidateCount: 1)
            }
        )
        viewModel.draft.displayName = " \n "

        let didConnect = await viewModel.testDraftConnection()

        XCTAssertFalse(didConnect)
        XCTAssertEqual(viewModel.connectionStatus, .failure("请先修复校验错误再测试连接。"))
        XCTAssertTrue(viewModel.validationErrors.contains("显示名称不能为空。"))
        XCTAssertNil(viewModel.lastErrorMessage)
    }

    func testConnectionStatusResetsWhenDraftChangesAfterTest() async throws {
        let viewModel = ProviderProfilesViewModel(
            profileStore: CapturingProfileStore(file: ProviderProfilesFile()),
            secretStore: RecordingSecretStore(),
            connectionTester: { _ in
                ProviderConnectionDiagnosticResult(providerName: "openai_chat", candidateCount: 1)
            }
        )

        let didConnect = await viewModel.testDraftConnection()
        XCTAssertTrue(didConnect)
        XCTAssertEqual(viewModel.connectionStatus, .success("已连接 openai_chat，收到 1 条候选。"))

        viewModel.draft.baseURL = "http://localhost:8317/v1"

        XCTAssertEqual(viewModel.connectionStatus, .idle)
    }

    func testConnectionFailureDoesNotUsePersistentLastErrorSlot() async throws {
        let viewModel = ProviderProfilesViewModel(
            profileStore: CapturingProfileStore(file: ProviderProfilesFile()),
            secretStore: RecordingSecretStore(),
            connectionTester: { _ in
                throw ProviderError.invalidResponse("diagnostic failed")
            }
        )

        let didConnect = await viewModel.testDraftConnection()

        XCTAssertFalse(didConnect)
        XCTAssertEqual(viewModel.connectionStatus, .failure("Invalid provider response: diagnostic failed"))
        XCTAssertNil(viewModel.lastErrorMessage)
    }

    func testConnectionSuccessPreservesPreviousPersistentSaveError() async throws {
        let existing = [
            ProviderProfile(
                id: "local",
                displayName: "Local",
                kind: .openAIChat,
                baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
                model: "",
                isDefault: true
            )
        ]
        let viewModel = ProviderProfilesViewModel(
            profileStore: SavingThrowingProfileStore(
                file: ProviderProfilesFile(profiles: existing),
                error: TestProfileStoreError(message: "save failed")
            ),
            secretStore: RecordingSecretStore(),
            connectionTester: { _ in
                ProviderConnectionDiagnosticResult(providerName: "openai_chat", candidateCount: 1)
            }
        )

        viewModel.draft.displayName = "Updated Local"
        XCTAssertFalse(viewModel.saveDraft())
        XCTAssertEqual(viewModel.lastErrorMessage, "save failed")

        let didConnect = await viewModel.testDraftConnection()

        XCTAssertTrue(didConnect)
        XCTAssertEqual(viewModel.connectionStatus, .success("已连接 openai_chat，收到 1 条候选。"))
        XCTAssertEqual(viewModel.lastErrorMessage, "save failed")
    }

    func testConnectionTestPreservesSaveOnlyValidationErrors() async throws {
        let existing = [
            ProviderProfile(
                id: "local",
                displayName: "Local",
                kind: .openAIChat,
                baseURL: URL(string: "http://127.0.0.1:8317/v1")!,
                model: "",
                isDefault: true
            )
        ]
        let viewModel = ProviderProfilesViewModel(
            profileStore: CapturingProfileStore(file: ProviderProfilesFile(profiles: existing)),
            secretStore: RecordingSecretStore(),
            connectionTester: { _ in
                ProviderConnectionDiagnosticResult(providerName: "openai_chat", candidateCount: 1)
            }
        )

        viewModel.draft.isDefault = false
        XCTAssertFalse(viewModel.saveDraft())
        XCTAssertTrue(viewModel.validationErrors.contains("至少需要保留一个默认 provider。"))

        let didConnect = await viewModel.testDraftConnection()

        XCTAssertTrue(didConnect)
        XCTAssertTrue(viewModel.validationErrors.contains("至少需要保留一个默认 provider。"))
    }

    func testSupersededConnectionTestDoesNotPublishResult() async throws {
        let tester = DelayedConnectionTester()
        let viewModel = ProviderProfilesViewModel(
            profileStore: CapturingProfileStore(file: ProviderProfilesFile()),
            secretStore: RecordingSecretStore(),
            connectionTester: { configuration in
                try await tester.test(configuration)
            }
        )

        let pendingTest = Task {
            await viewModel.testDraftConnection()
        }
        while await !tester.hasPending {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(viewModel.connectionStatus, .testing)

        viewModel.createProfile(kind: .ollamaNative)
        await tester.resume(with: ProviderConnectionDiagnosticResult(providerName: "openai_chat", candidateCount: 1))
        let didConnect = await pendingTest.value

        XCTAssertFalse(didConnect)
        XCTAssertEqual(viewModel.connectionStatus, .idle)
        XCTAssertNil(viewModel.lastErrorMessage)
    }

    func testTwoViewModelsRejectStaleSaveWithoutLosingNewProfileAndKeepDraft() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-vm-stale-save-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("providers.json")
        let storeA = FileProviderProfileStore(fileURL: fileURL, revisionSignal: NoopRevisionSignal())
        let storeB = FileProviderProfileStore(fileURL: fileURL, revisionSignal: NoopRevisionSignal())
        let initial = ProviderProfile(
            id: "initial",
            displayName: "Initial",
            kind: .ollamaNative,
            baseURL: URL(string: "http://localhost:11434")!,
            model: "llama3.2",
            isDefault: true
        )
        _ = try storeA.transactProfiles(expectedRevision: 0) { current in
            var updated = current
            updated.profiles = [initial]
            return updated
        }
        let secrets = InMemorySecretStore()
        let viewModelA = ProviderProfilesViewModel(
            profileStore: storeA,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false
        )
        let viewModelB = ProviderProfilesViewModel(
            profileStore: storeB,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false
        )

        viewModelA.createProfile(kind: .ollamaNative)
        let addedID = viewModelA.draft.id
        viewModelA.draft.displayName = "Added by A"
        viewModelA.draft.isDefault = false
        XCTAssertTrue(viewModelA.saveDraft())

        viewModelB.draft.displayName = "Unsaved edit from B"
        XCTAssertFalse(viewModelB.saveDraft())

        let disk = try storeA.loadProfiles()
        XCTAssertEqual(disk.profiles.count, 2)
        XCTAssertEqual(disk.profiles.first(where: { $0.id == "initial" })?.displayName, "Initial")
        XCTAssertEqual(disk.profiles.first(where: { $0.id == addedID })?.displayName, "Added by A")
        XCTAssertEqual(viewModelB.profiles, disk.profiles)
        XCTAssertEqual(viewModelB.draft.displayName, "Unsaved edit from B")
        XCTAssertEqual(
            viewModelB.lastErrorMessage,
            "Provider 配置已在另一个 KnowType 设置窗口中更新。当前草稿已保留，磁盘配置已刷新；请核对最新内容后重试。"
        )
    }

    func testTwoViewModelsRejectStaleDefaultChangeAndRefreshProfiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-vm-stale-default-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("providers.json")
        let storeA = FileProviderProfileStore(fileURL: fileURL, revisionSignal: NoopRevisionSignal())
        let storeB = FileProviderProfileStore(fileURL: fileURL, revisionSignal: NoopRevisionSignal())
        let first = ProviderProfile(
            id: "first",
            displayName: "First",
            kind: .ollamaNative,
            baseURL: URL(string: "http://localhost:11434")!,
            model: "first-model",
            isDefault: true
        )
        let second = ProviderProfile(
            id: "second",
            displayName: "Second",
            kind: .ollamaNative,
            baseURL: URL(string: "http://localhost:11435")!,
            model: "second-model"
        )
        _ = try storeA.transactProfiles(expectedRevision: 0) { current in
            var updated = current
            updated.profiles = [first, second]
            return updated
        }
        let secrets = InMemorySecretStore()
        let viewModelA = ProviderProfilesViewModel(
            profileStore: storeA,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false
        )
        let viewModelB = ProviderProfilesViewModel(
            profileStore: storeB,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false
        )

        viewModelB.draft.displayName = "Unsaved B draft"
        viewModelA.draft.displayName = "First updated by A"
        XCTAssertTrue(viewModelA.saveDraft())

        XCTAssertThrowsError(try viewModelB.setDefaultProfile(id: second.id)) { error in
            XCTAssertEqual(error as? ProviderProfilesViewModelError, .staleBaseline)
        }

        let disk = try storeA.loadProfiles()
        XCTAssertEqual(disk.profiles.filter(\.isDefault).map(\.id), [first.id])
        XCTAssertEqual(viewModelB.profiles.first(where: { $0.id == first.id })?.displayName, "First updated by A")
        XCTAssertEqual(viewModelB.draft.displayName, "Unsaved B draft")
    }

    func testTwoViewModelsRejectStaleDraftAndSavedTestsWithoutSendingK2ToE1() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-vm-stale-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("providers.json")
        let storeA = FileProviderProfileStore(fileURL: fileURL, revisionSignal: NoopRevisionSignal())
        let storeB = FileProviderProfileStore(fileURL: fileURL, revisionSignal: NoopRevisionSignal())
        let storeC = FileProviderProfileStore(fileURL: fileURL, revisionSignal: NoopRevisionSignal())
        let oldSecretName = "legacy.provider.work.apiKey"
        let newSecretName = "knowtype.provider.work.credential.00000000-0000-0000-0000-000000000002"
        let initial = ProviderProfile(
            id: "work",
            displayName: "Work",
            kind: .openAIResponses,
            baseURL: URL(string: "https://e1.example.com/v1")!,
            model: "gpt-test",
            secretName: oldSecretName,
            isDefault: true
        )
        _ = try storeA.transactProfiles(expectedRevision: 0) { current in
            var updated = current
            updated.profiles = [initial]
            return updated
        }
        let secrets = InMemorySecretStore(values: [oldSecretName: "K1"])
        let recorder = ConfigurationRecorder()
        let viewModelA = ProviderProfilesViewModel(
            profileStore: storeA,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false,
            credentialReferenceGenerator: { _ in newSecretName }
        )
        let viewModelB = ProviderProfilesViewModel(
            profileStore: storeB,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false,
            connectionTester: { configuration in
                await recorder.append(configuration)
                return ProviderConnectionDiagnosticResult(providerName: "test", candidateCount: 1)
            }
        )
        let viewModelC = ProviderProfilesViewModel(
            profileStore: storeC,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false,
            connectionTester: { configuration in
                await recorder.append(configuration)
                return ProviderConnectionDiagnosticResult(providerName: "test", candidateCount: 1)
            }
        )

        viewModelA.draft.baseURL = "https://e2.example.com/v1"
        viewModelA.draft.apiKey = "K2"
        XCTAssertTrue(viewModelA.saveDraft())

        let staleDraftResult = await viewModelB.testDraftConnection()
        let staleSavedResult = await viewModelC.testSavedProfileConnection()
        let refreshedDraftResult = await viewModelB.testDraftConnection()
        XCTAssertFalse(staleDraftResult)
        XCTAssertFalse(staleSavedResult)
        XCTAssertFalse(refreshedDraftResult)

        let configurations = await recorder.configurations
        XCTAssertTrue(configurations.isEmpty)
        XCTAssertEqual(viewModelB.draft.baseURL, "https://e1.example.com/v1")
        XCTAssertEqual(viewModelB.profiles.first?.baseURL.absoluteString, "https://e2.example.com/v1")
        XCTAssertEqual(try secrets.secret(named: newSecretName), "K2")
        XCTAssertNil(try secrets.secret(named: oldSecretName))
    }

    func testInFlightE1TestUsesK1ThenRejectsResultAfterE2K2Commit() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-vm-inflight-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("providers.json")
        let storeA = FileProviderProfileStore(fileURL: fileURL, revisionSignal: NoopRevisionSignal())
        let storeB = FileProviderProfileStore(fileURL: fileURL, revisionSignal: NoopRevisionSignal())
        let oldSecretName = "legacy.provider.work.apiKey"
        let newSecretName = "knowtype.provider.work.credential.00000000-0000-0000-0000-000000000002"
        let initial = ProviderProfile(
            id: "work",
            displayName: "Work",
            kind: .openAIResponses,
            baseURL: URL(string: "https://e1.example.com/v1")!,
            model: "gpt-test",
            secretName: oldSecretName,
            isDefault: true
        )
        _ = try storeA.transactProfiles(expectedRevision: 0) { current in
            var updated = current
            updated.profiles = [initial]
            return updated
        }
        let secrets = InMemorySecretStore(values: [oldSecretName: "K1"])
        let tester = BlockingConfigurationTester()
        let viewModelA = ProviderProfilesViewModel(
            profileStore: storeA,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false,
            credentialReferenceGenerator: { _ in newSecretName }
        )
        let viewModelB = ProviderProfilesViewModel(
            profileStore: storeB,
            secretStore: secrets,
            loadDefaultsWhenEmpty: false,
            connectionTester: { configuration in
                await tester.test(configuration)
            }
        )

        let pendingTest = Task { await viewModelB.testDraftConnection() }
        while await !tester.hasPending {
            try await Task.sleep(for: .milliseconds(1))
        }

        viewModelA.draft.baseURL = "https://e2.example.com/v1"
        viewModelA.draft.apiKey = "K2"
        XCTAssertTrue(viewModelA.saveDraft())
        await tester.resume()

        let didConnect = await pendingTest.value
        let configurations = await tester.configurations
        XCTAssertFalse(didConnect)
        let configuration = try XCTUnwrap(configurations.first)
        XCTAssertEqual(configuration.baseURL.absoluteString, "https://e1.example.com/v1")
        XCTAssertEqual(configuration.apiKey, "K1")
        XCTAssertNotEqual(configuration.apiKey, "K2")
        XCTAssertEqual(viewModelB.profiles.first?.baseURL.absoluteString, "https://e2.example.com/v1")
        XCTAssertEqual(viewModelB.draft.baseURL, "https://e1.example.com/v1")
    }
}

private actor ConfigurationRecorder {
    private(set) var configurations: [ProviderConfiguration] = []

    func append(_ configuration: ProviderConfiguration) {
        configurations.append(configuration)
    }
}

private actor BlockingConfigurationTester {
    private var continuation: CheckedContinuation<ProviderConnectionDiagnosticResult, Never>?
    private(set) var configurations: [ProviderConfiguration] = []

    var hasPending: Bool {
        continuation != nil
    }

    func test(_ configuration: ProviderConfiguration) async -> ProviderConnectionDiagnosticResult {
        configurations.append(configuration)
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume(
            returning: ProviderConnectionDiagnosticResult(providerName: "test", candidateCount: 1)
        )
        continuation = nil
    }
}

private struct NoopRevisionSignal: ProviderProfileRevisionSignaling {
    func postProviderProfilesChanged(revision: UInt64) {}
}

private actor DelayedConnectionTester {
    private var continuation: CheckedContinuation<ProviderConnectionDiagnosticResult, Error>?

    var hasPending: Bool {
        continuation != nil
    }

    func test(_ configuration: ProviderConfiguration) async throws -> ProviderConnectionDiagnosticResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with result: ProviderConnectionDiagnosticResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private final class CapturingProfileStore: ProviderProfileStore, @unchecked Sendable {
    private var file: ProviderProfilesFile
    private(set) var savedFiles: [ProviderProfilesFile] = []
    private let lock = NSLock()

    init(file: ProviderProfilesFile) {
        self.file = file
    }

    func loadProfiles() throws -> ProviderProfilesFile {
        lock.lock()
        defer { lock.unlock() }
        return file
    }

    func saveProfiles(_ profiles: ProviderProfilesFile) throws {
        lock.lock()
        defer { lock.unlock() }
        savedFiles.append(profiles)
        file = profiles
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

private final class SavingThrowingProfileStore: ProviderProfileStore, @unchecked Sendable {
    private let file: ProviderProfilesFile
    private let error: Error
    private(set) var saveAttempts: [ProviderProfilesFile] = []

    init(file: ProviderProfilesFile, error: Error) {
        self.file = file
        self.error = error
    }

    func loadProfiles() throws -> ProviderProfilesFile {
        file
    }

    func saveProfiles(_ profiles: ProviderProfilesFile) throws {
        saveAttempts.append(profiles)
        throw error
    }
}

private final class RecordingSecretStore: SecretStore, @unchecked Sendable {
    private var values: [String: String]
    private let setError: Error?
    private let deleteError: Error?
    private let deleteErrors: [String: Error]
    private(set) var setSecretCalls: [(value: String, name: String)] = []
    private(set) var deleteSecretCalls: [String] = []

    init(
        values: [String: String] = [:],
        setError: Error? = nil,
        deleteError: Error? = nil,
        deleteErrors: [String: Error] = [:]
    ) {
        self.values = values
        self.setError = setError
        self.deleteError = deleteError
        self.deleteErrors = deleteErrors
    }

    func secret(named name: String) throws -> String? {
        values[name]
    }

    func setSecret(_ value: String, named name: String) throws {
        setSecretCalls.append((value: value, name: name))
        if let setError {
            throw setError
        }
        values[name] = value
    }

    func deleteSecret(named name: String) throws {
        deleteSecretCalls.append(name)
        if let error = deleteErrors[name] {
            throw error
        }
        if let deleteError {
            throw deleteError
        }
        values.removeValue(forKey: name)
    }
}

private struct TestProfileStoreError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
