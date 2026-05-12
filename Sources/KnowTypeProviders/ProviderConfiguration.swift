import Foundation
import KnowTypeCore

public enum ProviderKind: String, Codable, Sendable, Equatable, CaseIterable {
    case openAIChat = "openai_chat"
    case openAIResponses = "openai_responses"
    case anthropicMessages = "anthropic_messages"
    case geminiNative = "gemini_native"
    case ollamaNative = "ollama_native"
    case customHTTP = "custom_http"
}

public struct ProviderConfiguration: Codable, Sendable, Equatable {
    public var kind: ProviderKind
    public var baseURL: URL
    public var apiKey: String?
    public var model: String
    public var timeoutSeconds: TimeInterval
    public var headers: [String: String]
    public var customBodyTemplate: String?
    public var customResponsePath: String?

    public init(
        kind: ProviderKind,
        baseURL: URL,
        apiKey: String? = nil,
        model: String,
        timeoutSeconds: TimeInterval = 20,
        headers: [String: String] = [:],
        customBodyTemplate: String? = nil,
        customResponsePath: String? = nil
    ) {
        self.kind = kind
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.timeoutSeconds = timeoutSeconds
        self.headers = headers
        self.customBodyTemplate = customBodyTemplate
        self.customResponsePath = customResponsePath
    }

    func endpoint(path: String) -> URL {
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if baseURL.path.hasSuffix("/v1"), suffix.hasPrefix("v1/") {
            suffix.removeFirst("v1/".count)
        }
        return URL(string: "\(base)/\(suffix)")!
    }
}

public enum ProviderError: Error, Equatable, CustomStringConvertible {
    case invalidResponse(String)
    case httpStatus(Int, String)
    case missingAPIKey
    case invalidTemplate(String)
    case unsupportedKind(ProviderKind)

    public var description: String {
        switch self {
        case .invalidResponse(let message):
            return "Invalid provider response: \(message)"
        case .httpStatus(let status, let body):
            return "Provider returned HTTP \(status): \(body)"
        case .missingAPIKey:
            return "Provider requires an API key"
        case .invalidTemplate(let message):
            return "Invalid custom HTTP template: \(message)"
        case .unsupportedKind(let kind):
            return "Unsupported provider kind: \(kind.rawValue)"
        }
    }
}

public enum ProviderFactory {
    public static func makeProvider(
        configuration: ProviderConfiguration,
        httpClient: any HTTPClient = URLSessionHTTPClient()
    ) throws -> any LLMProvider {
        switch configuration.kind {
        case .openAIChat:
            return OpenAIChatProvider(configuration: configuration, httpClient: httpClient)
        case .openAIResponses:
            return OpenAIResponsesProvider(configuration: configuration, httpClient: httpClient)
        case .anthropicMessages:
            return AnthropicMessagesProvider(configuration: configuration, httpClient: httpClient)
        case .geminiNative:
            return GeminiNativeProvider(configuration: configuration, httpClient: httpClient)
        case .ollamaNative:
            return OllamaNativeProvider(configuration: configuration, httpClient: httpClient)
        case .customHTTP:
            return CustomHTTPProvider(configuration: configuration, httpClient: httpClient)
        }
    }
}
