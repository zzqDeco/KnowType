import Foundation
import KnowTypeCore

public struct OpenAIChatProvider: LLMProvider {
    public let providerName = "openai_chat"
    private let configuration: ProviderConfiguration
    private let httpClient: any HTTPClient

    public init(configuration: ProviderConfiguration, httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.configuration = configuration
        self.httpClient = httpClient
    }

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        var urlRequest = URLRequest(url: configuration.endpoint(path: "/v1/chat/completions"))
        applyCommonHeaders(&urlRequest, configuration: configuration)
        if let apiKey = configuration.apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        urlRequest.httpBody = try jsonData([
            "model": configuration.model,
            "stream": false,
            "temperature": 0.2,
            "max_tokens": 256,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": PromptBuilder.systemPrompt],
                ["role": "user", "content": PromptBuilder.userPayload(for: request)]
            ]
        ])

        let (data, response) = try await httpClient.data(for: urlRequest)
        try validateHTTPResponse(response, data: data)
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let content = ResponseNormalizer.string(at: ["choices", "0", "message", "content"], in: raw) else {
            throw ProviderError.invalidResponse("missing choices[0].message.content")
        }
        return try ResponseNormalizer.normalizeText(content)
    }
}
