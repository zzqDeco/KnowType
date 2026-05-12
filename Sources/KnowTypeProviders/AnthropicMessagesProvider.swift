import Foundation
import KnowTypeCore

public struct AnthropicMessagesProvider: LLMProvider {
    public let providerName = "anthropic_messages"
    private let configuration: ProviderConfiguration
    private let httpClient: any HTTPClient

    public init(configuration: ProviderConfiguration, httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.configuration = configuration
        self.httpClient = httpClient
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        var urlRequest = URLRequest(url: configuration.endpoint(path: "/v1/messages"))
        applyCommonHeaders(&urlRequest, configuration: configuration)
        if let apiKey = configuration.apiKey, !apiKey.isEmpty {
            urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        if urlRequest.value(forHTTPHeaderField: "anthropic-version") == nil {
            urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        urlRequest.httpBody = try jsonData([
            "model": configuration.model,
            "system": PromptBuilder.systemPrompt,
            "max_tokens": 256,
            "temperature": 0.2,
            "messages": [
                ["role": "user", "content": PromptBuilder.userPayload(for: request)]
            ]
        ])

        let (data, response) = try await httpClient.data(for: urlRequest)
        try validateHTTPResponse(response, data: data)
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let content = ResponseNormalizer.string(at: ["content", "0", "text"], in: raw) else {
            throw ProviderError.invalidResponse("missing content[0].text")
        }
        return try ResponseNormalizer.normalizeText(content)
    }
}
