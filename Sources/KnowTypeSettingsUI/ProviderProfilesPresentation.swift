import Foundation
import KnowTypeProviders

struct SettingsKeyValuePresentation: Equatable, Sendable {
    var label: String
    var value: String
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

    init(draft: ProviderProfileDraft) {
        self.displayNameFieldLabel = "Display Name"
        self.kindPickerLabel = "Kind"
        self.baseURLFieldLabel = "Base URL"
        self.modelFieldLabel = "Model"
        self.timeoutLabel = "Timeout: \(Int(draft.timeoutSeconds)) seconds"
        self.defaultProviderLabel = "Default provider"
        self.showsCustomHTTPFields = draft.kind == .customHTTP
        self.customBodyTemplateLabel = "Custom HTTP"
        self.customResponsePathLabel = "Response Path"
        self.secret = ProviderSecretPresentation(secretName: draft.secretName)
    }
}

struct ProviderSecretPresentation: Equatable, Sendable {
    var sectionTitle: String
    var apiKeyFieldPrompt: String
    var reference: SettingsKeyValuePresentation?
    var helpText: String

    init(secretName: String?) {
        self.sectionTitle = "API Key"
        self.apiKeyFieldPrompt = "Leave blank to keep existing key"
        self.reference = secretName.map {
            SettingsKeyValuePresentation(label: "Secret reference", value: $0)
        }
        self.helpText = "API keys are written through the secret store. On macOS this uses Keychain; provider JSON stores secret references only."
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

    init(status: ProviderConnectionStatus) {
        self.sectionTitle = "Connection"
        self.testButtonLabel = "Test Connection"
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

    init(errors: [String]) {
        self.title = "Validation"
        self.messages = errors
    }
}

struct ProviderLastErrorPresentation: Equatable, Sendable {
    var title: String
    var message: String?

    var isVisible: Bool {
        message != nil
    }

    init(message: String?) {
        self.title = "Last Error"
        self.message = message
    }
}
